import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/photo_layer.dart';

// ==========================================
// 🎬 Живые фото + Cinematic эффекты
// ✅ Детерминировано: превью == экспорт
// ✅ Динамическое освещение + глубина резкости
// ✅ Цветовая температура для заметности на светлых фото
// ✅ Регулируемая интенсивность (0..1) через слайдер
// ==========================================

/// Плавная кривая (smoothstep) для естественного движения
double _ease(double t) => t * t * (3 - 2 * t);

/// Линейная интерполяция
double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Масштаб вокруг центра прямоугольника
Rect _scale(Rect r, double s) {
  final w = r.width * s;
  final h = r.height * s;
  return Rect.fromCenter(center: r.center, width: w, height: h);
}

/// Сдвиг в долях размера прямоугольника
Rect _pan(Rect r, double fx, double fy) =>
    r.translate(r.width * fx, r.height * fy);

// ==========================================
// 🎬 Cinematic параметры для каждого кадра
// ==========================================
class CinematicParams {
  /// Смещение источника света (-1..1 по X и Y)
  final Offset lightOffset;
  
  /// Интенсивность света (0..1)
  final double lightIntensity;
  
  /// Размытие фона в пикселях
  final double backgroundBlur;
  
  /// Насыщенность фона (0..1, где 1 = оригинал)
  final double saturation;
  
  /// Размытие в движении (для панорамы)
  final double motionBlur;

  /// Цветовая температура (0 = холодный синий, 1 = тёплый оранжевый)
  final double colorTemperature;

  const CinematicParams({
    required this.lightOffset,
    required this.lightIntensity,
    required this.backgroundBlur,
    required this.saturation,
    required this.motionBlur,
    this.colorTemperature = 0.5,
  });

  /// Дефолтные параметры (без cinematic эффектов)
  static const CinematicParams none = CinematicParams(
    lightOffset: Offset.zero,
    lightIntensity: 0,
    backgroundBlur: 0,
    saturation: 1,
    motionBlur: 0,
    colorTemperature: 0.5,
  );
}

/// Результат применения движения + cinematic эффектов
class CinematicResult {
  final Rect rect;
  final CinematicParams params;

  const CinematicResult(this.rect, this.params);
}

/// Применяет Ken Burns движение + cinematic эффекты
/// [intensity] — множитель интенсивности (0..1), дефолт 1.0
/// Возвращает трансформированный rect и параметры освещения/размытия
CinematicResult applyLiveMotionWithCinematic(
  Rect dst,
  LiveMotion mode,
  double t, {
  double intensity = 1.0, // ✅ ИСПРАВЛЕНО: добавлены фигурные скобки {}
}) {
  final e = _ease(t.clamp(0.0, 1.0));
  
  switch (mode) {
    case LiveMotion.none:
      return CinematicResult(dst, CinematicParams.none);
      
    case LiveMotion.zoomIn:
      final rect = _scale(dst, _lerp(1.0, 1.14, e));
      final params = CinematicParams(
        lightOffset: Offset(0, 0),
        lightIntensity: (0.6 * e) * intensity,
        backgroundBlur: (8 * e) * intensity,
        saturation: 1 - (0.2 * e) * intensity,
        motionBlur: 0,
        colorTemperature: 0.5 + (0.4 * e) * intensity,
      );
      return CinematicResult(rect, params);
      
    case LiveMotion.zoomOut:
      final rect = _scale(dst, _lerp(1.14, 1.0, e));
      final params = CinematicParams(
        lightOffset: Offset.zero,
        lightIntensity: (0.6 * (1 - e)) * intensity,
        backgroundBlur: (8 * (1 - e)) * intensity,
        saturation: 1 - (0.2 * (1 - e)) * intensity,
        motionBlur: 0,
        colorTemperature: 0.5 - (0.3 * (1 - e)) * intensity,
      );
      return CinematicResult(rect, params);
      
    case LiveMotion.panLeft:
      final rect = _pan(_scale(dst, 1.12), _lerp(0.05, -0.05, e), 0);
      final params = CinematicParams(
        lightOffset: Offset(_lerp(0.3, -0.3, e), 0),
        lightIntensity: 0.25 * intensity,
        backgroundBlur: 4 * intensity,
        saturation: 1 - 0.1 * intensity,
        motionBlur: (6 * math.sin(e * math.pi)) * intensity,
        colorTemperature: 0.5 + 0.3 * intensity,
      );
      return CinematicResult(rect, params);
      
    case LiveMotion.panRight:
      final rect = _pan(_scale(dst, 1.12), _lerp(-0.05, 0.05, e), 0);
      final params = CinematicParams(
        lightOffset: Offset(_lerp(-0.3, 0.3, e), 0),
        lightIntensity: 0.25 * intensity,
        backgroundBlur: 4 * intensity,
        saturation: 1 - 0.1 * intensity,
        motionBlur: (6 * math.sin(e * math.pi)) * intensity,
        colorTemperature: 0.5 - 0.3 * intensity,
      );
      return CinematicResult(rect, params);
      
    case LiveMotion.breathe:
      final s = 1.06 + 0.018 * math.sin(t * math.pi * 2);
      final dx = 0.006 * math.sin(t * math.pi * 2 * 0.8 + 0.7);
      final dy = 0.004 * math.sin(t * math.pi * 2 * 0.6);
      final rect = _pan(_scale(dst, s), dx, dy);
      final params = CinematicParams(
        lightOffset: Offset(
          (0.15 * math.sin(t * math.pi * 2 * 0.8)) * intensity,
          (0.1 * math.sin(t * math.pi * 2 * 0.6)) * intensity,
        ),
        lightIntensity: 0.15 * intensity,
        backgroundBlur: 2 * intensity,
        saturation: 1 - 0.05 * intensity,
        motionBlur: 0,
        colorTemperature: 0.5 + (0.1 * math.sin(t * math.pi * 2 * 0.5)) * intensity,
      );
      return CinematicResult(rect, params);
  }
}

/// Старая функция для обратной совместимости (без cinematic)
Rect applyLiveMotion(Rect dst, LiveMotion mode, double t) {
  return applyLiveMotionWithCinematic(dst, mode, t, intensity: 1.0).rect;
}