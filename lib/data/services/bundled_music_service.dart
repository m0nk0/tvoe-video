import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'media_storage_service.dart';

// ==========================================
// Встроенная музыка (royalty-free, Pixabay)
// ✅ 16 треков, 8 настроений — покрыты все жизненные поводы
// ✅ Имена файлов БЕЗ пробелов и скобок — безопасно для FFmpeg
// ==========================================

/// Настроение трека — совпадает с PhotoMood/MontageStyle
enum MusicMood {
  party,
  travel,
  romance,
  family,
  birthday,
  wedding,
  newyear,
  nostalgia,
}

class BundledTrack {
  final String assetPath;
  final String title;
  final MusicMood mood;
  final String? artist;

  const BundledTrack({
    required this.assetPath,
    required this.title,
    required this.mood,
    this.artist,
  });
}

/// Список всех встроенных треков.
/// Файлы в assets/music/ должны называться ТОЧНО как указано в assetPath.
const List<BundledTrack> kBundledTracks = [
  // ---- Вечеринка ----
  BundledTrack(
    assetPath: 'assets/music/party_01.mp3',
    title: 'Energetic Pop',
    mood: MusicMood.party,
    artist: 'Pixabay',
  ),
  BundledTrack(
    assetPath: 'assets/music/party_02.mp3',
    title: 'Party Vibes',
    mood: MusicMood.party,
    artist: 'Pixabay',
  ),
  // ---- Путешествие ----
  BundledTrack(
    assetPath: 'assets/music/travel_01.mp3',
    title: 'Adventure Road',
    mood: MusicMood.travel,
    artist: 'Pixabay',
  ),
  BundledTrack(
    assetPath: 'assets/music/travel_02.mp3',
    title: 'Journey Indie',
    mood: MusicMood.travel,
    artist: 'Pixabay',
  ),
  // ---- Романтика ----
  BundledTrack(
    assetPath: 'assets/music/romance_01.mp3',
    title: 'Soft Piano',
    mood: MusicMood.romance,
    artist: 'Pixabay',
  ),
  BundledTrack(
    assetPath: 'assets/music/romance_02.mp3',
    title: 'Romantic Acoustic',
    mood: MusicMood.romance,
    artist: 'Pixabay',
  ),
  // ---- Семья ----
  BundledTrack(
    assetPath: 'assets/music/family_01.mp3',
    title: 'Happy Ukulele',
    mood: MusicMood.family,
    artist: 'Pixabay',
  ),
  BundledTrack(
    assetPath: 'assets/music/family_02.mp3',
    title: 'Warm Feel Good',
    mood: MusicMood.family,
    artist: 'Pixabay',
  ),
  // ---- 🎂 День рождения ----
  BundledTrack(
    assetPath: 'assets/music/birthday_01.mp3',
    title: 'Birthday Fun',
    mood: MusicMood.birthday,
    artist: 'Pixabay',
  ),
  BundledTrack(
    assetPath: 'assets/music/birthday_02.mp3',
    title: 'Happy Celebration',
    mood: MusicMood.birthday,
    artist: 'Pixabay',
  ),
  // ---- 💍 Свадьба ----
  BundledTrack(
    assetPath: 'assets/music/wedding_01.mp3',
    title: 'Wedding Day',
    mood: MusicMood.wedding,
    artist: 'Pixabay',
  ),
  BundledTrack(
    assetPath: 'assets/music/wedding_02.mp3',
    title: 'First Dance',
    mood: MusicMood.wedding,
    artist: 'Pixabay',
  ),
  // ---- 🎄 Новый год ----
  BundledTrack(
    assetPath: 'assets/music/newyear_01.mp3',
    title: 'Winter Magic',
    mood: MusicMood.newyear,
    artist: 'Pixabay',
  ),
  BundledTrack(
    assetPath: 'assets/music/newyear_02.mp3',
    title: 'Festive Lights',
    mood: MusicMood.newyear,
    artist: 'Pixabay',
  ),
  // ---- 📼 Ностальгия ----
  BundledTrack(
    assetPath: 'assets/music/nostalgia_01.mp3',
    title: 'Old Memories',
    mood: MusicMood.nostalgia,
    artist: 'Pixabay',
  ),
  BundledTrack(
    assetPath: 'assets/music/nostalgia_02.mp3',
    title: 'Childhood Years',
    mood: MusicMood.nostalgia,
    artist: 'Pixabay',
  ),
];

/// ✅ Префикс имён файлов встроенных треков:
/// без пробелов и скобок — безопасен для команд FFmpeg
const String kBundledPrefix = 'bundled_';

/// Устаревший префикс (удаляем такие файлы при инициализации)
const String kLegacyPrefix = '[BUNDLED]';

class BundledMusicService {
  final MediaStorageService _storage;

  BundledMusicService(this._storage);

