import 'package:hive/hive.dart';
import '../models/video_project.dart';

class ProjectRepository {
  static const String _boxName = 'projects';
  late Box<VideoProject> _box;

  Future<void> init() async {
    _box = await Hive.openBox<VideoProject>(_boxName);
  }

  List<VideoProject> getAllProjects() {
    final projects = _box.values.toList();
    projects.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return projects;
  }

  Future<void> saveProject(VideoProject project) async {
    await _box.put(project.id, project);
  }

  Future<void> deleteProject(String id) async {
    await _box.delete(id);
  }

  VideoProject? getProject(String id) {
    return _box.get(id);
  }

  Future<void> clearAll() async {
    await _box.clear();
  }
}