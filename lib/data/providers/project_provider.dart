import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../models/video_project.dart';
import '../models/photo_layer.dart';

/// Провайдер текущего редактируемого проекта
final currentProjectProvider = StateNotifierProvider<ProjectNotifier, VideoProject>((ref) {
  return ProjectNotifier();
});

/// Индекс выбранного кадра на таймлайне
final selectedPhotoIndexProvider = StateProvider<int>((ref) => 0);

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
      state = _copyWithPhotos([...state.photos, ...newPhotos]);
    }
  }

  /// Удаление фото по индексу
  void removePhoto(int index) {
    if (index < 0 || index >= state.photos.length) return;
    final updated = List<PhotoLayer>.from(state.photos)..removeAt(index);
    state = _copyWithPhotos(updated);
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
    state = _copyWithPhotos(updated);
  }

  /// Изменение порядка фото (drag-and-drop)
  void reorderPhotos(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final updated = List<PhotoLayer>.from(state.photos);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    state = _copyWithPhotos(updated);
  }

  VideoProject _copyWithPhotos(List<PhotoLayer> photos) {
    return VideoProject(
      id: state.id,
      name: state.name,
      createdAtMilliseconds: state.createdAtMilliseconds,
      photos: photos,
      texts: state.texts,
      template: state.template,
    );
  }
}