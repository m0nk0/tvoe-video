import 'dart:math' as math;

import '../../data/models/photo_layer.dart';
import '../../data/models/video_project.dart';
import 'beat_detector.dart';
import 'smart_analyzer.dart';

// ==========================================
// 🧬 Геном клипа: независимые гены + матрица совместимости.
// Скрещивание = независимый сэмпл генов; фидбек = мутация выбранных генов.
// ✅ Грейд — по долям настроений фото (осознанно, не монеткой).
// ✅ Темп — по плотности битов музыки (кадр ≈ baseMs на сетке битов).
// ==========================================

/// Стиль/тема монтажа (перенесён сюда, smart_montage ре-экспортирует)
enum MontageStyle {
  auto, family, travel, party, romance, birthday, wedding, newyear, nostalgia,
}

enum TransFamily { soft, dynamic, glitch, reveal }
enum MotionPolicy { calm, scenic, lively, static }
enum GradePolicy { neutral, warm, cool, vivid, vintage, film }
enum EntrancePolicy { soft, lively }
enum StructurePolicy { chrono, finale }

/// Профиль музыки (энергия и плотность битов управляют темпом и драйвом)
class MusicProfile {
  final double bpm;
  final double energy; // 0..1 средняя амплитуда волны
  final double density; // битов в секунду
  final String? tag; // стиль bundled-трека, если известен

  const MusicProfile({this.bpm = 0, this.energy = 0, this.density = 0, this.tag});

  bool get isValid => bpm > 0;

  /// low / mid / high
  String get energyClass {
    if (bpm > 120 || energy > 0.45) return 'high';
    if (bpm < 85 && energy < 0.25) return 'low';
    return 'mid';
  }

  factory MusicProfile.fromBeats(BeatAnalysis a, {String? tag}) {
    final w = a.waveform;
    final e = w.isEmpty ? 0.0 : w.reduce((x, y) => x + y) / w.length;
    final d = a.durationSec > 0 ? a.beats.length / a.durationSec : 0.0;
    return MusicProfile(bpm: a.bpm, energy: e, density: d, tag: tag);
  }
}

class MontageGenome {
  final MontageStyle theme;
  final TransFamily family;
  final MotionPolicy motion;
  final GradePolicy grade;
  final OverlayType overlay;
  final double overlayIntensity;
  final EntrancePolicy entrance;
  final StructurePolicy structure;
  final int tempoK; // битов на кадр
  final int baseMs;

  const MontageGenome({
    required this.theme,
    required this.family,
    required this.motion,
    required this.grade,
    required this.overlay,
    required this.overlayIntensity,
    required this.entrance,
    required this.structure,
    required this.tempoK,
    required this.baseMs,
  });

  // ---- Матрица совместимости: тема ограничивает пулы генов ----
  static const Map<MontageStyle, List<TransFamily>> _families = {
    MontageStyle.party: [TransFamily.glitch, TransFamily.dynamic],
    MontageStyle.birthday: [TransFamily.reveal, TransFamily.dynamic],
    MontageStyle.travel: [TransFamily.dynamic, TransFamily.reveal],
    MontageStyle.newyear: [TransFamily.reveal, TransFamily.soft],
    MontageStyle.romance: [TransFamily.soft],
    MontageStyle.wedding: [TransFamily.soft, TransFamily.reveal],
    MontageStyle.nostalgia: [TransFamily.soft],
    MontageStyle.family: [TransFamily.soft, TransFamily.reveal],
    MontageStyle.auto: [TransFamily.soft, TransFamily.reveal],
  };

  static const Map<MontageStyle, List<MotionPolicy>> _motions = {
    MontageStyle.party: [MotionPolicy.lively],
    MontageStyle.birthday: [MotionPolicy.lively, MotionPolicy.calm],
    MontageStyle.travel: [MotionPolicy.scenic, MotionPolicy.lively],
    MontageStyle.newyear: [MotionPolicy.scenic, MotionPolicy.calm],
    MontageStyle.romance: [MotionPolicy.calm],
    MontageStyle.wedding: [MotionPolicy.calm],
    MontageStyle.nostalgia: [MotionPolicy.calm, MotionPolicy.static],
    MontageStyle.family: [MotionPolicy.calm, MotionPolicy.scenic],
    MontageStyle.auto: [MotionPolicy.calm, MotionPolicy.scenic],
  };

