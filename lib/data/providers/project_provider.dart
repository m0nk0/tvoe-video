import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
export 'media_storage_provider.dart';
import '../models/audio_track.dart';
import '../models/keyframe.dart';
import '../models/photo_layer.dart';
import '../models/text_layer.dart';
import '../models/video_project.dart';
import '../services/media_storage_service.dart';
import 'media_storage_provider.dart';
import 'projects_provider.dart';


final currentProjectProvider = StateNotifierProvider<ProjectNotifier, VideoProject>((ref) {
  return ProjectNotifier(ref);
});

final selectedPhotoIndexProvider = StateProvider<int>((ref) => 0);
final playheadMsProvider = StateProvider<double>((ref) => 0.0);
final isPlayingProvider = StateProvider<bool>((ref) => false);
// ✅ Фаза 1b: выделенный текстовый блок (null = выделен видео-клип)
final selectedTextIndexProvider = StateProvider<int?>((ref) => null);
// ✅ Под-срез 2: выделенный кейфрейм [photoIndex, kfIndex] или null
final selectedKeyframeProvider = StateProvider<List<int>?>((ref) => null);

class ProjectNotifier extends StateNotifier<VideoProject> {
  final Ref _ref;

  // ==========================================
  // ✅ Стек истории для Undo/Redo
  // ==========================================
  final List<VideoProject> _history = [];
  int _historyIndex = -1;
  bool _pending = false;
  String? _lastOp;
  int _lastOpTime = 0;
  int _batchDepth = 0;
  bool _batchDirty = false;

  static const int _maxHistory = 20;
  static const int _coalesceMs = 800;

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

  void beginBatch() {
    if (_batchDepth == 0) {
      _flushPending();
      _batchDirty = false;
    }
    _batchDepth++;
  }

