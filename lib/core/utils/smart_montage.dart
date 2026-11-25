import 'dart:math' as math;

import '../../data/models/keyframe.dart';
import '../../data/models/photo_layer.dart';
import '../../data/models/video_project.dart';
import 'montage_genome.dart';
import 'smart_analyzer.dart';

export 'montage_genome.dart'
    show MontageStyle, MusicProfile, MontageGenome, TransFamily, MotionPolicy, GradePolicy;

// ==========================================
// 🎬 AI-режиссёр: скоринг всех 8 тем + геномный план клипа
// ✅ движение/оверлеи/микро-зум-кейфреймы в плане
// ✅ seed → re-roll; переходы зависят от смены сцены и энергии
// ✅ анти-амплификация: грейд не усиливает родной тон кадра
// ==========================================

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
  // ✅ новые гены
  final LiveMotion liveMotion;
  final OverlayType overlayType;
  final double overlayIntensity;
  final List<Keyframe> keyframes;
  final int beatsPerFrame;

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
    this.liveMotion = LiveMotion.none,
    this.overlayType = OverlayType.none,
    this.overlayIntensity = 0.4,
    this.keyframes = const [],
    this.beatsPerFrame = 2,
  });

  MontageFramePlan copyWith({
    int? durationMs,
    TransitionType? transition,
    FilterType? filter,
    EntranceAnimation? entrance,
    int? entranceDurationMs,
    LiveMotion? liveMotion,
    OverlayType? overlayType,
    double? overlayIntensity,
    List<Keyframe>? keyframes,
    int? beatsPerFrame,
  }) =>
      MontageFramePlan(
        imagePath: imagePath,
        durationMs: durationMs ?? this.durationMs,
        transition: transition ?? this.transition,
        filter: filter ?? this.filter,
        entrance: entrance ?? this.entrance,
        entranceDurationMs: entranceDurationMs ?? this.entranceDurationMs,
        fitMode: fitMode,
        offsetX: offsetX,
        offsetY: offsetY,
        liveMotion: liveMotion ?? this.liveMotion,
        overlayType: overlayType ?? this.overlayType,
        overlayIntensity: overlayIntensity ?? this.overlayIntensity,
        keyframes: keyframes ?? this.keyframes,
        beatsPerFrame: beatsPerFrame ?? this.beatsPerFrame,
      );
}

class SmartMontage {
  // ==========================================
  // ✅ Скоринг ВСЕХ 8 тем (вместо 4 порогов)
  // ==========================================
  static MontageStyle autoDetect(List<SmartPhotoAnalysis> analyses) {
    final ranked = rankThemes(analyses);
    return ranked.isEmpty ? MontageStyle.family : ranked.first.key;
  }

  static List<MapEntry<MontageStyle, double>> rankThemes(List<SmartPhotoAnalysis> a) {
    if (a.isEmpty) return [const MapEntry(MontageStyle.family, 1)];
    final n = a.length.toDouble();
    double faces = 0, group = 0, smiles = 0, warm = 0, cool = 0, vibrant = 0, muted = 0, dark = 0, pastel = 0;
    for (final x in a) {
      if (x.faceCount > 0) faces++;
      if (x.faceCount >= 2) group++;
      if (x.hasSmile) smiles++;
      if (x.mood == PhotoMood.warm) warm++;
      if (x.mood == PhotoMood.cool) cool++;
      if (x.mood == PhotoMood.vibrant) vibrant++;
      if (x.mood == PhotoMood.muted) muted++;
      if (x.brightness < 0.28) dark++;
      if (x.brightness > 0.68 && _satOf(x.dominantColor) < 0.25) pastel++;
    }
    faces /= n; group /= n; smiles /= n; warm /= n; cool /= n; vibrant /= n; muted /= n; dark /= n; pastel /= n;

    final scores = <MontageStyle, double>{
      MontageStyle.family: faces * 1.2 + warm * 0.6 + muted * 0.5 + smiles * 0.4,
      MontageStyle.travel: (1 - faces) * 1.1 + cool * 0.8 + vibrant * 0.5,
      MontageStyle.party: vibrant * 1.1 + group * 0.7 + smiles * 0.6 + dark * 0.3,
      MontageStyle.romance: warm * 1.0 + (faces > 0 && faces < 0.6 ? 0.6 : 0) + muted * 0.3,
      MontageStyle.birthday: vibrant * 0.9 + smiles * 0.9 + group * 0.5,
      MontageStyle.wedding: pastel * 1.3 + faces * 0.5 + warm * 0.3,
      MontageStyle.newyear: cool * 0.8 + dark * 0.7 + vibrant * 0.4,
      MontageStyle.nostalgia: muted * 1.2 + (1 - vibrant) * 0.4 + warm * 0.2,
    };
    final list = scores.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
    return list;
  }

