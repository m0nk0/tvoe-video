import 'dart:math' as math;

import '../../data/models/photo_layer.dart';
import 'smart_analyzer.dart';

// ==========================================
// Умный монтаж: генератор клипа из анализа фото
// ✅ 8 стилей: 4 базовых (авто-детект) + 4 тематических (ручной выбор)
// ✅ Трендовые переходы используются ИИ в подходящих стилях
// ==========================================

/// Стиль монтажа
enum MontageStyle {
  auto, // определить автоматически
  family, // семейный: плавный, тёплый
  travel, // путешествие: динамичный, сочный
  party, // вечеринка: быстрый, яркий
  romance, // романтика: медленный, нежный
  birthday, // 🎂 день рождения: бодрый, праздничный
  wedding, // 💍 свадьба: плавный, торжественный
  newyear, // 🎄 новый год: средний, волшебный
  nostalgia, // 📼 ностальгия: медленный, винтажный
}

/// План одного кадра будущего клипа
class MontageFramePlan {
  final String imagePath;
  final int durationMs;
  final TransitionType transition;
  final FilterType filter;
  final EntranceAnimation entrance;
  final int entranceDurationMs;
  final FitMode fitMode;
  final double offsetX;
  final double offsetY;

  const MontageFramePlan({
    required this.imagePath,
    required this.durationMs,
    required this.transition,
    required this.filter,
    required this.entrance,
    required this.entranceDurationMs,
    required this.fitMode,
    required this.offsetX,
    required this.offsetY,
  });
}

class SmartMontage {
  // ==========================================
  // Автоопределение стиля по набору фото
  // ✅ Выбирает ТОЛЬКО из 4 базовых стилей
  // ==========================================
  static MontageStyle autoDetect(List<SmartPhotoAnalysis> analyses) {
    if (analyses.isEmpty) return MontageStyle.family;

    int group = 0, vibrant = 0, warm = 0, cool = 0, smiles = 0;
    for (final a in analyses) {
      if (a.faceCount >= 2) group++;
      if (a.mood == PhotoMood.vibrant) vibrant++;
      if (a.mood == PhotoMood.warm) warm++;
      if (a.mood == PhotoMood.cool) cool++;
      if (a.hasSmile) smiles++;
    }

    final n = analyses.length;
    if (vibrant >= n / 3 || (smiles >= n / 2 && group >= n / 3)) {
      return MontageStyle.party;
    }
    if (cool >= n / 3) return MontageStyle.travel;
    if (warm >= n / 3 && smiles >= n / 3) return MontageStyle.romance;
    return MontageStyle.family;
  }

  // ==========================================
  // Генерация плана клипа
  // ==========================================
  static List<MontageFramePlan> generate({
    required List<SmartPhotoAnalysis> analyses,
    required MontageStyle style,
    required double canvasAspect,
  }) {
    if (analyses.isEmpty) return [];

    final effective =
        style == MontageStyle.auto ? autoDetect(analyses) : style;

    // ✅ Лучшее фото — в финал (эффектная концовка)
    final list = List<SmartPhotoAnalysis>.from(analyses);
    if (list.length >= 3) {
      int best = 0;
      double bestScore = -1;
      for (int i = 0; i < list.length; i++) {
        final s = _score(list[i]);
        if (s > bestScore) {
          bestScore = s;
          best = i;
        }
      }
      final finale = list.removeAt(best);
      list.add(finale);
    }

    return [
      for (int i = 0; i < list.length; i++)
        _planFor(list[i], effective, i, canvasAspect),
    ];
  }

  static double _score(SmartPhotoAnalysis a) =>
      a.complexityScore +
      (a.hasSmile ? 0.3 : 0.0) +
      (a.faceCount > 0 ? 0.2 : 0.0);

