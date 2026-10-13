import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'photo_fit.dart';

// ==========================================
// Умное кадрирование: центрирование лиц в кадре
// ==========================================

/// Результат умного кадрирования
class SmartCropResult {
  /// Нормализованный сдвиг по X (-1..1)
  final double offsetX;

  /// Нормализованный сдвиг по Y (-1..1)
  final double offsetY;

  /// Найдены ли лица на фото
  final bool faceFound;

  /// Количество найденных лиц
  final int faceCount;

  const SmartCropResult({
    required this.offsetX,
    required this.offsetY,
    required this.faceFound,
    this.faceCount = 0,
  });
}

class SmartCropService {
  /// Вычисляет offsetX/offsetY для режима cover,
  /// чтобы лица (или группа лиц) оказались в центре кадра
  static Future<SmartCropResult> computeCoverOffsets({
    required String imagePath,
    required ui.Size imageSize,
    required ui.Size canvas,
  }) async {
        final detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: false,
        enableTracking: false,
      ),
    );

    try {
      final faces =
          await detector.processImage(InputImage.fromFilePath(imagePath));

      if (faces.isEmpty) {
        return const SmartCropResult(
          offsetX: 0,
          offsetY: 0,
          faceFound: false,
        );
      }

      // ✅ Объединяем все лица в один бокс (для групповых фото)
      double left = double.infinity;
      double top = double.infinity;
      double right = -double.infinity;
      double bottom = -double.infinity;

      for (final face in faces) {
        final b = face.boundingBox;
        left = math.min(left, b.left);
        top = math.min(top, b.top);
        right = math.max(right, b.right);
        bottom = math.max(bottom, b.bottom);
      }

      // Центр группы лиц в нормализованных координатах фото (0..1)
      final fx = ((left + right) / 2) / imageSize.width;
      final fy = ((top + bottom) / 2) / imageSize.height;

      // Математика cover-режима из PhotoFitCalculator
      final base =
          PhotoFitCalculator.coverScale(image: imageSize, canvas: canvas);
      final drawW = imageSize.width * base;
      final drawH = imageSize.height * base;
      final freeX = (canvas.width - drawW).abs() / 2;
      final freeY = (canvas.height - drawH).abs() / 2;

      // ✅ Сдвиг, при котором центр лиц попадает в центр кадра
      double ox = 0;
      double oy = 0;
      if (freeX > 1) {
        ox = (drawW * (0.5 - fx) / freeX).clamp(-1.0, 1.0);
      }
      if (freeY > 1) {
        oy = (drawH * (0.5 - fy) / freeY).clamp(-1.0, 1.0);
      }

      return SmartCropResult(
        offsetX: ox,
        offsetY: oy,
        faceFound: true,
        faceCount: faces.length,
      );
    } finally {
      await detector.close();
    }
  }
}