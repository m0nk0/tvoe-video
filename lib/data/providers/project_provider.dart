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

  ProjectNotifier(this._ref)
      : super(VideoProject(
          id: const Uuid().v4(),
          name: 'Новый проект',
          photos: [],
          texts: [],
        ));

  void setProject(VideoProject project) {
    state = project;
    _ref.read(selectedPhotoIndexProvider.notifier).state = 0;
    _ref.read(playheadMsProvider.notifier).state = 0.0;
    _ref.read(isPlayingProvider.notifier).state = false;
  }

  void loadProject(VideoProject project) => setProject(project);
  void reset() {
    state = VideoProject(id: const Uuid().v4(), name: 'Новый проект', photos: [], texts: []);
    _ref.read(selectedPhotoIndexProvider.notifier).state = 0;
    _ref.read(playheadMsProvider.notifier).state = 0.0;
    _ref.read(isPlayingProvider.notifier).state = false;
  }
  void clearProject() => reset();
  void setName(String name) { state = state.copyWith(name: name); }

  Future<void> addPhotosFromGallery() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 90, maxWidth: 2048, maxHeight: 2048);
    if (images.isEmpty) return;

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
    final newPhotos = List<PhotoLayer>.from(state.photos);
    newPhotos[index] = newPhotos[index].copyWith(durationMilliseconds: durationMs);
    state = state.copyWith(photos: newPhotos);
  }

  void updatePhotoTransition(int index, TransitionType transition, {bool applyToAll = false}) {
    if (index < 0 || index >= state.photos.length) return;
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
    final newPhotos = List<PhotoLayer>.from(state.photos);
    if (applyToAll) {
      for (int i = 0; i < newPhotos.length; i++) newPhotos[i] = newPhotos[i].copyWith(filter: filter);
    } else {
      newPhotos[index] = newPhotos[index].copyWith(filter: filter);
    }
    state = state.copyWith(photos: newPhotos);
  }

  void updatePhotoEntranceAnimation(int index, EntranceAnimation animation, {bool applyToAll = false}) {
    if (index < 0 || index >= state.photos.length) return;
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
    state = state.copyWith(formatId: formatId);
  }

  void updateOverlay(OverlayType type) { state = state.copyWith(overlayType: type); }
  void updateOverlayIntensity(double value) { state = state.copyWith(overlayIntensity: value.clamp(0.1, 1.0)); }
  void updateCinematicIntensity(double value) { state = state.copyWith(cinematicIntensity: value.clamp(0.0, 1.0)); }

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
    final newPhotos = List<PhotoLayer>.from(state.photos);
    newPhotos[index] = newPhotos[index].copyWith(
      fitMode: fitMode, scale: scale, offsetX: offsetX, offsetY: offsetY,
      backgroundType: backgroundType, backgroundColor: backgroundColor,
    );
    state = state.copyWith(photos: newPhotos);
  }

  void reorderPhotos(int oldIndex, int newIndex) {
    final newPhotos = List<PhotoLayer>.from(state.photos);
    if (newIndex > oldIndex) newIndex--;
    final item = newPhotos.removeAt(oldIndex);
    newPhotos.insert(newIndex, item);
    state = state.copyWith(photos: newPhotos);
  }

  void addText(TextLayer layer) { state = state.copyWith(texts: [...state.texts, layer]); }
  void updateText(int index, TextLayer layer) {
    if (index < 0 || index >= state.texts.length) return;
    final newTexts = List<TextLayer>.from(state.texts);
    newTexts[index] = layer;
    state = state.copyWith(texts: newTexts);
  }
  void removeText(int index) {
    if (index < 0 || index >= state.texts.length) return;
    final newTexts = List<TextLayer>.from(state.texts)..removeAt(index);
    state = state.copyWith(texts: newTexts);
  }

  void setAudioTrack(AudioTrack track) { state = state.copyWith(audioTrack: track); }
  void removeAudioTrack() {
    state = VideoProject(
      id: state.id, name: state.name, photos: state.photos, texts: state.texts,
      audioTrack: null, createdAt: state.createdAt, formatId: state.formatId,
    );
  }
  void updateAudioVolume(double volume) {
    if (state.audioTrack == null) return;
    state = state.copyWith(audioTrack: state.audioTrack!.copyWith(volume: volume));
  }
  void updateAudioStartTime(double startTime) {
    if (state.audioTrack == null) return;
    state = state.copyWith(audioTrack: state.audioTrack!.copyWith(startTime: startTime));
  }

  // ==========================================
  // 🎨 AI Гармонизация цвета
  // ==========================================
  /// Применяет сгенерированные матрицы коррекции к фото проекта.
  void applyHarmonizationMatrices(Map<String, List<double>> matrices) {
    if (matrices.isEmpty) return;

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