import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Сервис хранения медиафайлов проекта:
/// - клипы:  {documents}/tvoe_video/clips/
/// - музыка: {documents}/tvoe_video/music/
/// - фото:   {documents}/tvoe_video/photos/
class MediaStorageService {
  late Directory _clipsDir;
  late Directory _musicDir;
  late Directory _photosDir;

  Directory get clipsDir => _clipsDir;
  Directory get musicDir => _musicDir;
  Directory get photosDir => _photosDir;

  static const _musicExts = [
    'mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'wma', 'opus',
  ];

  static const _photoExts = [
    'jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic',
  ];

  /// Создаёт папки проекта при первом запуске
  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/tvoe_video');
    _clipsDir = Directory('${root.path}/clips');
    _musicDir = Directory('${root.path}/music');
    _photosDir = Directory('${root.path}/photos');
    if (!_clipsDir.existsSync()) _clipsDir.createSync(recursive: true);
    if (!_musicDir.existsSync()) _musicDir.createSync(recursive: true);
    if (!_photosDir.existsSync()) _photosDir.createSync(recursive: true);
  }

  /// Копирует аудиофайл в папку музыки проекта.
  Future<String> importMusic(String sourcePath, {String? title}) async {
    final src = File(sourcePath);
    if (!src.existsSync()) throw Exception('Файл не найден: $sourcePath');
    final ext = _extOf(sourcePath);
    final name =
        '${DateTime.now().microsecondsSinceEpoch}_${_safeName(title ?? 'track')}.$ext';
    final dest = File('${_musicDir.path}/$name');
    await src.copy(dest.path);
    return dest.path;
  }

  /// ✅ Копирует фото в папку фото проекта.
  /// Возвращает путь копии.
  Future<String> importPhoto(String sourcePath) async {
    final src = File(sourcePath);
    if (!src.existsSync()) throw Exception('Файл не найден: $sourcePath');
    final extRaw = _extOf(sourcePath);
    final ext = _photoExts.contains(extRaw) ? extRaw : 'jpg';
    final name =
        '${DateTime.now().microsecondsSinceEpoch}_${_safeName('photo')}.$ext';
    final dest = File('${_photosDir.path}/$name');
    await src.copy(dest.path);
    return dest.path;
  }

  /// Сохраняет экспортированный клип в папку клипов проекта.
  Future<String> saveClip(String sourcePath, {String? title}) async {
    final src = File(sourcePath);
    if (!src.existsSync()) throw Exception('Файл не найден: $sourcePath');
    final name =
        '${DateTime.now().microsecondsSinceEpoch}_${_safeName(title ?? 'clip')}.mp4';
    final dest = File('${_clipsDir.path}/$name');
    await src.copy(dest.path);
    return dest.path;
  }

  /// Список клипов (новые сверху)
  List<File> listClips() => _list(_clipsDir, ['mp4']);

  /// Список сохранённых треков (новые сверху)
  List<File> listMusic() => _list(_musicDir, _musicExts);

  /// ✅ Список сохранённых фото (новые сверху)
  List<File> listPhotos() => _list(_photosDir, _photoExts);

  /// Человекочитаемое имя из имени файла (убираем timestamp-префикс)
  static String displayName(File f) {
    var name = f.uri.pathSegments.last;
    name = name.replaceFirst(RegExp(r'^\d+_'), '');
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    return name.replaceAll('_', ' ').trim();
  }

  /// Размер файла в читаемом виде
  static String formatBytes(File f) {
    final bytes = f.lengthSync();
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  // ---------- служебное ----------

  List<File> _list(Directory dir, List<String> exts) {
    if (!dir.existsSync()) return [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => exts.contains(_extOf(f.path)))
        .toList();
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  static String _extOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return 'bin';
    return path.substring(dot + 1).toLowerCase();
  }

  static String _safeName(String s) => s
      .replaceAll(RegExp(r'[^\w\dа-яА-ЯёЁ\-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
}

/// Провайдер сервиса (переопределяется в main.dart после init)
final mediaStorageProvider = Provider<MediaStorageService>((ref) {
  throw UnimplementedError('mediaStorageProvider must be overridden in main.dart');
});