  // ==========================================
  // План одного кадра
  // ==========================================
  static MontageFramePlan _planFor(
    SmartPhotoAnalysis a,
    MontageStyle style,
    int index,
    double canvasAspect,
  ) {
    // ---- Длительность (характер стиля) ----
    int base;
    switch (style) {
      case MontageStyle.party:
        base = 1600;
        break;
      case MontageStyle.birthday:
        base = 1800;
        break;
      case MontageStyle.travel:
        base = 2400;
        break;
      case MontageStyle.newyear:
        base = 2500;
        break;
      case MontageStyle.romance:
        base = 3200;
        break;
      case MontageStyle.wedding:
        base = 4000;
        break;
      case MontageStyle.nostalgia:
        base = 4500;
        break;
      default:
        base = 2800; // family
    }
    int dur = base;
    if (a.isSlowPaced) dur += 600;
    if (a.isFastPaced) dur -= 500;
    dur = dur.clamp(1000, 5000);

    // ---- Переход ----
    final transitions = _transitionsFor(style);
    final transition = index == 0
        ? TransitionType.none
        : transitions[index % transitions.length];

    // ---- Появление ----
    final entrances = _entrancesFor(style);
    final entrance = entrances[index % entrances.length];
    final entranceMs = _entranceMsFor(style);

    // ---- Фильтр по настроению и стилю ----
    final filter = _filterForMood(a.mood, style);

    // ---- Умное центрирование лиц ----
    final offsets = _smartOffsets(a, canvasAspect);

    return MontageFramePlan(
      imagePath: a.imagePath,
      durationMs: dur,
      transition: transition,
      filter: filter,
      entrance: entrance,
      entranceDurationMs: entranceMs,
      fitMode: FitMode.cover,
      offsetX: offsets[0],
      offsetY: offsets[1],
    );
  }

  // ==========================================
  // ✅ Наборы переходов по стилям (ИИ использует трендовые!)
  // ==========================================
  static List<TransitionType> _transitionsFor(MontageStyle style) {
    switch (style) {
      case MontageStyle.party:
        // 🎉 Драйв: хлыст, RGB-глитч, вспышка
        return [
          TransitionType.whipPan,
          TransitionType.rgbSplit,
          TransitionType.flash,
          TransitionType.glitch,
          TransitionType.zoomOut,
        ];
      case MontageStyle.birthday:
        // 🎂 Празднично: вспышка, круг, пролёт
        return [
          TransitionType.flash,
          TransitionType.circleReveal,
          TransitionType.crossZoom,
          TransitionType.slideLeft,
        ];
      case MontageStyle.travel:
        // 🗺 Динамика: пролёт, хлыст, слайды
        return [
          TransitionType.crossZoom,
          TransitionType.slideLeft,
          TransitionType.whipPan,
          TransitionType.wipe,
        ];
      case MontageStyle.newyear:
        // 🎄 Волшебно: круг, спин, пролёт
        return [
          TransitionType.circleReveal,
          TransitionType.spinBlur,
          TransitionType.crossZoom,
          TransitionType.slideLeft,
        ];
      case MontageStyle.romance:
        // 💕 Нежно: только плавные
        return [
          TransitionType.blur,
          TransitionType.fade,
          TransitionType.dissolve,
        ];
      case MontageStyle.wedding:
        // 💍 Торжественно: только плавные
        return [
          TransitionType.fade,
          TransitionType.dissolve,
          TransitionType.blur,
        ];
      case MontageStyle.nostalgia:
        // 📼 Задумчиво: только мягкие растворения
        return [
          TransitionType.dissolve,
          TransitionType.fade,
          TransitionType.blur,
        ];
      default: // family
        return [
          TransitionType.fade,
          TransitionType.dissolve,
          TransitionType.crossZoom,
          TransitionType.circleReveal,
        ];
    }
  }

  // ==========================================
  // Наборы появлений по стилям
  // ==========================================
  static List<EntranceAnimation> _entrancesFor(MontageStyle style) {
    switch (style) {
      case MontageStyle.party:
        return [
          EntranceAnimation.zoomIn,
          EntranceAnimation.slideFromBottom,
          EntranceAnimation.fadeIn,
        ];
      case MontageStyle.birthday:
        return [
          EntranceAnimation.zoomIn,
          EntranceAnimation.slideFromLeft,
          EntranceAnimation.slideFromRight,
        ];
      case MontageStyle.travel:
        return [
          EntranceAnimation.slideFromLeft,
          EntranceAnimation.zoomIn,
          EntranceAnimation.slideFromRight,
        ];
      case MontageStyle.newyear:
        return [
          EntranceAnimation.zoomIn,
          EntranceAnimation.slideFromTop,
          EntranceAnimation.fadeIn,
        ];
      case MontageStyle.romance:
        return [
          EntranceAnimation.fadeIn,
          EntranceAnimation.zoomIn,
          EntranceAnimation.fadeIn,
        ];
      case MontageStyle.wedding:
        return [
          EntranceAnimation.fadeIn,
          EntranceAnimation.fadeIn,
          EntranceAnimation.zoomIn,
        ];
      case MontageStyle.nostalgia:
        return [
          EntranceAnimation.fadeIn,
          EntranceAnimation.fadeIn,
          EntranceAnimation.fadeIn,
        ];
      default: // family
        return [
          EntranceAnimation.fadeIn,
          EntranceAnimation.none,
          EntranceAnimation.fadeIn,
        ];
    }
  }

