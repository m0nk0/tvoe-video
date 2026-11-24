import 'package:hive/hive.dart';

part 'keyframe.g.dart';

// ==========================================
// ✅ Кейфрейм: состояние фото в момент времени
// tMs — момент ВНУТРИ кадра (0..durationMilliseconds)
// ==========================================
@HiveType(typeId: 14)
class Keyframe extends HiveObject {
  @HiveField(0)
  double tMs; // момент внутри кадра, мс

  @HiveField(1)
  double scale; // 0.5..3.0

  @HiveField(2)
  double offsetX; // -1..1 (доли ширины)

  @HiveField(3)
  double offsetY; // -1..1 (доли высоты)

  @HiveField(4)
  double opacity; // 0..1

  @HiveField(5)
  double rotation; // радианы

  Keyframe({
    this.tMs = 0,
    this.scale = 1,
    this.offsetX = 0,
    this.offsetY = 0,
    this.opacity = 1,
    this.rotation = 0,
  });

  Keyframe copyWith({
    double? tMs,
    double? scale,
    double? offsetX,
    double? offsetY,
    double? opacity,
    double? rotation,
  }) {
    return Keyframe(
      tMs: tMs ?? this.tMs,
      scale: scale ?? this.scale,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      opacity: opacity ?? this.opacity,
      rotation: rotation ?? this.rotation,
    );
  }

  static Keyframe lerp(Keyframe a, Keyframe b, double t) {
    // ✅ Исправление: l принимает 2 аргумента, t захвачен из замыкания
    double l(double x, double y) => x + (y - x) * t;
    return Keyframe(
      tMs: l(a.tMs, b.tMs),
      scale: l(a.scale, b.scale),
      offsetX: l(a.offsetX, b.offsetX),
      offsetY: l(a.offsetY, b.offsetY),
      opacity: l(a.opacity, b.opacity),
      rotation: l(a.rotation, b.rotation),
    );
  }
}

// ==========================================
// ✅ Семплер: значение кейфреймов в момент tMs
// Пустой список = нейтральное состояние (ничего не меняем)
// ==========================================
Keyframe sampleKeyframes(List<Keyframe> kfs, double tMs) {
  if (kfs.isEmpty) return Keyframe();
  if (kfs.length == 1 || tMs <= kfs.first.tMs) return kfs.first.copyWith(tMs: tMs);
  if (tMs >= kfs.last.tMs) return kfs.last.copyWith(tMs: tMs);
  for (int i = 0; i < kfs.length - 1; i++) {
    final a = kfs[i];
    final b = kfs[i + 1];
    if (tMs >= a.tMs && tMs <= b.tMs) {
      final span = (b.tMs - a.tMs).abs();
      final t = span < 0.001 ? 0.0 : (tMs - a.tMs) / span;
      return Keyframe.lerp(a, b, t);
    }
  }
  return kfs.last.copyWith(tMs: tMs);
}