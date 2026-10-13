import 'package:hive/hive.dart';

import 'photo_layer.dart';
import 'text_layer.dart';
import 'audio_track.dart';
import 'video_format.dart';

part 'video_project.g.dart';

// ==========================================
// Анимированные оверлеи всего видео
// ==========================================
@HiveType(typeId: 12)
enum OverlayType {
  @HiveField(0) none,
  @HiveField(1) film,
  @HiveField(2) cinema,
  @HiveField(3) vhs,
  @HiveField(4) lightleak,
  @HiveField(5) dreamy,
  @HiveField(6) bokeh,
  @HiveField(7) snow,
  @HiveField(8) cyber,
}

@HiveType(typeId: 1)
class VideoProject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final List<PhotoLayer> photos;

  @HiveField(3)
  final List<TextLayer> texts;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  final DateTime updatedAt;

  @HiveField(6)
  final AudioTrack? audioTrack;

  @HiveField(7, defaultValue: 0)
  final int formatId;

  @HiveField(8, defaultValue: OverlayType.none)
  final OverlayType overlayType;

  @HiveField(9, defaultValue: 0.6)
  final double overlayIntensity;

  // 🎬 НОВОЕ: интенсивность cinematic-эффекта (0.0-1.0, дефолт 0.5)
  @HiveField(10, defaultValue: 0.5)
  final double cinematicIntensity;

  VideoProject({
    required this.id,
    required this.name,
    required this.photos,
    required this.texts,
    this.audioTrack,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.formatId = 0,
    this.overlayType = OverlayType.none,
    this.overlayIntensity = 0.6,
    this.cinematicIntensity = 0.5,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  VideoProject copyWith({
    String? id,
    String? name,
    List<PhotoLayer>? photos,
    List<TextLayer>? texts,
    AudioTrack? audioTrack,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? formatId,
    OverlayType? overlayType,
    double? overlayIntensity,
    double? cinematicIntensity,
  }) {
    return VideoProject(
      id: id ?? this.id,
      name: name ?? this.name,
      photos: photos ?? this.photos,
      texts: texts ?? this.texts,
      audioTrack: audioTrack ?? this.audioTrack,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      formatId: formatId ?? this.formatId,
      overlayType: overlayType ?? this.overlayType,
      overlayIntensity: overlayIntensity ?? this.overlayIntensity,
      cinematicIntensity: cinematicIntensity ?? this.cinematicIntensity,
    );
  }

  VideoFormat get format => VideoFormat.byId(formatId);

  int get totalDurationMs =>
      photos.fold<int>(0, (sum, p) => sum + p.durationMilliseconds);

  double get totalDurationSec => totalDurationMs / 1000.0;

  String get formattedDuration {
    final d = Duration(milliseconds: totalDurationMs);
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}