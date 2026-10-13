import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../data/models/photo_layer.dart';

// ==========================================
// Построение перехода по типу
// ✅ 18 переходов: 12 базовых + 6 трендовых
// ==========================================
Widget buildTransition(
    Widget child, Animation<double> animation, TransitionType type) {
  switch (type) {
    case TransitionType.none:
      return child;
    case TransitionType.fade:
      return FadeTransition(opacity: animation, child: child);
    case TransitionType.slideLeft:
      return SlideTransition(
        position:
            Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(animation),
        child: child,
      );
    case TransitionType.slideRight:
      return SlideTransition(
        position:
            Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
                .animate(animation),
        child: child,
      );
    case TransitionType.zoomIn:
      return ScaleTransition(
        scale: Tween<double>(begin: 0.6, end: 1.0)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: FadeTransition(opacity: animation, child: child),
      );
    case TransitionType.zoomOut:
      return ScaleTransition(
        scale: Tween<double>(begin: 1.4, end: 1.0)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: FadeTransition(opacity: animation, child: child),
      );
    case TransitionType.blur:
      return _BlurTransition(animation: animation, child: child);
    case TransitionType.rotate:
      return RotationTransition(
        turns: Tween<double>(begin: 0.25, end: 0.0)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: FadeTransition(opacity: animation, child: child),
      );
    case TransitionType.flip:
      return AnimatedBuilder(
        animation: animation,
        builder: (context, c) {
          final scaleX = animation.value.clamp(0.0, 1.0);
          return Transform(
            transform: Matrix4.identity()
              ..scale(scaleX < 0.5 ? -1.0 + 2 * scaleX : 1.0, 1.0),
            alignment: Alignment.center,
            child: FadeTransition(opacity: animation, child: c),
          );
        },
        child: child,
      );
    case TransitionType.dissolve:
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        child: child,
      );
    case TransitionType.wipe:
      return _ClipRectTransition(animation: animation, child: child);
    case TransitionType.glitch:
      return _GlitchTransition(animation: animation, child: child);

    // ==========================================
    // 🆕 ТРЕНДОВЫЕ ПЕРЕХОДЫ
    // ==========================================
    case TransitionType.whipPan:
      return _WhipPanTransition(animation: animation, child: child);
    case TransitionType.crossZoom:
      return _CrossZoomTransition(animation: animation, child: child);
    case TransitionType.flash:
      return _FlashTransition(animation: animation, child: child);
    case TransitionType.circleReveal:
      return _CircleRevealTransition(animation: animation, child: child);
    case TransitionType.spinBlur:
      return _SpinBlurTransition(animation: animation, child: child);
    case TransitionType.rgbSplit:
      return _RgbSplitTransition(animation: animation, child: child);
  }
}

// ==========================================
// Применение анимации появления
// ==========================================
Widget applyEntranceAnimation(
    EntranceAnimation type, AnimationController controller, Widget child) {
  final t = controller.value.clamp(0.0, 1.0);
  final curvedT = Curves.easeOut.transform(t);

  switch (type) {
    case EntranceAnimation.none:
      return child;
    case EntranceAnimation.fadeIn:
      return Opacity(opacity: curvedT, child: child);
    case EntranceAnimation.slideFromLeft:
      return Transform.translate(
        offset: Offset(-100 * (1 - curvedT), 0),
        child: Opacity(opacity: curvedT, child: child),
      );
    case EntranceAnimation.slideFromRight:
      return Transform.translate(
        offset: Offset(100 * (1 - curvedT), 0),
        child: Opacity(opacity: curvedT, child: child),
      );
    case EntranceAnimation.slideFromTop:
      return Transform.translate(
        offset: Offset(0, -100 * (1 - curvedT)),
        child: Opacity(opacity: curvedT, child: child),
      );
    case EntranceAnimation.slideFromBottom:
      return Transform.translate(
        offset: Offset(0, 100 * (1 - curvedT)),
        child: Opacity(opacity: curvedT, child: child),
      );
    case EntranceAnimation.zoomIn:
      return Transform.scale(
        scale: 0.5 + 0.5 * curvedT,
        child: Opacity(opacity: curvedT, child: child),
      );
    case EntranceAnimation.rotateIn:
      return Transform.rotate(
        angle: (1 - curvedT) * 0.5,
        child: Opacity(opacity: curvedT, child: child),
      );
  }
}

// ==========================================
// Вспомогательные виджеты переходов (базовые)
// ==========================================
class _BlurTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _BlurTransition({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, c) {
        final t = animation.value.clamp(0.0, 1.0);
        final sigma = (1.0 - t) * 12.0;
        return Opacity(
          opacity: t,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: c,
          ),
        );
      },
      child: child,
    );
  }
}

class _ClipRectTransition extends AnimatedWidget {
  final Widget child;

  const _ClipRectTransition({
    required Animation<double> animation,
    required this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    final progress = animation.value.clamp(0.0, 1.0);
    return ClipRect(
      clipper: _WipeClipper(progress),
      child: child,
    );
  }
}

class _WipeClipper extends CustomClipper<Rect> {
  final double progress;
  _WipeClipper(this.progress);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * progress, size.height);
  }

  @override
  bool shouldReclip(_WipeClipper oldClipper) => oldClipper.progress != progress;
}

class _GlitchTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _GlitchTransition({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, c) {
        final t = animation.value;
        final isGlitching = t < 0.5;
        if (!isGlitching) return c!;

        final offset = (1.0 - t * 2) * 10.0;
        return Stack(
          children: [
            Transform.translate(
              offset: Offset(offset, 0),
              child: Opacity(
                opacity: 0.7,
                child: ColorFiltered(
                  colorFilter:
                      const ColorFilter.mode(Color(0xFFFF0000), BlendMode.srcATop),
                  child: c,
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(-offset, 0),
              child: Opacity(
                opacity: 0.7,
                child: ColorFiltered(
                  colorFilter:
                      const ColorFilter.mode(Color(0xFF00FF00), BlendMode.srcATop),
                  child: c,
                ),
              ),
            ),
            c!,
          ],
        );
      },
      child: child,
    );
  }
}

