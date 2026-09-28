import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../models/video_project.dart';
import '../models/photo_layer.dart';
import '../models/text_layer.dart';

/// Провайдер текущего редактируемого проекта
final currentProjectProvider = StateNotifierProvider<ProjectNotifier, VideoProject>((ref) {
  return ProjectNotifier();
});

/// Индекс выбранного кадра на таймлайне
final selectedPhotoIndexProvider = StateProvider<int>((ref) => 0);

/// Позиция плейхеда в миллисекундах на глобальной шкале видео
final playheadMsProvider = StateProvider<double>((ref) => 0);

/// Идёт ли воспроизведение
final isPlayingProvider = StateProvider<bool>((ref) => false);

class ProjectNotifier extends StateNotifier<VideoProject> {
  ProjectNotifier() : super(VideoProject.empty());

  void loadProject(VideoProject project) {
    state = project;
  }

  void clearProject() {
    state = VideoProject.empty();
  }

  /// Добавление фото из галереи
  Future<void> addPhotosFromGallery() async {
    final picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage(
      imageQuality: 85,
      requestFullMetadata: false,
    );

    if (images.isNotEmpty) {
      final newPhotos = images
          .map((file) => PhotoLayer(
                imagePath: file.path,
                durationMilliseconds: 3000,
              ))
          .toList();
      state = _copyWith(photos: [...state.photos, ...newPhotos]);
    }
  }

  /// Удаление фото по индексу
  void removePhoto(int index) {
    if (index < 0 || index >= state.photos.length) return;
    final updated = List<PhotoLayer>.from(state.photos)..removeAt(index);
    state = _copyWith(photos: updated);
  }

  /// Изменение длительности кадра (в миллисекундах)
  void updatePhotoDuration(int index, int milliseconds) {
    if (index < 0 || index >= state.photos.length) return;
    final old = state.photos[index];
    final updated = List<PhotoLayer>.from(state.photos);
    updated[index] = PhotoLayer(
      imagePath: old.imagePath,
      durationMilliseconds: milliseconds,
      transition: old.transition,
      scale: old.scale,
      positionX: old.positionX,
      positionY: old.positionY,
    );
    state = _copyWith(photos: updated);
  }

  /// Изменение перехода кадра
  void updatePhotoTransition(int index, TransitionType transition) {
    if (index < 0 || index >= state.photos.length) return;
    final old = state.photos[index];
    final updated = List<PhotoLayer>.from(state.photos);
    updated[index] = PhotoLayer(
      imagePath: old.imagePath,
      durationMilliseconds: old.durationMilliseconds,
      transition: transition,
      scale: old.scale,
      positionX: old.positionX,
      positionY: old.positionY,
    );
    state = _copyWith(photos: updated);
  }

  /// Изменение порядка фото (drag-and-drop)
  void reorderPhotos(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final updated = List<PhotoLayer>.from(state.photos);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    state = _copyWith(photos: updated);
  }

  /// Добавление текстового слоя
  void addText(TextLayer layer) {
    state = _copyWith(texts: [...state.texts, layer]);
  }

  /// Обновление текстового слоя
  void updateText(int index, TextLayer layer) {
    if (index < 0 || index >= state.texts.length) return;
    final updated = List<TextLayer>.from(state.texts);
    updated[index] = layer;
    state = _copyWith(texts: updated);
  }

  /// Удаление текстового слоя
  void removeText(int index) {
    if (index < 0 || index >= state.texts.length) return;
    final updated = List<TextLayer>.from(state.texts)..removeAt(index);
    state = _copyWith(texts: updated);
  }

  /// Универсальное копирование состояния
  VideoProject _copyWith({List<PhotoLayer>? photos, List<TextLayer>? texts}) {
    return VideoProject(
      id: state.id,
      name: state.name,
      createdAtMilliseconds: state.createdAtMilliseconds,
      photos: photos ?? state.photos,
      texts: texts ?? state.texts,
      template: state.template,
    );
  }
}