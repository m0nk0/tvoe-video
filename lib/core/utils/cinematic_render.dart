import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'live_motion.dart';

// ==========================================
// 🎬 Рендеринг Cinematic эффектов поверх кадра
// ✅ Динамическое освещение + цветовая температура
// ✅ Motion blur для панорамы
// ==========================================

/// Рисует cinematic-эффекты поверх готового кадра
void paintCinematicEffects(
  Canvas canvas,
  CinematicParams params,
  int width,
  int height,
) {
  final w = width.toDouble();
  final h = height.toDouble();
  final fullRect = Rect.fromLTWH(0, 0, w, h);

  // 1. Динамическое освещение с цветовой температурой
  if (params.lightIntensity > 0.01) {
    _paintDynamicLight(canvas, params, w, h, fullRect);
  }

  // 2. Motion blur (имитация через лёгкое размытие по направлению)
  if (params.motionBlur > 0.5) {
    _paintMotionBlur(canvas, params, w, h, fullRect);
  }
}

/// Динамическое освещение: радиальный градиент со смещением + цветовая температура
void _paintDynamicLight(
  Canvas canvas,
  CinematicParams params,
  double w,
  double h,
  Rect fullRect,
) {
  // Центр света смещён относительно центра кадра
  final centerX = w / 2 + params.lightOffset.dx * w * 0.3;
  final centerY = h / 2 + params.lightOffset.dy * h * 0.3;
  final radius = math.max(w, h) * 0.8;

  // ✅ Цветовая температура: 0 = холодный синий, 1 = тёплый оранжевый
  final warmColor = Color.fromRGBO(255, 180, 100, params.lightIntensity * 0.5);
  final coolColor = Color.fromRGBO(100, 150, 255, params.lightIntensity * 0.5);
  
  // Интерполяция между тёплым и холодным
  final t = params.colorTemperature.clamp(0.0, 1.0);
  final centerColor = Color.fromRGBO(
    (warmColor.red * t + coolColor.red * (1 - t)).round(),
    (warmColor.green * t + coolColor.green * (1 - t)).round(),
    (warmColor.blue * t + coolColor.blue * (1 - t)).round(),
    params.lightIntensity * 0.5,
  );

  // Градиент: центр цветной, края затемнены
  final gradient = ui.Gradient.radial(
    Offset(centerX, centerY),
    radius,
    [
      centerColor,
      Colors.transparent,
      Colors.black.withOpacity(params.lightIntensity * 0.6),
    ],
    [0.0, 0.5, 1.0],
  );

  // ✅ Используем overlay вместо softLight — агрессивнее, заметен на любом фото
  canvas.drawRect(
    fullRect,
    Paint()
      ..shader = gradient
      ..blendMode = BlendMode.overlay,
  );
}

/// Motion blur: имитация через размытие по горизонтали
void _paintMotionBlur(
  Canvas canvas,
  CinematicParams params,
  double w,
  double h,
  Rect fullRect,
) {
  // Направление размытия зависит от направления панорамы
  final blurSigma = params.motionBlur;
  final isPanLeft = params.lightOffset.dx > 0;
  final isPanRight = params.lightOffset.dx < 0;

  if (!isPanLeft && !isPanRight) return;

  // Рисуем несколько слоёв со смещением для имитации motion blur
  final layers = 5;
  final maxOffset = blurSigma * 2;

  for (int i = 0; i < layers; i++) {
    final t = i / (layers - 1);
    final offset = isPanLeft
        ? -maxOffset * t
        : maxOffset * t;

    canvas.save();
    canvas.translate(offset, 0);
    canvas.drawRect(
      fullRect,
      Paint()
        ..color = Colors.white.withOpacity(0.02)
        ..blendMode = BlendMode.screen,
    );
    canvas.restore();
  }
}