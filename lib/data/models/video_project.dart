import 'package:hive/hive.dart';
import 'photo_layer.dart';
import 'text_layer.dart';
import 'template.dart';

part 'video_project.g.dart';

@HiveType(typeId: 0)
class VideoProject extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  int createdAtMilliseconds;

  @HiveField(3)
  List<PhotoLayer> photos;

  @HiveField(4)
  List<TextLayer> texts;

  @HiveField(5)
  Template? template;

  VideoProject({
    required this.id,
    required this.name,
    required this.createdAtMilliseconds,
    List<PhotoLayer>? photos,
    List<TextLayer>? texts,
    this.template,
  })  : photos = photos ?? [],
        texts = texts ?? [];

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMilliseconds);

  Duration get totalDuration {
    int totalMs = 0;
    for (var photo in photos) {
      totalMs += photo.durationMilliseconds;
    }
    return Duration(milliseconds: totalMs);
  }

  String get formattedDuration {
    final duration = totalDuration;
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  factory VideoProject.empty({String? name}) {
    return VideoProject(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name ?? 'Новый проект',
      createdAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
    );
  }
}