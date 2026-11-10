import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/audio_track.dart';
import '../models/photo_layer.dart';
import '../models/text_layer.dart';
import '../models/video_project.dart';
import '../services/media_storage_service.dart';
import 'projects_provider.dart';

final currentProjectProvider = StateNotifierProvider<ProjectNotifier, VideoProject>((ref) {
  return ProjectNotifier(ref);
});

final selectedPhotoIndexProvider = StateProvider<int>((ref) => 0);
final playheadMsProvider = StateProvider<double>((ref) => 0.0);
final isPlayingProvider = StateProvider<bool>((ref) => false);

class ProjectNotifier extends StateNotifier<VideoProject> {
  final Ref _ref;

  // ==========================================
  // ✅ НОВОЕ: Стек истории для Undo/Redo
  // ==========================================
  final List<VideoProject> _history = [];
  int _historyIndex = -1;
  bool _pending = false; // текущее состояние ещё не в истории
  String? _lastOp; // для склейки непрерывных изменений (слайдеры)
  int _lastOpTime = 0;
  int _batchDepth = 0; // пакетные изменения (умный монтаж, бит-синк)
  bool _batchDirty = false;

  static const int _maxHistory = 20; // максимум 20 шагов назад
  static const int _coalesceMs = 800; // окно склейки для слайдеров

  ProjectNotifier(this._ref)
      : super(VideoProject(
          id: const Uuid().v4(),
          name: 'Новый проект',
          photos: [],
          texts: [],
        )) {
    _history.add(state);
    _historyIndex = 0;
  }

  // ==========================================
  // ✅ Внутренняя механика истории
  // ==========================================

  /// Отметить начало изменения.
  /// [op] — имя непрерывной операции (слайдер); одинаковые [op]
  /// в пределах окна склеиваются в ОДИН шаг истории.
  void _commitHistory({String? op}) {
    if (_batchDepth > 0) {
      _batchDirty = true;
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (op != null && op == _lastOp && now - _lastOpTime < _coalesceMs) {
      _lastOpTime = now;
      _pending = true;
      return;
    }
    _flushPending();
    _lastOp = op;
    _lastOpTime = now;
    _pending = true;
  }

  /// Дописать текущее состояние в историю
  void _flushPending() {
    if (!_pending) return;
    _pending = false;
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(state);
    _historyIndex = _history.length - 1;
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
      _historyIndex--;
    }
  }

  /// Начало пакетного изменения (умный монтаж, синхрон по битам)
  void beginBatch() {
    if (_batchDepth == 0) {
      _flushPending();
      _batchDirty = false;
    }
    _batchDepth++;
  }

  /// Конец пакетного изменения: всё пакетом = ОДИН шаг истории
  void endBatch() {
    if (_batchDepth > 0) _batchDepth--;
    if (_batchDepth == 0 && _batchDirty) {
      _batchDirty = false;
      _pending = true;
      _lastOp = null;
    }
  }

  // ==========================================
  // ✅ Публичные Undo/Redo
  // ==========================================

  bool get canUndo => _pending || _historyIndex > 0;
  bool get canRedo => !_pending && _historyIndex < _history.length - 1;

  void undo() {
    _flushPending();
    if (_historyIndex <= 0) return;
    _historyIndex--;
    state = _history[_historyIndex];
    _lastOp = null;
    _clampSelection();
    print('↩️ Undo: шаг $_historyIndex из ${_history.length - 1}');
  }

  void redo() {
    _flushPending();
    if (_historyIndex >= _history.length - 1) return;
    _historyIndex++;
    state = _history[_historyIndex];
    _lastOp = null;
    _clampSelection();
    print('↪️ Redo: шаг $_historyIndex из ${_history.length - 1}');
  }

  /// Защищаем индексы/плейхед после отката
  void _clampSelection() {
    final count = state.photos.length;
    if (count == 0) {
      _ref.read(selectedPhotoIndexProvider.notifier).state = 0;
      _ref.read(playheadMsProvider.notifier).state = 0.0;
      return;
    }
    final cur = _ref.read(selectedPhotoIndexProvider);
    if (cur >= count) {
      _ref.read(selectedPhotoIndexProvider.notifier).state = count - 1;
    }
    final total = state.photos.fold<int>(0, (s, p) => s + p.durationMilliseconds);
    final ph = _ref.read(playheadMsProvider);
    if (ph > total) {
      _ref.read(playheadMsProvider.notifier).state = total.toDouble();
    }
  }