// ==========================================
// 🆕 ⚡ WHIP PAN — резкий сдвиг с motion-blur (пик блюра в середине)
// ==========================================
class _WhipPanTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _WhipPanTransition({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, c) {
        final t = animation.value.clamp(0.0, 1.0);
        final pos = Curves.easeInOutCubic.transform(t);
        final blur = math.sin(math.pi * t) * 14.0; // максимум в середине
        return ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur * 0.25),
          child: FractionalTranslation(
            translation: Offset(1 - pos, 0),
            child: c,
          ),
        );
      },
      child: child,
    );
  }
}

// ==========================================
// 🆕 🔍 CROSS ZOOM — «пролёт» сквозь фото (зум 1.8→1.0 с блюром)
// ==========================================
class _CrossZoomTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _CrossZoomTransition({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, c) {
        final t = animation.value.clamp(0.0, 1.0);
        final curved = Curves.easeInOut.transform(t);
        final scale = 1.8 - 0.8 * curved;
        final blur = (1.0 - curved) * 8.0;
        return Opacity(
          opacity: curved,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Transform.scale(scale: scale, child: c),
          ),
        );
      },
      child: child,
    );
  }
}

// ==========================================
// 🆕 💥 FLASH — белая вспышка в начале (концертный стиль)
// ==========================================
class _FlashTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _FlashTransition({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, c) {
        final t = animation.value.clamp(0.0, 1.0);
        final flash = t < 0.35 ? 1.0 - (t / 0.35) : 0.0;
        return Stack(
          children: [
            Opacity(
              opacity: (t / 0.25).clamp(0.0, 1.0),
              child: c,
            ),
            if (flash > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.white.withOpacity(flash * 0.9),
                  ),
                ),
              ),
          ],
        );
      },
      child: child,
    );
  }
}

// ==========================================
// 🆕 ⭕ CIRCLE REVEAL — раскрытие кадра кругом из центра
// ==========================================
class _CircleRevealTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _CircleRevealTransition({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, c) {
        final t = animation.value.clamp(0.0, 1.0);
        final curved = Curves.easeOut.transform(t);
        return ClipPath(
          clipper: _CircleClipper(curved),
          child: c,
        );
      },
      child: child,
    );
  }
}

class _CircleClipper extends CustomClipper<Path> {
  final double progress;
  _CircleClipper(this.progress);

  @override
  Path getClip(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.sqrt(size.width * size.width + size.height * size.height) / 2;
    final radius = maxRadius * progress;
    return Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  @override
  bool shouldReclip(_CircleClipper oldClipper) =>
      oldClipper.progress != progress;
}

// ==========================================
// 🆕  SPIN BLUR — поворот с размытием и зумом
// ==========================================
class _SpinBlurTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _SpinBlurTransition({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, c) {
        final t = animation.value.clamp(0.0, 1.0);
        final curved = Curves.easeOut.transform(t);
        final angle = (1.0 - curved) * 0.6; // ~34°
        final blur = (1.0 - curved) * 10.0;
        final scale = 0.75 + 0.25 * curved;
        return Opacity(
          opacity: curved,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Transform.rotate(
              angle: angle,
              child: Transform.scale(scale: scale, child: c),
            ),
          ),
        );
      },
      child: child,
    );
  }
}

// ==========================================
// 🆕 🌈 RGB SPLIT — хроматическое расщепление + джиттер полос
// ==========================================
class _RgbSplitTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _RgbSplitTransition({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, c) {
        final t = animation.value.clamp(0.0, 1.0);
        if (t >= 0.6) return c!;

        final k = 1.0 - t / 0.6;
        final off = k * 14.0;

        return Stack(
          children: [
            // Красный канал
            Transform.translate(
              offset: Offset(off, -off * 0.3),
              child: Opacity(
                opacity: 0.6,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                      Color(0xFFFF0000), BlendMode.srcATop),
                  child: c,
                ),
              ),
            ),
            // Зелёный канал
            Transform.translate(
              offset: Offset(-off, off * 0.3),
              child: Opacity(
                opacity: 0.6,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                      Color(0xFF00FF00), BlendMode.srcATop),
                  child: c,
                ),
              ),
            ),
            // Синий канал
            Transform.translate(
              offset: Offset(off * 0.5, off * 0.5),
              child: Opacity(
                opacity: 0.5,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                      Color(0xFF0000FF), BlendMode.srcATop),
                  child: c,
                ),
              ),
            ),
            // Горизонтальная полоса-джиттер
            ClipRect(
              clipper: _BandClipper(0.35 + 0.1 * math.sin(t * 40), 0.12),
              child: Transform.translate(
                offset: Offset(-off * 1.5, 0),
                child: c,
              ),
            ),
            // Основной слой
            Opacity(opacity: (t / 0.6).clamp(0.0, 1.0), child: c!),
          ],
        );
      },
      child: child,
    );
  }
}

class _BandClipper extends CustomClipper<Rect> {
  final double centerY; // 0..1
  final double height; // доля высоты
  _BandClipper(this.centerY, this.height);

  @override
  Rect getClip(Size size) {
    final top = size.height * (centerY - height / 2);
    return Rect.fromLTWH(0, top, size.width, size.height * height);
  }

  @override
  bool shouldReclip(_BandClipper oldClipper) =>
      oldClipper.centerY != centerY || oldClipper.height != height;
}