  static double _satOf(int argb) {
    final r = (argb & 0xFF) / 255.0;
    final g = ((argb >> 8) & 0xFF) / 255.0;
    final b = ((argb >> 16) & 0xFF) / 255.0;
    final mx = math.max(r, math.max(g, b));
    final mn = math.min(r, math.min(g, b));
    final l = (mx + mn) / 2;
    if (mx == mn) return 0;
    return (mx - mn) / (1 - (2 * l - 1).abs());
  }

  static double _colorDist(int c1, int c2) {
    double d(int sh) {
      final a = ((c1 >> sh) & 0xFF).toDouble();
      final b = ((c2 >> sh) & 0xFF).toDouble();
      return (a - b) * (a - b);
    }
    return math.sqrt(d(0) + d(8) + d(16));
  }

  // ==========================================
  // Генерация плана по геному
  // ==========================================
  static List<MontageFramePlan> generate({
    required List<SmartPhotoAnalysis> analyses,
    required MontageStyle style,
    required double canvasAspect,
    int seed = 1,
    MusicProfile? music,
    MontageGenome? genome,
  }) {
    if (analyses.isEmpty) return [];
    final theme = style == MontageStyle.auto ? autoDetect(analyses) : style;
    final g = genome ??
        MontageGenome.sample(theme: theme, analyses: analyses, music: music, seed: seed);
    final r = math.Random(seed * 7919 + 13);

    final list = List<SmartPhotoAnalysis>.from(analyses);
    if (g.structure == StructurePolicy.finale && list.length >= 3) {
      int best = 0;
      double bs = -1;
      for (int i = 0; i < list.length; i++) {
        final s = _score(list[i]);
        if (s > bs) { bs = s; best = i; }
      }
      list.add(list.removeAt(best));
    }

    final plans = <MontageFramePlan>[];
    for (int i = 0; i < list.length; i++) {
      final a = list[i];
      final prev = i > 0 ? list[i - 1] : null;

      // длительность
      int dur = g.baseMs;
      if (a.isSlowPaced) dur += 600;
      if (a.isFastPaced) dur -= 500;
      dur = dur.clamp(1000, 5000);

      // переход: family + смена сцены
      TransitionType tr = TransitionType.none;
      if (i > 0) {
        final pool = _familyPool(g.family);
        final dist = prev == null ? 999.0 : _colorDist(prev.dominantColor, a.dominantColor);
        final softSubset = pool.where((t) =>
            t == TransitionType.fade || t == TransitionType.dissolve || t == TransitionType.blur).toList();
        final usePool = (dist < 45 && softSubset.isNotEmpty) ? softSubset : pool;
        tr = usePool[r.nextInt(usePool.length)];
      }

      // движение по политике + содержанию кадра
      LiveMotion motion;
      List<Keyframe> kfs = const [];
      switch (g.motion) {
        case MotionPolicy.calm:
          motion = a.faceCount > 0
              ? (r.nextBool() ? LiveMotion.breathe : LiveMotion.zoomIn)
              : (r.nextBool() ? LiveMotion.breathe : LiveMotion.zoomOut);
          break;
        case MotionPolicy.scenic:
          motion = i.isEven ? LiveMotion.panLeft : LiveMotion.panRight;
          break;
        case MotionPolicy.lively:
          motion = [LiveMotion.zoomIn, LiveMotion.zoomOut, LiveMotion.breathe][r.nextInt(3)];
          break;
        case MotionPolicy.static:
          motion = LiveMotion.none;
          // микро-зум кейфреймами, чтобы кадр не был мёртвым
          kfs = [
            Keyframe(tMs: 0, scale: 1.0),
            Keyframe(tMs: dur.toDouble(), scale: 1.06),
          ];
          break;
      }

      // ✅ грейд + анти-амплификация: не усиливаем родной тон кадра
      FilterType filter = _gradeFilter(g.grade);
      if (g.grade == GradePolicy.cool && a.mood == PhotoMood.cool) filter = FilterType.none;
      if (g.grade == GradePolicy.warm && a.mood == PhotoMood.warm) filter = FilterType.none;
      if (g.grade == GradePolicy.vivid && a.mood == PhotoMood.muted) filter = FilterType.none;

      // появление
      final entrances = g.entrance == EntrancePolicy.soft
          ? [EntranceAnimation.fadeIn, EntranceAnimation.none, EntranceAnimation.fadeIn]
          : [EntranceAnimation.zoomIn, EntranceAnimation.slideFromLeft, EntranceAnimation.slideFromRight, EntranceAnimation.slideFromBottom];
      final entrance = entrances[r.nextInt(entrances.length)];

      final offsets = _smartOffsets(a, canvasAspect);

      plans.add(MontageFramePlan(
        imagePath: a.imagePath,
        durationMs: dur,
        transition: tr,
        filter: filter,
        entrance: entrance,
        entranceDurationMs: _entranceMsFor(g.theme),
        fitMode: FitMode.cover,
        offsetX: offsets[0],
        offsetY: offsets[1],
        liveMotion: motion,
        overlayType: g.overlay,
        overlayIntensity: g.overlayIntensity,
        keyframes: kfs,
        beatsPerFrame: g.tempoK,
      ));
    }
    return plans;
  }

