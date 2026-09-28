import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_project.dart';
import '../repositories/project_repository.dart';

/// Провайдер репозитория проектов (Hive)
final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository();
});

/// Провайдер списка всех проектов
final projectsProvider = StateNotifierProvider<ProjectsNotifier, List<VideoProject>>((ref) {
  return ProjectsNotifier(ref.watch(projectRepositoryProvider));
});

class ProjectsNotifier extends StateNotifier<List<VideoProject>> {
  ProjectsNotifier(this._repo) : super([]) {
    _load();
  }

  final ProjectRepository _repo;

  void _load() {
    state = _repo.getAllProjects();
  }

  void refresh() => _load();

  Future<void> save(VideoProject project) async {
    await _repo.saveProject(project);
    _load();
  }

  Future<void> delete(String id) async {
    await _repo.deleteProject(id);
    _load();
  }

  Future<void> rename(String id, String newName) async {
    final project = _repo.getProject(id);
    if (project == null) return;
    final updated = VideoProject(
      id: project.id,
      name: newName,
      createdAtMilliseconds: project.createdAtMilliseconds,
      photos: project.photos,
      texts: project.texts,
      template: project.template,
    );
    await _repo.saveProject(updated);
    _load();
  }
}