  void endBatch() {
    if (_batchDepth > 0) _batchDepth--;
    if (_batchDepth == 0 && _batchDirty) {
      _batchDirty = false;
      _pending = true;
      _lastOp = null;
    }
  }

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
    final tCur = _ref.read(selectedTextIndexProvider);
    if (tCur != null && tCur >= state.texts.length) {
      _ref.read(selectedTextIndexProvider.notifier).state =
          state.texts.isEmpty ? null : state.texts.length - 1;
    }
    // ✅ защищаем выделение кейфрейма после отката
    final kCur = _ref.read(selectedKeyframeProvider);
    if (kCur != null &&
        (kCur[0] >= count || kCur[1] >= state.photos[kCur[0]].keyframes.length)) {
      _ref.read(selectedKeyframeProvider.notifier).state = null;
    }
  }

  // ==========================================
  // Управление проектом
  // ==========================================

  void setProject(VideoProject project) {
    _commitHistory();
    state = project;
    _ref.read(selectedPhotoIndexProvider.notifier).state = 0;
    _ref.read(selectedTextIndexProvider.notifier).state = null;
    _ref.read(selectedKeyframeProvider.notifier).state = null;
    _ref.read(playheadMsProvider.notifier).state = 0.0;
    _ref.read(isPlayingProvider.notifier).state = false;
  }

  void loadProject(VideoProject project) => setProject(project);

  void reset() {
    _commitHistory();
    state = VideoProject(id: const Uuid().v4(), name: 'Новый проект', photos: [], texts: []);
    _ref.read(selectedPhotoIndexProvider.notifier).state = 0;
    _ref.read(selectedTextIndexProvider.notifier).state = null;
    _ref.read(selectedKeyframeProvider.notifier).state = null;
    _ref.read(playheadMsProvider.notifier).state = 0.0;
    _ref.read(isPlayingProvider.notifier).state = false;
  }

  void clearProject() => reset();

  void setName(String name) {
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

        if (storedPath == null) {
          print('⚠️ Пропуск фото (importPhoto вернул null): ${img.path}');
          continue;
        }

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
    _ref.read(selectedKeyframeProvider.notifier).state = null;
  }

  void updatePhotoDuration(int index, int durationMs) {
    if (index < 0 || index >= state.photos.length) return;
    _commitHistory(op: 'dur');
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
  // ✅ Фаза 1a: дублирование и разделение кадра
  // ==========================================

  void duplicatePhoto(int index) {
    if (index < 0 || index >= state.photos.length) return;
    _commitHistory();
    final copy = state.photos[index];
    final newPhotos = List<PhotoLayer>.from(state.photos)..insert(index + 1, copy);
    state = state.copyWith(photos: newPhotos);
    _ref.read(selectedPhotoIndexProvider.notifier).state = index + 1;
  }

  void splitPhoto(int index, int atMs) {
    if (index < 0 || index >= state.photos.length) return;
    final p = state.photos[index];
    if (atMs <= 0 || atMs >= p.durationMilliseconds) return;
    _commitHistory();
    final left = p.copyWith(durationMilliseconds: atMs);
    final right = p.copyWith(durationMilliseconds: p.durationMilliseconds - atMs);
    final newPhotos = List<PhotoLayer>.from(state.photos);
    newPhotos[index] = left;
    newPhotos.insert(index + 1, right);
    state = state.copyWith(photos: newPhotos);
    _ref.read(selectedPhotoIndexProvider.notifier).state = index + 1;
    _ref.read(selectedKeyframeProvider.notifier).state = null;
  }

  // ==========================================
  // ✅ Фаза 1b: перемещение клипа и дубль текста
  // ==========================================

  void movePhoto(int from, int to) {
    if (from == to) return;
    if (from < 0 || from >= state.photos.length) return;
    _commitHistory();
    final list = List<PhotoLayer>.from(state.photos);
    final item = list.removeAt(from);
    final target = to.clamp(0, list.length);
    list.insert(target, item);
    state = state.copyWith(photos: list);
    _ref.read(selectedPhotoIndexProvider.notifier).state = target;
    _ref.read(selectedTextIndexProvider.notifier).state = null;
    _ref.read(selectedKeyframeProvider.notifier).state = null;
  }

  void duplicateText(int index) {
    if (index < 0 || index >= state.texts.length) return;
    _commitHistory();
    final t = state.texts[index];
    final dur = t.endTimeMilliseconds - t.startTimeMilliseconds;
    final copy = TextLayer(
      text: t.text,
      fontFamily: t.fontFamily,
      fontSize: t.fontSize,
      colorValue: t.colorValue,
      startTimeMilliseconds: t.endTimeMilliseconds,
      endTimeMilliseconds: t.endTimeMilliseconds + dur,
      animation: t.animation,
      positionX: t.positionX,
      positionY: t.positionY,
    );
    state = state.copyWith(texts: [...state.texts, copy]);
    _ref.read(selectedTextIndexProvider.notifier).state = state.texts.length;
  }

  // ==========================================
  // ✅ Кейфреймы: CRUD
  // ==========================================

  void addKeyframe(int photoIndex, Keyframe kf) {
    if (photoIndex < 0 || photoIndex >= state.photos.length) return;
    _commitHistory();
    final np = List<PhotoLayer>.from(state.photos);
    final p = np[photoIndex];
    final kfs = [...p.keyframes, kf]..sort((a, b) => a.tMs.compareTo(b.tMs));
    np[photoIndex] = p.copyWith(keyframes: kfs);
    state = state.copyWith(photos: np);
  }

  // ✅ БЕЗ сортировки во время drag — иначе индекс «перепрыгивает» на соседний ромбик и drag залипает
  void updateKeyframe(int photoIndex, int kfIndex, Keyframe kf) {
    if (photoIndex < 0 || photoIndex >= state.photos.length) return;
    final p = state.photos[photoIndex];
    if (kfIndex < 0 || kfIndex >= p.keyframes.length) return;
    _commitHistory();
    final np = List<PhotoLayer>.from(state.photos);
    final kfs = List<Keyframe>.from(p.keyframes);
    kfs[kfIndex] = kf;
    np[photoIndex] = p.copyWith(keyframes: kfs);
    state = state.copyWith(photos: np);
  }

  // ✅ Сортивка ПОСЛЕ drag + восстановление выделения по объекту
  void normalizeKeyframes(int photoIndex) {
    if (photoIndex < 0 || photoIndex >= state.photos.length) return;
    final p = state.photos[photoIndex];
    if (p.keyframes.length < 2) return;
    final sel = _ref.read(selectedKeyframeProvider);
    Keyframe? selKf;
    if (sel != null && sel[0] == photoIndex && sel[1] < p.keyframes.length) {
      selKf = p.keyframes[sel[1]];
    }
    final sorted = List<Keyframe>.from(p.keyframes)..sort((a, b) => a.tMs.compareTo(b.tMs));
    final np = List<PhotoLayer>.from(state.photos);
    np[photoIndex] = p.copyWith(keyframes: sorted);
    state = state.copyWith(photos: np);
    if (selKf != null) {
      final newIdx = sorted.indexOf(selKf);
      if (newIdx >= 0) {
        _ref.read(selectedKeyframeProvider.notifier).state = [photoIndex, newIdx];
      }
    }
  }

  void removeKeyframe(int photoIndex, int kfIndex) {
    if (photoIndex < 0 || photoIndex >= state.photos.length) return;
    final p = state.photos[photoIndex];
    if (kfIndex < 0 || kfIndex >= p.keyframes.length) return;
    _commitHistory();
    final np = List<PhotoLayer>.from(state.photos);
    final kfs = List<Keyframe>.from(p.keyframes)..removeAt(kfIndex);
    np[photoIndex] = p.copyWith(keyframes: kfs);
    state = state.copyWith(photos: np);
  }
    void setKeyframes(int photoIndex, List<Keyframe> kfs) {
    if (photoIndex < 0 || photoIndex >= state.photos.length) return;
    _commitHistory();
    final np = List<PhotoLayer>.from(state.photos);
    np[photoIndex] = np[photoIndex].copyWith(
      keyframes: List<Keyframe>.from(kfs)..sort((a, b) => a.tMs.compareTo(b.tMs)),
    );
    state = state.copyWith(photos: np);
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
    final tCur = _ref.read(selectedTextIndexProvider);
    if (tCur != null) {
      if (newTexts.isEmpty) {
        _ref.read(selectedTextIndexProvider.notifier).state = null;
      } else if (tCur >= newTexts.length) {
        _ref.read(selectedTextIndexProvider.notifier).state = newTexts.length - 1;
      }
    }
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
    _commitHistory();

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