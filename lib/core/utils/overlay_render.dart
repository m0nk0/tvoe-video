import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/models/video_project.dart';

// ==========================================
// Анимированные оверлеи всего видео
// ✅ 9 оверлеев + регулировка интенсивности (k)
// ✅ Детерминированный рендер: превью == экспорт
// ==========================================

/// Рисует оверлей поверх готового кадра
/// [intensity] — 0.1..1.0 (дефолт 0.6 = прежняя сила)
void paintOverlay(
  Canvas canvas,
  OverlayType type,
  int timeMs,
  int width,
  int height,
  double intensity,
) {
  // k = 1.0 при интенсивности 0.6 (прежний вид), сильнее/слабее по краям
  final k = (intensity.clamp(0.1, 1.0) / 0.6).clamp(0.15, 1.8);
  switch (type) {
    case OverlayType.none:
      return;
    case OverlayType.film:
      _paintFilm(canvas, timeMs, width, height, k);
      return;
    case OverlayType.cinema:
      _paintCinema(canvas, width, height, k);
      return;
    case OverlayType.vhs:
      _paintVhs(canvas, timeMs, width, height, k);
      return;
    case OverlayType.lightleak:
      _paintLightLeak(canvas, timeMs, width, height, k);
      return;
    case OverlayType.dreamy:
      _paintDreamy(canvas, timeMs, width, height, k);
      return;
    case OverlayType.bokeh:
      _paintBokeh(canvas, timeMs, width, height, k);
      return;
    case OverlayType.snow:
      _paintSnow(canvas, timeMs, width, height, k);
      return;
    case OverlayType.cyber:
      _paintCyber(canvas, timeMs, width, height, k);
      return;
  }
}

/// Масштабированная прозрачность с клампом
double _a(double base, double k) => (base * k).clamp(0.0, 1.0);

// ==========================================
// 🎞 КИНОПЛЁНКА
// ==========================================
void _paintFilm(Canvas canvas, int timeMs, int width, int height, double k) {
  final rnd = math.Random(timeMs ~/ 66);
  final fullRect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());

  final flicker = rnd.nextDouble() * 0.06;
  if (flicker > 0.02) {
    canvas.drawRect(
      fullRect,
      Paint()..color = Colors.black.withOpacity(_a(flicker, k)),
    );
  }

  final grainPaint = Paint();
  final grainCount = (width * height / 9000).round().clamp(60, 260);
  for (int i = 0; i < grainCount; i++) {
    final x = rnd.nextDouble() * width;
    final y = rnd.nextDouble() * height;
    final s = 1.0 + rnd.nextDouble() * 2.2;
    final isWhite = rnd.nextBool();
    grainPaint.color = (isWhite ? Colors.white : Colors.black)
        .withOpacity(_a(0.05 + rnd.nextDouble() * 0.09, k));
    canvas.drawRect(Rect.fromLTWH(x, y, s, s), grainPaint);
  }

  if (rnd.nextDouble() < 0.30) {
    final x = rnd.nextDouble() * width;
    canvas.drawRect(
      Rect.fromLTWH(x, 0, 1.5, height.toDouble()),
      Paint()..color = Colors.white.withOpacity(_a(0.16, k)),
    );
  }

  if (rnd.nextDouble() < 0.18) {
    final x = rnd.nextDouble() * width;
    final y = rnd.nextDouble() * height;
    canvas.drawCircle(
      Offset(x, y),
      2.5 + rnd.nextDouble() * 4,
      Paint()..color = Colors.white.withOpacity(_a(0.10, k)),
    );
  }

  _paintVignette(canvas, width, height, _a(0.35, k));
}

// ==========================================
// 🎬 КИНО 2.35:1
// ==========================================
void _paintCinema(Canvas canvas, int width, int height, double k) {
  final barHeight = (height - width / 2.35) / 2;
  if (barHeight > 0) {
    final barPaint = Paint()..color = const Color(0xFF000000);
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), barHeight), barPaint);
    canvas.drawRect(
        Rect.fromLTWH(0, height - barHeight, width.toDouble(), barHeight),
        barPaint);
  }
  _paintVignette(canvas, width, height, _a(0.45, k));
}