  static const Map<MontageStyle, List<GradePolicy>> _grades = {
    MontageStyle.party: [GradePolicy.vivid, GradePolicy.cool],
    MontageStyle.birthday: [GradePolicy.vivid, GradePolicy.warm],
    // ✅ travel без глобального холода: лето не должно синеть
    MontageStyle.travel: [GradePolicy.vivid, GradePolicy.neutral],
    MontageStyle.newyear: [GradePolicy.cool, GradePolicy.film],
    MontageStyle.romance: [GradePolicy.warm, GradePolicy.vintage],
    MontageStyle.wedding: [GradePolicy.neutral, GradePolicy.warm],
    MontageStyle.nostalgia: [GradePolicy.vintage, GradePolicy.film],
    MontageStyle.family: [GradePolicy.warm, GradePolicy.neutral, GradePolicy.vivid],
    MontageStyle.auto: [GradePolicy.warm, GradePolicy.neutral],
  };

  static const Map<MontageStyle, int> _baseMs = {
    MontageStyle.party: 1600,
    MontageStyle.birthday: 1800,
    MontageStyle.travel: 2400,
    MontageStyle.newyear: 2500,
    MontageStyle.romance: 3200,
    MontageStyle.wedding: 4000,
    MontageStyle.nostalgia: 4500,
    MontageStyle.family: 2800,
    MontageStyle.auto: 2800,
  };

  static T _pick<T>(math.Random r, List<T> pool, {T? avoid}) {
    if (pool.isEmpty) throw StateError('Пустой пул гена');
    if (pool.length == 1) return pool.first;
    var v = pool[r.nextInt(pool.length)];
    if (avoid != null && pool.length > 1) {
      int guard = 0;
      while (v == avoid && guard++ < 4) v = pool[r.nextInt(pool.length)];
    }
    return v;
  }

  // ==========================================
  // ✅ Осознанный пул грейда: по долям настроений фото
  // (mood считается попиксельно в анализаторе — это честный сигнал сочности)
  // ==========================================
  static List<GradePolicy> _gradePool(MontageStyle t, List<SmartPhotoAnalysis> analyses) {
    final pool = List<GradePolicy>.from(_grades[t]!);
    if (analyses.isEmpty) return pool;
    final n = analyses.length.toDouble();
    final vibrantRatio = analyses.where((a) => a.mood == PhotoMood.vibrant).length / n;
    final mutedRatio = analyses.where((a) => a.mood == PhotoMood.muted).length / n;
    if (vibrantRatio >= 0.5) {
      // большинство кадров уже сочные → не пересаливаем
      pool.remove(GradePolicy.vivid);
      if (!pool.contains(GradePolicy.neutral)) pool.add(GradePolicy.neutral);
    } else if (mutedRatio >= 0.5) {
      // большинство блёклые → обязательно оживляем
      pool.remove(GradePolicy.neutral);
      if (!pool.contains(GradePolicy.vivid)) pool.add(GradePolicy.vivid);
    }
    return pool.isEmpty ? List<GradePolicy>.from(_grades[t]!) : pool;
  }

  // ==========================================
  // ✅ Темп: кадр ≈ baseMs, но привязан к сетке битов
  // k = baseSec × density (бит/с), clamp 1..8
  // ==========================================
  static int _tempoK(MusicProfile? m, int baseMs, math.Random r) {
    if (m == null || !m.isValid || m.density <= 0) return _pick(r, [2, 2, 4]);
    return (baseMs / 1000 * m.density).round().clamp(1, 8);
  }