  // ==========================================
  // Управление проектом
  // ==========================================

  void setProject(VideoProject project) {
    _commitHistory();
    state = project;
    _ref.read(selectedPhotoIndexProvider.notifier).state = 0;
    _ref.read(playheadMsProvider.notifier).state = 0.0;
    _ref.read(isPlayingProvider.notifier).state = false;
  }

  void loadProject(VideoProject project) => setProject(project);

  void reset() {
    _commitHistory();
    state = VideoProject(id: const Uuid().v4(), name: 'Новый проект', photos: [], texts: []);
    _ref.read(selectedPhotoIndexProvider.notifier).state = 0;
    _ref.read(playheadMsProvider.notifier).state = 0.0;
    _ref.read(isPlayingProvider.notifier).state = false;
  }

  void clearProject() => reset();

  void setName(String name) {
    // Печатаемый текст: не создаём шаг на каждую букву,
    // но помечаем состояние как "ожидающее записи"
    state = state.copyWith(name: name);
    _pending = true;
  }

  // ==========================================
  // Фото
  // ==========================================

  Future<void> addPhotosFromGallery() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 90, maxWidth: 2048, maxHeight: 2048);
    if (images.isEmpty) return;

    _commitHistory();
    final storage = _ref.read(mediaStorageProvider);
    final newPhotos = <PhotoLayer>[];

    for (final img in images) {
      try {
        final storedPath = await storage.importPhoto(img.path);
        print('📸 ФОТО СОХРАНЕНО В ПАПКУ: $storedPath');
        try {
          final cacheFile = File(img.path);
          if (cacheFile.existsSync()) cacheFile.deleteSync();
        } catch (_) {}

        newPhotos.add(PhotoLayer(
          imagePath: storedPath, durationMilliseconds: 3000, transition: TransitionType.fade,
          filter: FilterType.none, entranceAnimation: EntranceAnimation.none, entranceDurationMs: 500,
          fitMode: FitMode.cover, scale: 1.0, offsetX: 0.0, offsetY: 0.0,
          backgroundType: BackgroundType.blur, backgroundColor: 0xFF000000,
        ));
      } catch (e) {
        print('❌ ОШИБКА СОХРАНЕНИЯ ФОТО: $e');
      }
    }

    if (newPhotos.isEmpty) return;
    final updatedPhotos = [...state.photos, ...newPhotos];
    state = state.copyWith(photos: updatedPhotos);
    _ref.read(selectedPhotoIndexProvider.notifier).state = updatedPhotos.length - 1;
  }

  void addPhotoByPath(String path) {
    _commitHistory();
    final newPhoto = PhotoLayer(
      imagePath: path, durationMilliseconds: 3000, transition: TransitionType.fade,
      filter: FilterType.none, entranceAnimation: EntranceAnimation.none, entranceDurationMs: 500,
      fitMode: FitMode.cover, scale: 1.0, offsetX: 0.0, offsetY: 0.0,
      backgroundType: BackgroundType.blur, backgroundColor: 0xFF000000,
    );
    final updatedPhotos = [...state.photos, newPhoto];
    state = state.copyWith(photos: updatedPhotos);
    _ref.read(selectedPhotoIndexProvider.notifier).state = updatedPhotos.length - 1;
  }

  void removePhoto(int index) {
    if (index < 0 || index >= state.photos.length) return;
    _commitHistory();
    final newPhotos = List<PhotoLayer>.from(state.photos)..removeAt(index);
    state = state.copyWith(photos: newPhotos);
    final current = _ref.read(selectedPhotoIndexProvider);
    if (newPhotos.isEmpty) {
      _ref.read(selectedPhotoIndexProvider.notifier).state = 0;
    } else if (current >= newPhotos.length) {
      _ref.read(selectedPhotoIndexProvider.notifier).state = newPhotos.length - 1;
    }
  }

  void updatePhotoDuration(int index, int durationMs) {
    if (index < 0 || index >= state.photos.length) return;
    _commitHistory(op: 'dur'); // склейка: слайдер = 1 шаг
    final newPhotos = List<PhotoLayer>.from(state.photos);
    newPhotos[index] = newPhotos[index].copyWith(durationMilliseconds: durationMs);
    state = state.copyWith(photos: newPhotos);
  }

  void updatePhotoTransition(int index, TransitionType transition, {bool applyToAll = false}) {
    if (index < 0 || index >= state.photos.length) return;
    _commitHistory();
    final newPhotos = List<PhotoLayer>.from(state.photos);
    if (applyToAll) {
      for (int i = 0; i < newPhotos.length; i++) newPhotos[i] = newPhotos[i].copyWith(transition: transition);
    } else {
      newPhotos[index] = newPhotos[index].copyWith(transition: transition);
    }
    state = state.copyWith(photos: newPhotos);
  }

  void updatePhotoTransitionDuration(int index, int durationMs, {bool applyToAll = false}) {
    if (index < 0 || index >= state.photos.length) return;
    final clamped = durationMs.clamp(300, 1500);
    _commitHistory(op: 'trdur');
    final newPhotos = List<PhotoLayer>.from(state.photos);
    if (applyToAll) {
      for (int i = 0; i < newPhotos.length; i++) newPhotos[i] = newPhotos[i].copyWith(transitionDurationMs: clamped);
    } else {
      newPhotos[index] = newPhotos[index].copyWith(transitionDurationMs: clamped);
    }
    state = state.copyWith(photos: newPhotos);
  }

  void updatePhotoLiveMotion(int index, LiveMotion motion, {bool applyToAll = false}) {
    if (index < 0 || index >= state.photos.length) return;
    _commitHistory();
    final newPhotos = List<PhotoLayer>.from(state.photos);
    if (applyToAll) {
      for (int i = 0; i < newPhotos.length; i++) newPhotos[i] = newPhotos[i].copyWith(liveMotion: motion);
    } else {
      newPhotos[index] = newPhotos[index].copyWith(liveMotion: motion);
    }
    state = state.copyWith(photos: newPhotos);
  }

  void updatePhotoFilter(int index, FilterType filter, {bool applyToAll = false}) {
    if (index < 0 || index >= state.photos.length) return;
    _commitHistory();
    final newPhotos = List<PhotoLayer>.from(state.photos);
    if (applyToAll) {
      for (int i = 0; i < newPhotos.length; i++) newPhotos[i] = newPhotos[i].copyWith(filter: filter);
    } else {
      newPhotos[index] = newPhotos[index].copyWith(filter: filter);
    }
    state = state.copyWith(photos: newPhotos);
  }

  void updatePhotoOverlay(int index, OverlayType type, double intensity, {bool applyToAll = false}) {
    if (index < 0 || index >= state.photos.length) return;
    _commitHistory();
    final newPhotos = List<PhotoLayer>.from(state.photos);
    if (applyToAll) {
      for (int i = 0; i < newPhotos.length; i++) {
        newPhotos[i] = newPhotos[i].copyWith(overlayType: type, overlayIntensity: intensity);
      }
    } else {
      newPhotos[index] = newPhotos[index].copyWith(overlayType: type, overlayIntensity: intensity);
    }
    state = state.copyWith(photos: newPhotos);
  }

  void updatePhotoEntranceAnimation(int index, EntranceAnimation animation, {bool applyToAll = false}) {
    if (index < 0 || index >= state.photos.length) return;
    _commitHistory();
    final newPhotos = List<PhotoLayer>.from(state.photos);
    if (applyToAll) {
      for (int i = 0; i < newPhotos.length; i++) newPhotos[i] = newPhotos[i].copyWith(entranceAnimation: animation);
    } else {
      newPhotos[index] = newPhotos[index].copyWith(entranceAnimation: animation);
    }
    state = state.copyWith(photos: newPhotos);
  }

  void updatePhotoEntranceDuration(int index, int durationMs, {bool applyToAll = false}) {
    if (index < 0 || index >= state.photos.length) return;
    _commitHistory(op: 'endur');
    final newPhotos = List<PhotoLayer>.from(state.photos);
    if (applyToAll) {
      for (int i = 0; i < newPhotos.length; i++) newPhotos[i] = newPhotos[i].copyWith(entranceDurationMs: durationMs);
    } else {
      newPhotos[index] = newPhotos[index].copyWith(entranceDurationMs: durationMs);
    }
    state = state.copyWith(photos: newPhotos);
  }

  void updateFormat(int formatId) {
    if (formatId < 0 || formatId >= 4) return;
    _commitHistory();
    state = state.copyWith(formatId: formatId);
  }

  void updateOverlay(OverlayType type) {
    _commitHistory();
    state = state.copyWith(overlayType: type);
  }

  void updateOverlayIntensity(double value) {
    _commitHistory(op: 'ovint');
    state = state.copyWith(overlayIntensity: value.clamp(0.1, 1.0));
  }

  void updateCinematicIntensity(double value) {
    _commitHistory(op: 'cinint');
    state = state.copyWith(cinematicIntensity: value.clamp(0.0, 1.0));
  }

  void updatePhotoFit({
    required int index,
    FitMode? fitMode,
    double? scale,
    double? offsetX,
    double? offsetY,
    BackgroundType? backgroundType,
    int? backgroundColor,
  }) {
    if (index < 0 || index >= state.photos.length) return;
    _commitHistory();
    final newPhotos = List<PhotoLayer>.from(state.photos);
    newPhotos[index] = newPhotos[index].copyWith(
      fitMode: fitMode, scale: scale, offsetX: offsetX, offsetY: offsetY,
      backgroundType: backgroundType, backgroundColor: backgroundColor,
    );
    state = state.copyWith(photos: newPhotos);
  }

  void reorderPhotos(int oldIndex, int newIndex) {
    _commitHistory();
    final newPhotos = List<PhotoLayer>.from(state.photos);
    if (newIndex > oldIndex) newIndex--;
    final item = newPhotos.removeAt(oldIndex);
    newPhotos.insert(newIndex, item);
    state = state.copyWith(photos: newPhotos);
  }

  // ==========================================
  // Текст
  // ==========================================

  void addText(TextLayer layer) {
    _commitHistory();
    state = state.copyWith(texts: [...state.texts, layer]);
  }

  void updateText(int index, TextLayer layer) {
    if (index < 0 || index >= state.texts.length) return;
    _commitHistory();
    final newTexts = List<TextLayer>.from(state.texts);
    newTexts[index] = layer;
    state = state.copyWith(texts: newTexts);
  }

  void removeText(int index) {
    if (index < 0 || index >= state.texts.length) return;
    _commitHistory();
    final newTexts = List<TextLayer>.from(state.texts)..removeAt(index);
    state = state.copyWith(texts: newTexts);
  }

  // ==========================================
  // Аудио
  // ==========================================

  void setAudioTrack(AudioTrack track) {
    _commitHistory();
    state = state.copyWith(audioTrack: track);
  }

  void removeAudioTrack() {
    _commitHistory();
    // ✅ ИСПРАВЛЕНО: сохраняем оверлеи/интенсивности (раньше терялись)
    state = VideoProject(
      id: state.id,
      name: state.name,
      photos: state.photos,
      texts: state.texts,
      audioTrack: null,
      createdAt: state.createdAt,
      formatId: state.formatId,
      overlayType: state.overlayType,
      overlayIntensity: state.overlayIntensity,
      cinematicIntensity: state.cinematicIntensity,
    );
  }

  void updateAudioVolume(double volume) {
    if (state.audioTrack == null) return;
    _commitHistory(op: 'vol');
    state = state.copyWith(audioTrack: state.audioTrack!.copyWith(volume: volume));
  }

  void updateAudioStartTime(double startTime) {
    if (state.audioTrack == null) return;
    _commitHistory(op: 'astart');
    state = state.copyWith(audioTrack: state.audioTrack!.copyWith(startTime: startTime));
  }

  // ==========================================
  // 🎨 AI Гармонизация цвета
  // ==========================================
  void applyHarmonizationMatrices(Map<String, List<double>> matrices) {
    if (matrices.isEmpty) return;
    _commitHistory(); // одно массовое изменение = один шаг Undo

    final newPhotos = List<PhotoLayer>.from(state.photos);
    bool hasChanges = false;

    for (int i = 0; i < newPhotos.length; i++) {
      final matrix = matrices[newPhotos[i].imagePath];
      if (matrix != null) {
        newPhotos[i] = newPhotos[i].copyWith(harmonizationMatrix: matrix);
        hasChanges = true;
      }
    }

    if (hasChanges) {
      state = state.copyWith(photos: newPhotos);
    }
  }
}