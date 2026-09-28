import 'package:hive/hive.dart';
import 'photo_layer.dart';

part 'template.g.dart';

@HiveType(typeId: 3)
class Template extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String category;

  @HiveField(3)
  int photoDurationMilliseconds;

  @HiveField(4)
  TransitionType defaultTransition;

  @HiveField(5)
  String? musicPath;

  @HiveField(6)
  String? previewImagePath;

  Template({
    required this.id,
    required this.name,
    required this.category,
    required this.photoDurationMilliseconds,
    this.defaultTransition = TransitionType.fade,
    this.musicPath,
    this.previewImagePath,
  });

  Duration get photoDuration => Duration(milliseconds: photoDurationMilliseconds);
}