import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/video_project.dart';
import '../repositories/project_repository.dart';

// ==========================================
// Провайдер репозитория (переопределяется в main.dart)
// ==========================================
final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  throw UnimplementedError('projectRepositoryProvider must be overridden in main.dart');
});

// ==========================================
// Список всех проектов
// ==========================================
final projectsProvider =
    StateNotifierProvider<ProjectsNotifier, List<VideoProject>>((ref) {
  return ProjectsNotifier(ref.watch(projectRepositoryProvider));
});

class ProjectsNotifier extends StateNotifier<List<VideoProject>> {
  final ProjectRepository _repo;

  ProjectsNotifier(this._repo) : super([]) {
    loadAll();
  }

  /// Загрузить все проекты (метод синхронный в репозитории)
  void loadAll() {
    state = _repo.getAllProjects();
  }

  /// Перечитать список
  void refresh() => loadAll();

  /// Создать новый проект и сохранить его
  Future<VideoProject> createProject({String? name}) async {
    final project = VideoProject(
      id: const Uuid().v4(),
      name: name ?? 'Новый проект',
      photos: const [],
      texts: const [],
    );
    await _repo.saveProject(project);
    state = [project, ...state];
    return project;
  }

  /// Переименовать проект
  Future<void> rename(String id, String newName) async {
    final i = state.indexWhere((p) => p.id == id);
    if (i < 0) return;
    final updated = state[i].copyWith(name: newName);
    await _repo.saveProject(updated);
    state = [
      for (var j = 0; j < state.length; j++)
        if (j == i) updated else state[j]
    ];
  }

  /// Удалить проект
  Future<void> delete(String id) async {
    await _repo.deleteProject(id);
    state = state.where((p) => p.id != id).toList();
  }

  /// Очистить всё
  Future<void> clearAll() async {
    await _repo.clearAll();
    state = [];
  }
}