import 'package:hive/hive.dart';

part 'audio_track.g.dart';

@HiveType(typeId: 7)
class AudioTrack {
  @HiveField(0)
  final String filePath;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String? artist;

  @HiveField(3)
  final double volume;

  @HiveField(4)
  final double startTime;

  @HiveField(5)
  final bool isFromInternet;

  AudioTrack({
    required this.filePath,
    required this.title,
    this.artist,
    this.volume = 0.5,
    this.startTime = 0.0,
    this.isFromInternet = false,
  });

  AudioTrack copyWith({
    String? filePath,
    String? title,
    String? artist,
    double? volume,
    double? startTime,
    bool? isFromInternet,
  }) {
    return AudioTrack(
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      volume: volume ?? this.volume,
      startTime: startTime ?? this.startTime,
      isFromInternet: isFromInternet ?? this.isFromInternet,
    );
  }
}