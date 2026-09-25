import 'package:hive/hive.dart';

part 'photo_layer.g.dart';

@HiveType(typeId: 10)
enum TransitionType {
  @HiveField(0) none,
  @HiveField(1) fade,
  @HiveField(2) slideLeft,
  @HiveField(3) slideRight,
  @HiveField(4) zoomIn,
  @HiveField(5) zoomOut,
  @HiveField(6) blur,
}

@HiveType(typeId: 1)
class PhotoLayer extends HiveObject {
  @HiveField(0)
  String imagePath;

  @HiveField(1)
  int durationMilliseconds;

  @HiveField(2)
  TransitionType transition;

  @HiveField(3)
  double scale;

  @HiveField(4)
  double positionX;

  @HiveField(5)
  double positionY;

  PhotoLayer({
    required this.imagePath,
    required this.durationMilliseconds,
    this.transition = TransitionType.fade,
    this.scale = 1.0,
    this.positionX = 0.0,
    this.positionY = 0.0,
  });

  Duration get duration => Duration(milliseconds: durationMilliseconds);
  set duration(Duration value) => durationMilliseconds = value.inMilliseconds;

  factory PhotoLayer.empty() => PhotoLayer(
        imagePath: '',
        durationMilliseconds: 3000,
      );
}