  /// Копирует все встроенные треки из assets в папку приложения,
  /// если они ещё не скопированы. Вызывается один раз при запуске.
  /// ✅ Также удаляет устаревшие файлы со старым префиксом [BUNDLED]
  Future<void> initialize() async {
    final musicDir = _storage.musicDir;

    // 1. Удаляем легаси-файлы со скобками и пробелом
    try {
      for (final f in musicDir.listSync().whereType<File>()) {
        if (f.path.contains(kLegacyPrefix)) {
          await f.delete();
          print('🗑 Удалён устаревший трек: ${f.path.split('/').last}');
        }
      }
    } catch (e) {
      print('⚠️ Ошибка очистки легаси-треков: $e');
    }

    // 2. Копируем актуальные треки (пропускаем уже скопированные)
    int copied = 0;
    for (final track in kBundledTracks) {
      final fileName = _bundledFileName(track);
      final destFile = File('${musicDir.path}/$fileName');

      if (await destFile.exists()) continue;

      try {
        final byteData = await rootBundle.load(track.assetPath);
        final bytes = byteData.buffer.asUint8List();
        await destFile.writeAsBytes(bytes, flush: true);
        copied++;
        print('🎵 Скопирован встроенный трек: $fileName');
      } catch (e) {
        print('⚠️ Не удалось скопировать ${track.assetPath}: $e');
      }
    }
    if (copied > 0) print('✅ Встроенная музыка установлена: $copied треков');
  }

  /// Имя файла встроенного трека в папке приложения
  String _bundledFileName(BundledTrack track) {
    final original = track.assetPath.split('/').last;
    return '$kBundledPrefix$original';
  }

  /// Все встроенные треки как File
  List<File> bundledFiles() {
    final dir = _storage.musicDir;
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains(kBundledPrefix))
        .toList();
  }

  /// Является ли файл встроенным
  static bool isBundled(File file) => file.path.contains(kBundledPrefix);

  /// ✅ Подобрать встроенный трек под настроение фото (PhotoMood → MusicMood)
  File? pickForMood(String moodName) {
    final mood = _mapMood(moodName);
    final files = bundledFiles();
    for (final f in files) {
      final track = trackForFile(f);
      if (track != null && track.mood == mood) return f;
    }
    return files.isEmpty ? null : files.first;
  }

  /// ✅ Подобрать трек под стиль монтажа (MontageStyle → MusicMood)
  /// Работает для ВСЕХ 8 стилей, включая 4 тематических
  File? pickForStyle(String styleName) {
    final mood = _mapStyle(styleName);
    final files = bundledFiles();
    for (final f in files) {
      final track = trackForFile(f);
      if (track != null && track.mood == mood) return f;
    }
    return files.isEmpty ? null : files.first;
  }

  /// ✅ Маппинг стиля монтажа → настроение музыки
  /// Все 8 стилей: 4 базовых + 4 тематических
  MusicMood _mapStyle(String styleName) {
    switch (styleName) {
      case 'party':
        return MusicMood.party;
      case 'travel':
        return MusicMood.travel;
      case 'romance':
        return MusicMood.romance;
      case 'family':
        return MusicMood.family;
      case 'birthday':
        return MusicMood.birthday;
      case 'wedding':
        return MusicMood.wedding;
      case 'newyear':
        return MusicMood.newyear;
      case 'nostalgia':
        return MusicMood.nostalgia;
      default:
        return MusicMood.family;
    }
  }

  /// Маппинг настроения фото (PhotoMood) → настроение музыки
  /// Используется для авто-подбора по настроению фото
  MusicMood _mapMood(String moodName) {
    switch (moodName) {
      case 'vibrant':
        return MusicMood.party;
      case 'cool':
        return MusicMood.travel;
      case 'warm':
        return MusicMood.romance;
      default:
        return MusicMood.family;
    }
  }

  /// Найти BundledTrack по файлу
  BundledTrack? trackForFile(File file) {
    final name =
        file.path.split('/').last.replaceFirst(kBundledPrefix, '').trim();
    for (final t in kBundledTracks) {
      if (t.assetPath.endsWith(name)) return t;
    }
    return null;
  }

  /// Красивое имя встроенного трека (без префикса и расширения)
  static String displayName(File file) {
    final name = file.path.split('/').last;
    return name
        .replaceFirst(kBundledPrefix, '')
        .replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '')
        .replaceAll('_', ' ')
        .trim();
  }

  /// Восстановить удалённый встроенный трек
  Future<void> restoreBundled(BundledTrack track) async {
    final dir = _storage.musicDir;
    if (!await dir.exists()) await dir.create(recursive: true);
    final destFile = File('${dir.path}/${_bundledFileName(track)}');
    if (await destFile.exists()) return;
    try {
      final byteData = await rootBundle.load(track.assetPath);
      final bytes = byteData.buffer.asUint8List();
      await destFile.writeAsBytes(bytes, flush: true);
    } catch (e) {
      print('⚠️ Не удалось восстановить ${track.assetPath}: $e');
    }
  }
}

/// Provider
final bundledMusicProvider = Provider<BundledMusicService>((ref) {
  final storage = ref.watch(mediaStorageProvider);
  return BundledMusicService(storage);
});