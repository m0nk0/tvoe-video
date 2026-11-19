import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'bundled_music_service.dart';

class MediaStorageService {
  static final MediaStorageService _instance = MediaStorageService._internal();
  factory MediaStorageService() => _instance;
  MediaStorageService._internal();

  late final Directory _appDir;
  late final Directory _photosDir;
  late final Directory _musicDir;
  late final Directory _clipsDir;
  late final Directory _exportsDir;
  bool _initialized = false;

  Directory get appDir => _appDir;
  Directory get photosDir => _photosDir;
  Directory get musicDir => _musicDir;
  Directory get clipsDir => _clipsDir;
  Directory get exportsDir => _exportsDir;

  // ==========================================
  // Инициализация: создаём рабочие папки
  // ==========================================
  Future<void> init() async {
    if (_initialized) return;
    _appDir = await getApplicationDocumentsDirectory();
    _photosDir = Directory('${_appDir.path}/photos');
    _musicDir = Directory('${_appDir.path}/music');
    _clipsDir = Directory('${_appDir.path}/clips');
    _exportsDir = Directory('${_appDir.path}/exports');
    for (final d in [_photosDir, _musicDir, _clipsDir, _exportsDir]) {
      if (!d.existsSync()) d.createSync(recursive: true);
    }
    _initialized = true;
    print('📂 MediaStorage: папки готовы');
  }

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  // ==========================================
  // 📸 Фото: импорт из галереи/камеры
  // ==========================================
  Future<String?> importPhoto(String srcPath) async {
    await _ensureInit();
    try {
      final src = File(srcPath);
      if (!src.existsSync()) return null;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = srcPath.split('.').last.toLowerCase();
      final safeExt = ['jpg', 'jpeg', 'png', 'webp', 'heic'].contains(ext) ? ext : 'jpg';
      final dst = '${_photosDir.path}/photo_$ts.$safeExt';
      src.copySync(dst);
      print('📸 Фото импортировано: $dst');
      return dst;
    } catch (e) {
      print('❌ importPhoto: $e');
      return null;
    }
  }

  // ==========================================
  // 🎵 Музыка: импорт с устройства/из URL
  // ==========================================
  Future<String?> importMusic(String srcPath, {String? title}) async {
    await _ensureInit();
    try {
      final src = File(srcPath);
      if (!src.existsSync()) return null;
      // если уже в папке music/ — не копируем
      if (srcPath.startsWith(_musicDir.path)) return srcPath;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = srcPath.split('.').last.toLowerCase();
      final safeExt = ['mp3', 'wav', 'm4a', 'ogg', 'aac'].contains(ext) ? ext : 'mp3';
      final safeTitle = (title ?? 'track').replaceAll(RegExp(r'[^a-zA-Z0-9а-яА-Я_\-]'), '_');
      final dst = '${_musicDir.path}/${safeTitle}_$ts.$safeExt';
      src.copySync(dst);
      print('🎵 Музыка импортирована: $dst');
      return dst;
    } catch (e) {
      print('❌ importMusic: $e');
      return null;
    }
  }

  // ==========================================
  // 🎬 Клипы: импорт экспортированного видео/GIF в медиатеку
  // ==========================================
  Future<String?> importClip(String srcPath) async {
    await _ensureInit();
    try {
      final src = File(srcPath);
      if (!src.existsSync()) return null;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = srcPath.endsWith('.gif') ? 'gif' : 'mp4';
      final dst = '${_clipsDir.path}/clip_$ts.$ext';
      src.copySync(dst);
      print('🎬 Клип импортирован: $dst');
      return dst;
    } catch (e) {
      print('❌ importClip: $e');
      return null;
    }
  }

  // ==========================================
  // Списки файлов
  // ==========================================
  List<File> listPhotos() => _listDir(_photosDir);
  List<File> listMusic() => _listDir(_musicDir);
  List<File> listClips() => _listDir(_clipsDir);

  List<File> _listDir(Directory dir) {
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => !f.path.endsWith('.part'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  }

  // ==========================================
  // Удаление
  // ==========================================
  bool deleteFile(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
      return true;
    } catch (e) {
      print('❌ deleteFile: $e');
      return false;
    }
  }

  /// Очистка всех пользовательских файлов (сброс проекта)
  Future<int> clearAll() async {
    int deleted = 0;
    for (final dir in [_photosDir, _musicDir, _clipsDir, _exportsDir]) {
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync().whereType<File>()) {
        // bundled-треки оставляем
        if (BundledMusicService.isBundled(f)) continue;
        try {
          f.deleteSync();
          deleted++;
        } catch (_) {}
      }
    }
    print('🧹 Очищено файлов: $deleted');
    return deleted;
  }

  // ==========================================
  // Хелперы отображения
  // ==========================================
  static String displayName(File file) {
    try {
      final name = file.path.split('/').last;
      // убираем timestamp-хвост: photo_123456.jpg -> photo
      final stripped = name.replaceAll(RegExp(r'_\d{10,}\.'), '.');
      final base = stripped.contains('.')
          ? stripped.substring(0, stripped.lastIndexOf('.'))
          : stripped;
      if (base.isEmpty) return name;
      return base;
    } catch (_) {
      return file.path.split('/').last;
    }
  }

  static String formatBytes(File file) {
    try {
      final bytes = file.lengthSync();
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
      if (bytes < 1024 * 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
      }
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
    } catch (_) {
      return '?';
    }
  }
}