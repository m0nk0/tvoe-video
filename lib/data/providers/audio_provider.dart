import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/audio_track.dart';

// ==========================================
// Провайдеры аудио
// ==========================================

/// Общий аудио-плеер для превью треков
final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final player = AudioPlayer();
  ref.onDispose(() => player.dispose());
  return player;
});

/// Состояние воспроизведения превью
final isAudioPlayingProvider = StateProvider<bool>((ref) => false);

// ==========================================
// Разрешение на чтение аудио
// ==========================================
Future<bool> requestAudioPermission() async {
  if (!Platform.isAndroid) return true;

  // Android 13+: READ_MEDIA_AUDIO
  var status = await Permission.audio.status;
  if (status.isGranted) return true;
  status = await Permission.audio.request();
  if (status.isGranted) return true;

  // Android 12 и ниже: READ_EXTERNAL_STORAGE
  final storageStatus = await Permission.storage.status;
  if (storageStatus.isGranted) return true;
  final storageReq = await Permission.storage.request();
  return storageReq.isGranted;
}

// ==========================================
// Сканер музыки на устройстве (с подпапками)
// ==========================================
/// Ищет аудиофайлы в стандартных папках устройства,
/// включая ВСЕ вложенные подпапки (до 4 уровней вглубь)
Future<List<AudioTrack>> scanDeviceMusic() async {
  const exts = ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'wma', 'opus'];

  // Корневые папки для поиска
  final rootDirs = [
    '/storage/emulated/0/Music',
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Downloads',
    '/storage/emulated/0/Audio',
    '/storage/emulated/0/Documents',
    '/storage/emulated/0/MTS',
    '/storage/emulated/0/Android/media',
  ];

  final tracks = <AudioTrack>[];
  final seen = <String>{};

  void scanDir(Directory dir, int depth) {
    if (depth > 4 || tracks.length >= 500) return;
    try {
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is File) {
          final dot = entity.path.lastIndexOf('.');
          if (dot < 0) continue;
          final ext = entity.path.substring(dot + 1).toLowerCase();
          if (!exts.contains(ext)) continue;
          if (!seen.add(entity.path)) continue;
          final name = entity.uri.pathSegments.last;
          tracks.add(AudioTrack(
            filePath: entity.path,
            title: name.replaceAll(RegExp(r'\.[^.]+$'), ''),
            isFromInternet: false,
          ));
        } else if (entity is Directory) {
          final segments = entity.uri.pathSegments.where((s) => s.isNotEmpty);
          final dirName = segments.isEmpty ? '' : segments.last;
          // Пропускаем скрытые папки и защищённые Android/data, Android/obb
          if (dirName.startsWith('.')) continue;
          if (dirName == 'data' || dirName == 'obb') continue;
          scanDir(entity, depth + 1);
        }
      }
    } catch (e) {
      print('Ошибка сканирования ${dir.path}: $e');
    }
  }

  for (final d in rootDirs) {
    final dir = Directory(d);
    if (!dir.existsSync()) continue;
    scanDir(dir, 0);
  }

  tracks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return tracks;
}

// ==========================================
// Системный выбор файла (любая папка)
// ==========================================
Future<AudioTrack?> pickAudioFromDevice() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'wma',
        'opus', 'aiff', 'amr', '3gp',
      ],
      allowMultiple: false,
      allowCompression: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final path = file.path;
    if (path == null) return null;

    if (!File(path).existsSync()) return null;

    return AudioTrack(
      filePath: path,
      title: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
      isFromInternet: false,
    );
  } catch (e) {
    print('Ошибка выбора аудио: $e');
    return null;
  }
}

// ==========================================
// Скачивание аудио из интернета
// ==========================================
Future<AudioTrack?> downloadAudioFromUrl(String url) async {
  try {
    final uri = Uri.parse(url);
    final client = HttpClient();
    final request = await client.getUrl(uri);
    final response = await request.close();

    if (response.statusCode != 200) {
      client.close();
      return null;
    }

    final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    client.close();

    final dir = await getApplicationDocumentsDirectory();
    final extension = _extractExtension(uri.path) ?? 'mp3';
    final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);

    return AudioTrack(
      filePath: file.path,
      title: _extractTitle(uri) ?? 'Скачанный трек',
      isFromInternet: true,
    );
  } catch (e) {
    print('Ошибка скачивания аудио: $e');
    return null;
  }
}

/// Извлекает расширение из пути URL
String? _extractExtension(String path) {
  final match = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(path);
  if (match == null) return null;
  final ext = match.group(1)!.toLowerCase();
  const allowed = ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'wma'];
  return allowed.contains(ext) ? ext : null;
}

/// Извлекает название трека из URL
String? _extractTitle(Uri uri) {
  final lastSegment = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
  if (lastSegment == null || lastSegment.isEmpty) return null;
  return lastSegment.replaceAll(RegExp(r'\.[^.]+$'), '');
}