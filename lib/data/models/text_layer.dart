import 'package:hive/hive.dart';

part 'text_layer.g.dart';

@HiveType(typeId: 11)
enum AnimationType {
  @HiveField(0) none,
  @HiveField(1) fadeIn,
  @HiveField(2) slideUp,
  @HiveField(3) slideDown,
  @HiveField(4) typewriter,
}

@HiveType(typeId: 2)
class TextLayer extends HiveObject {
  @HiveField(0)
  String text;

  @HiveField(1)
  String fontFamily;

  @HiveField(2)
  double fontSize;

  @HiveField(3)
  int colorValue;

  @HiveField(4)
  int startTimeMilliseconds;

  @HiveField(5)
  int endTimeMilliseconds;

  @HiveField(6)
  AnimationType animation;

  @HiveField(7)
  double positionX;

  @HiveField(8)
  double positionY;

  TextLayer({
    required this.text,
    this.fontFamily = 'Manrope',
    this.fontSize = 24.0,
    this.colorValue = 0xFFFFFFFF,
    required this.startTimeMilliseconds,
    required this.endTimeMilliseconds,
    this.animation = AnimationType.fadeIn,
    this.positionX = 0.5,
    this.positionY = 0.5,
  });

  Duration get startTime => Duration(milliseconds: startTimeMilliseconds);
  set startTime(Duration value) => startTimeMilliseconds = value.inMilliseconds;

  Duration get endTime => Duration(milliseconds: endTimeMilliseconds);
  set endTime(Duration value) => endTimeMilliseconds = value.inMilliseconds;
}