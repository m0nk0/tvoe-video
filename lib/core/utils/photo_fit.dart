import 'package:flutter/material.dart';

import '../../data/models/photo_layer.dart';

/// ==========================================
/// Единая математика вписывания фото в кадр.
/// Используется ПРЕВЬЮ, ТАЙМЛАЙНОМ, КРОП-РЕДАКТОРОМ
/// и ЭКСПОРТОМ — поэтому «что видишь = то получишь».
/// ==========================================
class PhotoFitCalculator {
  /// Прямоугольник, в котором рисуется фото (целиком),
  /// с учётом формата кадра, режима, зума и панорамы.
  ///
  /// [image]  — размер исходного фото в пикселях
  /// [canvas] — размер кадра (формат проекта)
  /// [fitMode] — cover (заполнить) или contain (вписать)
  /// [scale]   — зум пользователя 1.0..3.0 (поверх базового)
  /// [offsetX/Y] — панорама -1..1 (нормализованная)
  static Rect dstRect({
    required Size image,
    required Size canvas,
    required FitMode fitMode,
    double scale = 1.0,
    double offsetX = 0.0,
    double offsetY = 0.0,
  }) {
    final iw = image.width;
    final ih = image.height;
    final cw = canvas.width;
    final ch = canvas.height;
    if (iw <= 0 || ih <= 0 || cw <= 0 || ch <= 0) return Rect.zero;

    final base = fitMode == FitMode.cover
        ? coverScale(image: image, canvas: canvas)
        : fitScale(image: image, canvas: canvas);

    final drawW = iw * base * scale;
    final drawH = ih * base * scale;

    // Свободный ход для панорамы
    final freeX = (cw - drawW).abs() / 2;
    final freeY = (ch - drawH).abs() / 2;

    final shiftX = offsetX.clamp(-1.0, 1.0) * freeX;
    final shiftY = offsetY.clamp(-1.0, 1.0) * freeY;

    return Rect.fromCenter(
      center: Offset(cw / 2 + shiftX, ch / 2 + shiftY),
      width: drawW,
      height: drawH,
    );
  }

  /// Базовый зум «заполнить» (cover): фото закрывает кадр целиком
  static double coverScale({required Size image, required Size canvas}) {
    if (image.width <= 0 || image.height <= 0) return 1.0;
    final sx = canvas.width / image.width;
    final sy = canvas.height / image.height;
    return sx > sy ? sx : sy;
  }

  /// Базовый зум «вписать» (contain): фото видно целиком
  static double fitScale({required Size image, required Size canvas}) {
    if (image.width <= 0 || image.height <= 0) return 1.0;
    final sx = canvas.width / image.width;
    final sy = canvas.height / image.height;
    return sx < sy ? sx : sy;
  }
}