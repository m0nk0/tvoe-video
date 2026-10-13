import 'package:flutter/material.dart';

class VideoFormat {
  final int id;
  final String name;
  final String ratio;
  final int width;
  final int height;
  final IconData icon;

  const VideoFormat({
    required this.id,
    required this.name,
    required this.ratio,
    required this.width,
    required this.height,
    required this.icon,
  });

  /// Соотношение сторон (ширина / высота)
  double get aspectRatio => width / height;

  /// Размер кадра
  Size get size => Size(width.toDouble(), height.toDouble());

  /// 4 формата с разными соотношениями
  static const List<VideoFormat> formats = [
    VideoFormat(
      id: 0,
      name: 'Сторис',
      ratio: '9:16',
      width: 1080,
      height: 1920,
      icon: Icons.phone_android,
    ),
    VideoFormat(
      id: 1,
      name: 'Квадрат',
      ratio: '1:1',
      width: 1080,
      height: 1080,
      icon: Icons.crop_square,
    ),
    VideoFormat(
      id: 2,
      name: 'Альбом',
      ratio: '16:9',
      width: 1920,
      height: 1080,
      icon: Icons.laptop_mac,
    ),
    VideoFormat(
      id: 3,
      name: 'Портрет',
      ratio: '4:5',
      width: 1080,
      height: 1350,
      icon: Icons.portrait,
    ),
  ];

  /// Безопасный доступ по индексу (с защитой от невалидных индексов)
  static VideoFormat byId(int id) {
    if (id < 0 || id >= formats.length) return formats.first;
    return formats[id];
  }

  /// Автоматически определяет рекомендуемый формат по ориентации фото
  static int recommendedForImage({required double width, required double height}) {
    if (width <= 0 || height <= 0) return 0;
    final aspect = width / height;

    // Очень вертикальное (>1.4) → Сторис
    if (aspect < 0.65) return 0;
    // Горизонтальное (>1.5) → Альбом
    if (aspect > 1.5) return 2;
    // Квадрат (0.9..1.1) → Квадрат
    if (aspect > 0.9 && aspect < 1.1) return 1;
    // Остальное (вертикальное, но не сильно) → Портрет
    return 3;
  }
}