  /// Сэмпл целого генома (скрещивание совместимых пулов)
  factory MontageGenome.sample({
    required MontageStyle theme,
    required List<SmartPhotoAnalysis> analyses,
    MusicProfile? music,
    int seed = 1,
  }) {
    final r = math.Random(seed);
    final t = theme == MontageStyle.auto ? MontageStyle.family : theme;
    final energy = music?.energyClass ?? 'mid';

    // Драйв музыки сдвигает family внутри разрешённого пула
    var famPool = _families[t]!;
    if (energy == 'high' && famPool.contains(TransFamily.dynamic)) {
      famPool = [TransFamily.dynamic, ...famPool];
    }
    if (energy == 'low' && famPool.contains(TransFamily.soft)) {
      famPool = [TransFamily.soft, ...famPool];
    }

    final motion = _pick(r, _motions[t]!);
    final overlayPool = t == MontageStyle.nostalgia || t == MontageStyle.romance
        ? [OverlayType.film, OverlayType.none]
        : [OverlayType.none, OverlayType.none, OverlayType.film];

    return MontageGenome(
      theme: t,
      family: _pick(r, famPool),
      motion: motion,
      // ✅ грейд по данным фото, а не монеткой
      grade: _pick(r, _gradePool(t, analyses)),
      overlay: _pick(r, overlayPool),
      overlayIntensity: 0.25 + r.nextDouble() * 0.3,
      entrance: (t == MontageStyle.party ||
              t == MontageStyle.birthday ||
              t == MontageStyle.travel)
          ? EntrancePolicy.lively
          : EntrancePolicy.soft,
      structure: analyses.length >= 3 ? StructurePolicy.finale : StructurePolicy.chrono,
      // ✅ темп по плотности битов
      tempoK: _tempoK(music, _baseMs[t]!, r),
      baseMs: _baseMs[t]!,
    );
  }

  /// Мутация: пересэмплировать ТОЛЬКО отмеченные пользователем гены
  MontageGenome mutate(
    Set<String> disliked,
    int seed, {
    MusicProfile? music,
    required List<SmartPhotoAnalysis> analyses,
  }) {
    final r = math.Random(seed);
    final t = theme;
    return MontageGenome(
      theme: disliked.contains('theme')
          ? _pick(r,
              MontageStyle.values.where((s) => s != MontageStyle.auto && s != t).toList(),
              avoid: t)
          : t,
      family: disliked.contains('transitions')
          ? _pick(r, _families[t]!, avoid: family)
          : family,
      motion: disliked.contains('motion') ? _pick(r, _motions[t]!, avoid: motion) : motion,
      grade: disliked.contains('grade')
          ? _pick(r, _gradePool(t, analyses), avoid: grade)
          : grade,
      overlay: disliked.contains('overlay')
          ? _pick(r, [OverlayType.none, OverlayType.film], avoid: overlay)
          : overlay,
      overlayIntensity:
          disliked.contains('overlay') ? 0.25 + r.nextDouble() * 0.3 : overlayIntensity,
      entrance: disliked.contains('entrance')
          ? (entrance == EntrancePolicy.soft ? EntrancePolicy.lively : EntrancePolicy.soft)
          : entrance,
      structure: disliked.contains('structure')
          ? (structure == StructurePolicy.finale
              ? StructurePolicy.chrono
              : StructurePolicy.finale)
          : structure,
      tempoK: disliked.contains('tempo')
          ? (tempoK + (r.nextBool() ? 1 : -1)).clamp(1, 8)
          : tempoK,
      baseMs: disliked.contains('tempo') ? _baseMs[t]! : baseMs,
    );
  }

  /// Человекочитаемое объяснение решения (чип доверия)
  String explain(List<SmartPhotoAnalysis> analyses) {
    final faces = analyses.fold<int>(0, (s, a) => s + a.faceCount);
    final smiles = analyses.where((a) => a.hasSmile).length;
    final parts = <String>[
      'Тема: ${theme.name}',
      'Переходы: ${family.name}',
      'Движение: ${motion.name}',
      'Цвет: ${grade.name}',
      if (overlay != OverlayType.none) 'Оверлей: ${overlay.name}',
      'Темп: $tempoK бита/кадр',
      if (faces > 0) 'Лиц: $faces',
      if (smiles > 0) 'Улыбок: $smiles',
    ];
    return parts.join(' • ');
  }
}