  static int _entranceMsFor(MontageStyle style) {
    switch (style) {
      case MontageStyle.party:
        return 400;
      case MontageStyle.birthday:
        return 450;
      case MontageStyle.newyear:
        return 500;
      case MontageStyle.romance:
        return 600;
      case MontageStyle.wedding:
        return 700;
      case MontageStyle.nostalgia:
        return 800;
      default:
        return 500;
    }
  }

  // ==========================================
  // ✅ Фильтры: сепия НЕ используется в авто-подборе
  // ==========================================
  static FilterType _filterForMood(PhotoMood mood, MontageStyle style) {
    const bright = ['vivid', 'bright', 'pop', 'saturated'];
    const warm = ['warm', 'sunset', 'golden'];
    const cool = ['cool', 'cold', 'winter'];
    const soft = ['soft', 'fade', 'pastel'];

    switch (style) {
      case MontageStyle.party:
        return _firstAvailable([...bright, ...warm]);
      case MontageStyle.birthday:
        if (mood == PhotoMood.cool) {
          return _firstAvailable([...bright, ...warm]);
        }
        return _firstAvailable([...bright, ...warm, 'none']);
      case MontageStyle.travel:
        if (mood == PhotoMood.cool) {
          return _firstAvailable([...cool, ...bright]);
        }
        return _firstAvailable([...bright, ...cool]);
      case MontageStyle.newyear:
        if (mood == PhotoMood.warm) {
          return _firstAvailable([...warm, ...bright]);
        }
        return _firstAvailable([...cool, ...bright, 'none']);
      case MontageStyle.romance:
        return _firstAvailable([...warm, ...soft, 'vintage']);
      case MontageStyle.wedding:
        return _firstAvailable([...soft, ...warm, 'vintage']);
      case MontageStyle.nostalgia:
        return _firstAvailable(['vintage', ...soft, ...warm, 'none']);
      case MontageStyle.family:
        if (mood == PhotoMood.cool) return _firstAvailable(cool);
        if (mood == PhotoMood.vibrant) return _firstAvailable(bright);
        return _firstAvailable([...warm, 'none']);
      default:
        break;
    }

    switch (mood) {
      case PhotoMood.warm:
        return _firstAvailable(warm);
      case PhotoMood.cool:
        return _firstAvailable(cool);
      case PhotoMood.vibrant:
        return _firstAvailable(bright);
      case PhotoMood.muted:
        return _firstAvailable([...soft, ...warm, 'none']);
      default:
        return FilterType.none;
    }
  }

  static FilterType _firstAvailable(List<String> names) {
    for (final n in names) {
      if (n == 'none') return FilterType.none;
      for (final f in FilterType.values) {
        if (f.name == n) return f;
      }
    }
    return FilterType.none;
  }

  // ==========================================
  // Умное центрирование лиц в cover-режиме
  // ==========================================
  static List<double> _smartOffsets(
      SmartPhotoAnalysis a, double canvasAspect) {
    if (a.faceCenterX == null || a.faceCenterY == null) return [0.0, 0.0];

    final ia = a.aspectRatio;
    final ca = canvasAspect;

    final base = math.max(ca / ia, 1.0);
    final drawW = ia * base;
    final drawH = base;
    final freeX = (ca - drawW).abs() / 2;
    final freeY = (1.0 - drawH).abs() / 2;

    double ox = 0;
    double oy = 0;
    if (freeX > 0.001) {
      ox = (drawW * (0.5 - a.faceCenterX!) / freeX).clamp(-1.0, 1.0);
    }
    if (freeY > 0.001) {
      oy = (drawH * (0.5 - a.faceCenterY!) / freeY).clamp(-1.0, 1.0);
    }
    return [ox, oy];
  }
}