// ==========================================
// 📼 VHS
// ==========================================
void _paintVhs(Canvas canvas, int timeMs, int width, int height, double k) {
  final w = width.toDouble();
  final h = height.toDouble();

  final scanPaint = Paint()..color = Colors.black.withOpacity(_a(0.10, k));
  for (double y = 0; y < h; y += 4) {
    canvas.drawRect(Rect.fromLTWH(0, y, w, 1.2), scanPaint);
  }

  final bandY = (timeMs * 0.12) % (h + 240) - 120;
  final rnd = math.Random(timeMs ~/ 100);
  canvas.drawRect(
    Rect.fromLTWH(0, bandY, w, 26),
    Paint()..color = Colors.white.withOpacity(_a(0.05, k)),
  );
  final noisePaint = Paint();
  for (int i = 0; i < 40; i++) {
    final x = rnd.nextDouble() * w;
    final y = bandY + rnd.nextDouble() * 26;
    noisePaint.color =
        Colors.white.withOpacity(_a(0.08 + rnd.nextDouble() * 0.12, k));
    canvas.drawRect(Rect.fromLTWH(x, y, 2 + rnd.nextDouble() * 8, 1.5), noisePaint);
  }

  final blink = (timeMs % 1200) < 700;
  final fontSize = w * 0.035;
  if (blink) {
    canvas.drawCircle(
      Offset(w * 0.06, h * 0.065),
      fontSize * 0.35,
      Paint()..color = const Color(0xFFE53935),
    );
  }
  final recPainter = TextPainter(
    text: TextSpan(
      text: 'REC',
      style: TextStyle(
        color: const Color(0xFFE53935),
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  recPainter.paint(
    canvas,
    Offset(w * 0.06 + fontSize * 0.7, h * 0.065 - recPainter.height / 2),
  );

  final mm = (timeMs ~/ 60000).toString().padLeft(2, '0');
  final ss = ((timeMs % 60000) ~/ 1000).toString().padLeft(2, '0');
  final ff = ((timeMs % 1000) ~/ 33).toString().padLeft(2, '0');
  final tcPainter = TextPainter(
    text: TextSpan(
      text: '$mm:$ss:$ff',
      style: TextStyle(
        color: Colors.white.withOpacity(_a(0.85, k)),
        fontSize: fontSize * 0.9,
        fontWeight: FontWeight.w700,
        fontFamily: 'monospace',
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tcPainter.paint(
    canvas,
    Offset(w - tcPainter.width - w * 0.05, h - tcPainter.height - h * 0.05),
  );

  _paintVignette(canvas, width, height, _a(0.30, k));
}

// ==========================================
// 🌅 ЗАСВЕТКИ (light leaks): тёплые пятна по углам, плывут
// ==========================================
void _paintLightLeak(Canvas canvas, int timeMs, int width, int height, double k) {
  final w = width.toDouble();
  final h = height.toDouble();
  final fullRect = Rect.fromLTWH(0, 0, w, h);
  final t1 = timeMs / 2600.0;
  final t2 = timeMs / 3400.0 + 1.7;

  final p1 = Offset(w * (0.15 + 0.12 * math.sin(t1)), h * (0.2 + 0.1 * math.cos(t1 * 0.8)));
  final p2 = Offset(w * (0.85 - 0.12 * math.cos(t2)), h * (0.8 - 0.12 * math.sin(t2)));
  final r = math.max(w, h) * 0.6;

  canvas.drawRect(
    fullRect,
    Paint()
      ..shader = ui.Gradient.radial(p1, r, [
        Color.fromRGBO(255, 120, 40, _a(0.38, k)),
        const Color(0x00000000),
      ]),
  );
  canvas.drawRect(
    fullRect,
    Paint()
      ..shader = ui.Gradient.radial(p2, r, [
        Color.fromRGBO(255, 60, 120, _a(0.30, k)),
        const Color(0x00000000),
      ]),
  );

  final pulse = (math.sin(timeMs / 900) + 1) / 2;
  canvas.drawRect(
    fullRect,
    Paint()..color = Colors.white.withOpacity(_a(0.05 * pulse, k)),
  );
}

// ==========================================
// ☁️ ДРИМ: мягкое свечение + парящие световые пятна
// ==========================================
void _paintDreamy(Canvas canvas, int timeMs, int width, int height, double k) {
  final w = width.toDouble();
  final h = height.toDouble();
  final fullRect = Rect.fromLTWH(0, 0, w, h);
  final pulse = 0.8 + 0.2 * math.sin(timeMs / 1200);

  // Центральное свечение
  canvas.drawRect(
    fullRect,
    Paint()
      ..shader = ui.Gradient.radial(
        Offset(w / 2, h / 2),
        math.max(w, h) * 0.7,
        [
          Color.fromRGBO(255, 255, 255, _a(0.16 * pulse, k)),
          const Color(0x00000000),
        ],
      ),
  );

  // Верхний мягкий свет
  canvas.drawRect(
    fullRect,
    Paint()
      ..shader = ui.Gradient.radial(
        Offset(w * 0.5, -h * 0.25),
        math.max(w, h) * 0.8,
        [
          Color.fromRGBO(255, 240, 220, _a(0.14, k)),
          const Color(0x00000000),
        ],
      ),
  );

  // Парящие мягкие пятна
  for (int i = 0; i < 7; i++) {
    final rnd = math.Random(i * 71 + 13);
    final bx = rnd.nextDouble() * w;
    final speed = 0.008 + rnd.nextDouble() * 0.012;
    final phase = rnd.nextDouble() * 6.28;
    final size = 24.0 + rnd.nextDouble() * 46.0;
    double y = (rnd.nextDouble() * h - timeMs * speed) % h;
    if (y < 0) y += h;
    final x = bx + math.sin(timeMs / 1400 + phase) * 18;
    canvas.drawCircle(
      Offset(x, y),
      size,
      Paint()
        ..shader = ui.Gradient.radial(Offset(x, y), size, [
          Color.fromRGBO(255, 255, 255, _a(0.10, k)),
          const Color(0x00000000),
        ]),
    );
  }
}

// ==========================================
// ✨ ЗОЛОТАЯ ПЫЛЬ: боке-частицы плывут вверх
// ==========================================
void _paintBokeh(Canvas canvas, int timeMs, int width, int height, double k) {
  final w = width.toDouble();
  final h = height.toDouble();

  for (int i = 0; i < 24; i++) {
    final rnd = math.Random(i * 131 + 7);
    final bx = rnd.nextDouble() * w;
    final speed = 0.012 + rnd.nextDouble() * 0.02;
    final phase = rnd.nextDouble() * 6.28;
    final size = 2.0 + rnd.nextDouble() * 2.2;

    double y = (rnd.nextDouble() * h - timeMs * speed) % h;
    if (y < 0) y += h;
    final x = bx + math.sin(timeMs / 900 + phase) * 12;
    final twinkle = (math.sin(timeMs / 700 + phase) + 1) / 2;
    final alpha = _a(0.22 + 0.28 * twinkle, k);

    // ореол
    canvas.drawCircle(
      Offset(x, y),
      size * 2.4,
      Paint()..color = Color.fromRGBO(255, 200, 90, alpha * 0.30),
    );
    // ядро
    canvas.drawCircle(
      Offset(x, y),
      size,
      Paint()..color = Color.fromRGBO(255, 225, 140, alpha),
    );
  }
}

// ==========================================
// ❄️ СНЕГ: падающие снежинки с покачиванием
// ==========================================
void _paintSnow(Canvas canvas, int timeMs, int width, int height, double k) {
  final w = width.toDouble();
  final h = height.toDouble();

  for (int i = 0; i < 40; i++) {
    final rnd = math.Random(i * 97 + 11);
    final speed = 0.03 + rnd.nextDouble() * 0.05;
    final size = 1.5 + rnd.nextDouble() * 3.0;
    final phase = rnd.nextDouble() * 6.28;
    final bx = rnd.nextDouble() * w;

    final y = (rnd.nextDouble() * h + timeMs * speed) % h;
    final x = bx + math.sin(timeMs / 800 + phase) * 14;
    final alpha = _a(0.45 + rnd.nextDouble() * 0.35, k);

    canvas.drawCircle(
      Offset(x, y),
      size,
      Paint()..color = Colors.white.withOpacity(alpha),
    );
  }
}

// ==========================================
// ⚡ КИБЕР-ВОЛНА: глитч-полосы cyan/magenta + сканлайны
// ==========================================
void _paintCyber(Canvas canvas, int timeMs, int width, int height, double k) {
  final w = width.toDouble();
  final h = height.toDouble();

  // Постоянные тонкие сканлайны
  final scanPaint = Paint()..color = Colors.black.withOpacity(_a(0.05, k));
  for (double y = 0; y < h; y += 6) {
    canvas.drawRect(Rect.fromLTWH(0, y, w, 1.0), scanPaint);
  }

  // Периодические глитч-всплески
  final cycle = timeMs % 2200;
  if (cycle < 320) {
    final rnd = math.Random(timeMs ~/ 60);
    for (int s = 0; s < 5; s++) {
      final y = rnd.nextDouble() * h;
      final bh = 4 + rnd.nextDouble() * 18;
      canvas.drawRect(
        Rect.fromLTWH(0, y, w, bh),
        Paint()..color = Color.fromRGBO(0, 255, 240, _a(0.10, k)),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, y + bh, w, 2),
        Paint()..color = Color.fromRGBO(255, 0, 90, _a(0.18, k)),
      );
    }
    final noisePaint = Paint();
    for (int n = 0; n < 20; n++) {
      final x = rnd.nextDouble() * w;
      final y = rnd.nextDouble() * h;
      noisePaint.color =
          Colors.white.withOpacity(_a(0.06 + rnd.nextDouble() * 0.10, k));
      canvas.drawRect(Rect.fromLTWH(x, y, 3 + rnd.nextDouble() * 10, 1.5), noisePaint);
    }
  }
}

// ==========================================
// Виньетка
// ==========================================
void _paintVignette(Canvas canvas, int width, int height, double strength) {
  if (strength <= 0.01) return;
  final shader = ui.Gradient.radial(
    Offset(width / 2, height / 2),
    math.max(width, height) * 0.75,
    [
      const Color(0x00000000),
      Color.fromRGBO(0, 0, 0, strength.clamp(0.0, 0.85)),
    ],
    [0.55, 1.0],
  );
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..shader = shader,
  );
}