  static List<TransitionType> _familyPool(TransFamily f) {
    switch (f) {
      case TransFamily.soft:
        return [TransitionType.fade, TransitionType.dissolve, TransitionType.blur];
      case TransFamily.dynamic:
        return [TransitionType.slideLeft, TransitionType.slideRight, TransitionType.zoomIn, TransitionType.zoomOut, TransitionType.whipPan, TransitionType.crossZoom, TransitionType.wipe];
      case TransFamily.glitch:
        return [TransitionType.glitch, TransitionType.rgbSplit, TransitionType.flash, TransitionType.spinBlur];
      case TransFamily.reveal:
        return [TransitionType.circleReveal, TransitionType.wipe, TransitionType.crossZoom, TransitionType.flash];
    }
  }

  static FilterType _gradeFilter(GradePolicy g) {
    switch (g) {
      case GradePolicy.neutral: return FilterType.none;
      case GradePolicy.warm: return FilterType.warm;
      case GradePolicy.cool: return FilterType.cool;
      case GradePolicy.vivid: return FilterType.vivid;
      case GradePolicy.vintage: return FilterType.vintage;
      case GradePolicy.film: return FilterType.film;
    }
  }

  static double _score(SmartPhotoAnalysis a) =>
      a.complexityScore + (a.hasSmile ? 0.3 : 0.0) + (a.faceCount > 0 ? 0.2 : 0.0);

  static int _entranceMsFor(MontageStyle style) {
    switch (style) {
      case MontageStyle.party: return 400;
      case MontageStyle.birthday: return 450;
      case MontageStyle.newyear: return 500;
      case MontageStyle.romance: return 600;
      case MontageStyle.wedding: return 700;
      case MontageStyle.nostalgia: return 800;
      default: return 500;
    }
  }

  static List<double> _smartOffsets(SmartPhotoAnalysis a, double canvasAspect) {
    if (a.faceCenterX == null || a.faceCenterY == null) return [0.0, 0.0];
    final ia = a.aspectRatio;
    final ca = canvasAspect;
    final base = math.max(ca / ia, 1.0);
    final drawW = ia * base;
    final drawH = base;
    final freeX = (ca - drawW).abs() / 2;
    final freeY = (1.0 - drawH).abs() / 2;
    double ox = 0, oy = 0;
    if (freeX > 0.001) ox = (drawW * (0.5 - a.faceCenterX!) / freeX).clamp(-1.0, 1.0);
    if (freeY > 0.001) oy = (drawH * (0.5 - a.faceCenterY!) / freeY).clamp(-1.0, 1.0);
    return [ox, oy];
  }
}