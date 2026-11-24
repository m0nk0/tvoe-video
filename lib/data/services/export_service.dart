import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';

import '../../core/utils/live_motion.dart';
import '../../core/utils/overlay_render.dart';
import '../../core/utils/photo_fit.dart';
import '../models/photo_layer.dart';
import '../models/text_layer.dart';
import '../models/video_project.dart';
import '../models/video_format.dart';

/// Результат экспорта
class ExportResult {
  final String videoPath;
  final bool hasAudio;
  final String? warning;

  ExportResult({
    required this.videoPath,
    this.hasAudio = false,
    this.warning,
  });
}

// ==========================================
// ✅ Hardening: пресеты качества экспорта
// ==========================================
enum ExportQuality { low, medium, high }

extension ExportQualityX on ExportQuality {
  double get multiplier {
    switch (this) {
      case ExportQuality.low:
        return 0.6;
      case ExportQuality.medium:
        return 1.0;
      case ExportQuality.high:
        return 1.6;
    }
  }

  String get label {
    switch (this) {
      case ExportQuality.low:
        return 'Эконом';
      case ExportQuality.medium:
        return 'Стандарт';
      case ExportQuality.high:
        return 'Высокое';
    }
  }
}

/// Сервис экспорта проекта в MP4 видео / GIF / PNG-обложку.
/// Видео кодируется нативным Android MediaCodec, звук — MediaExtractor + AAC + MediaMuxer.
/// Никаких сторонних плагинов для рендера.
class ExportService {
  static const int _defaultFps = 30;

  /// Канал нативного экспортёра (MainActivity.kt / VideoEncoder.kt / AudioMuxer.kt / GifEncoder.kt)
  static const MethodChannel _channel =
      MethodChannel('com.tvoymagazine.tvoe_video/exporter');

  /// Последняя ошибка — чтобы UI показал реальную причину, а не «отменён»
  static String? lastError;

  /// Кэш декодированных фото. Рендер идёт последовательно, поэтому 3 хватает.
  static final Map<String, ui.Image> _imageCache = {};
  static const int _maxCachedImages = 3;

  // ✅ Hardening: битрейт зависит от fps и пресета качества
  static int _bitrateFor(int width, int height, int fps, ExportQuality quality) {
    final b = (width * height * fps * 0.12 * quality.multiplier).round();
    return b.clamp(1500000, 20000000);
  }

  static void _clearImageCache() {
    for (final img in _imageCache.values) {
      try {
        img.dispose();
      } catch (_) {}
    }
    _imageCache.clear();
  }

  static Future<ui.Image?> _loadImage(String path) async {
    final cached = _imageCache[path];
    if (cached != null) return cached;

    final file = File(path);
    if (!file.existsSync()) return null;

    final bytes = await file.readAsBytes();
    final image = await decodeImageFromList(bytes);

    _imageCache[path] = image;
    while (_imageCache.length > _maxCachedImages) {
      final oldestKey = _imageCache.keys.first;
      final oldest = _imageCache.remove(oldestKey);
      try {
        oldest?.dispose();
      } catch (_) {}
    }
    return image;
  }

  static String _sanitizeFileName(String name) {
    var clean = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) clean = 'Мой клип';
    if (clean.length > 100) clean = clean.substring(0, 100);
    clean = clean.replaceAll(RegExp(r'\.+$'), '');
    return clean.isEmpty ? 'Мой клип' : clean;
  }

  static bool _moveFile(String from, String to) {
    try {
      final src = File(from);
      if (!src.existsSync()) return false;
      try {
        src.renameSync(to);
      } catch (_) {
        src.copySync(to);
        try {
          src.deleteSync();
        } catch (_) {}
      }
      final dst = File(to);
      return dst.existsSync() && dst.lengthSync() > 1024;
    } catch (e) {
      print('❌ Не удалось переместить видео: $e');
      return false;
    }
  }

  // ==========================================
  // ✅ Экспорт MP4: качество + fps настраиваемые
  // ==========================================
  static Future<ExportResult?> exportVideo({
    required VideoProject project,
    VideoFormat? format,
    String? outputFileName,
    Function(double)? onProgress,
    bool Function()? cancelChecker,
    ExportQuality quality = ExportQuality.medium,
    int fps = 30,
  }) async {
    lastError = null;

    if (project.photos.isEmpty) {
      lastError = 'В проекте нет кадров';
      return null;
    }

    final fmt = format ?? project.format;
    final width = fmt.width;
    final height = fmt.height;

    final appDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final baseName = (outputFileName != null && outputFileName.trim().isNotEmpty)
        ? _sanitizeFileName(outputFileName.trim())
        : 'tvoe_video_$timestamp';

    final silentVideoPath = '${appDir.path}/temp_silent_$timestamp.mp4';
    final finalVideoPath = '${appDir.path}/$baseName.mp4';

    try {
      final silentResult = await _renderSilentVideo(
        project: project,
        width: width,
        height: height,
        outputPath: silentVideoPath,
        onProgress: (p) => onProgress?.call(p * 0.8),
        cancelChecker: cancelChecker,
        fps: fps,
        quality: quality,
      );

      if (silentResult == null) {
        lastError ??= 'Экспорт отменён';
        _cleanup([silentVideoPath]);
        return null;
      }

      if (project.audioTrack != null) {
        onProgress?.call(0.85);
        final mixed = await _mixWithAudio(
          videoPath: silentVideoPath,
          audioPath: project.audioTrack!.filePath,
          outputPath: finalVideoPath,
          volume: project.audioTrack!.volume,
          startTime: project.audioTrack!.startTime,
          totalDurationMs: project.totalDurationMs,
        );
        onProgress?.call(1.0);

        if (mixed) {
          _cleanup([silentVideoPath]);
          return ExportResult(videoPath: finalVideoPath, hasAudio: true);
        }

        if (!_moveFile(silentVideoPath, finalVideoPath)) {
          lastError = 'Не удалось подготовить файл видео';
          _cleanup([silentVideoPath, finalVideoPath]);
          return null;
        }
        return ExportResult(
          videoPath: finalVideoPath,
          hasAudio: false,
          warning: 'Не удалось добавить музыку. Видео сохранено без звука.',
        );
      } else {
        onProgress?.call(1.0);
        if (!_moveFile(silentVideoPath, finalVideoPath)) {
          lastError = 'Не удалось подготовить файл видео';
          _cleanup([silentVideoPath, finalVideoPath]);
          return null;
        }
        return ExportResult(videoPath: finalVideoPath, hasAudio: false);
      }
    } catch (e) {
      print('Ошибка экспорта видео: $e');
      lastError = 'Ошибка экспорта: $e';
      _cleanup([silentVideoPath, finalVideoPath]);
      return null;
    } finally {
      _clearImageCache();
    }
  }

  // ==========================================
  // ✅ ШАГ 1: нативный рендер видео
  // Flutter Canvas → RGBA → MediaCodec H.264
  // ==========================================
  static Future<String?> _renderSilentVideo({
    required VideoProject project,
    required int width,
    required int height,
    required String outputPath,
    required Function(double) onProgress,
    bool Function()? cancelChecker,
    required int fps,
    required ExportQuality quality,
  }) async {
    int totalFrames = 0;
    for (final photo in project.photos) {
      totalFrames += (fps * photo.durationMilliseconds / 1000).ceil();
    }
    if (totalFrames <= 0) {
      lastError = 'Нулевая длительность проекта';
      return null;
    }

    bool started = false;
    try {
      await _channel.invokeMethod('start', {
        'width': width,
        'height': height,
        'fps': fps,
        'bitrate': _bitrateFor(width, height, fps, quality),
        'path': outputPath,
      });
      started = true;

      int renderedFrames = 0;

      for (int segIndex = 0; segIndex < project.photos.length; segIndex++) {
        final photo = project.photos[segIndex];
        final framesForSegment =
            (fps * photo.durationMilliseconds / 1000).ceil();
        if (framesForSegment <= 0) continue;

        for (int frameIndex = 0; frameIndex < framesForSegment; frameIndex++) {
          if (cancelChecker != null && cancelChecker()) {
            try {
              await _channel.invokeMethod('cancel');
            } catch (_) {}
            _cleanup([outputPath]);
            lastError = 'Экспорт отменён';
            return null;
          }

          final frameProgress = frameIndex / framesForSegment;

          final rgbaBytes = await _renderFrame(
            project: project,
            currentSegmentIndex: segIndex,
            frameProgress: frameProgress,
            width: width,
            height: height,
          );

          if (rgbaBytes == null) {
            throw Exception('Не удалось отрисовать кадр $renderedFrames');
          }

          await _channel.invokeMethod('feedFrame', rgbaBytes);

          renderedFrames++;
          onProgress(renderedFrames / totalFrames);
        }
      }

      await _channel.invokeMethod('finish');

      final file = File(outputPath);
      if (!file.existsSync() || file.lengthSync() < 1024) {
        lastError = 'Энкодер не создал файл видео';
        _cleanup([outputPath]);
        return null;
      }

      print('✅ Нативный рендер завершён: $renderedFrames кадров @${fps}fps '
          '(${quality.label}), '
          '${(file.lengthSync() / 1024 / 1024).toStringAsFixed(2)} МБ');
      return outputPath;
    } catch (e) {
      print('❌ Ошибка нативного рендера: $e');
      lastError = 'Ошибка кодирования видео: $e';
      if (started) {
        try {
          await _channel.invokeMethod('cancel');
        } catch (_) {}
      }
      _cleanup([outputPath]);
      return null;
    }
  }

  // ==========================================
  // ✅ ШАГ 2: нативное микширование звука
  // MP3 → PCM (громкость/задержка/фейд/обрезка) → AAC → MediaMuxer
  // ==========================================
  static Future<bool> _mixWithAudio({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    required double volume,
    required double startTime,
    required int totalDurationMs,
  }) async {
    try {
      final audioFile = File(audioPath);
      if (!audioFile.existsSync()) {
        print('⚠️ Аудиофайл не найден: $audioPath');
        return false;
      }
      if (totalDurationMs <= 0) return false;

      await _channel.invokeMethod('muxAudio', {
        'videoPath': videoPath,
        'audioPath': audioPath,
        'outputPath': outputPath,
        'volume': volume.clamp(0.0, 1.0),
        'startTime': startTime.clamp(0.0, totalDurationMs / 1000.0),
        'durationMs': totalDurationMs,
      });

      final out = File(outputPath);
      if (!out.existsSync() || out.lengthSync() < 1024) {
        print('⚠️ Муксер не создал файл со звуком');
        _cleanup([outputPath]);
        return false;
      }

      print('✅ Звук добавлен: '
          '${(out.lengthSync() / 1024 / 1024).toStringAsFixed(2)} МБ');
      return true;
    } catch (e) {
      print('❌ Ошибка микширования звука: $e');
      _cleanup([outputPath]);
      return false;
    }
  }

  static Future<Uint8List?> _renderFrame({
    required VideoProject project,
    required int currentSegmentIndex,
    required double frameProgress,
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
        recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.black,
    );

    await _paintPhotoWithTransition(
      canvas,
      project,
      currentSegmentIndex,
      frameProgress,
      width: width,
      height: height,
    );

    _paintTexts(
      canvas,
      project,
      currentSegmentIndex,
      frameProgress,
      width: width,
      height: height,
    );

    if (project.overlayType != OverlayType.none) {
      final segmentStartMs = project.photos
          .take(currentSegmentIndex)
          .fold<int>(0, (sum, photo) => sum + photo.durationMilliseconds);
      final elapsedMs = segmentStartMs +
          (frameProgress *
                  project.photos[currentSegmentIndex].durationMilliseconds)
              .toInt();

      paintOverlay(
        canvas,
        project.overlayType,
        elapsedMs,
        width,
        height,
        project.overlayIntensity,
      );
    }

    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(width, height);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return byteData?.buffer.asUint8List();
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }

  static Future<void> _paintPhotoWithTransition(
    Canvas canvas,
    VideoProject project,
    int currentSegmentIndex,
    double frameProgress, {
    required int width,
    required int height,
  }) async {
    final currentPhoto = project.photos[currentSegmentIndex];

    // ✅ Кэш вместо декодирования JPEG на каждый кадр
    final uiImage = await _loadImage(currentPhoto.imagePath);
    if (uiImage == null) return;

    final imgWidth = uiImage.width.toDouble();
    final imgHeight = uiImage.height.toDouble();
    final srcRect = Rect.fromLTWH(0, 0, imgWidth, imgHeight);
    final fullRect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final imageSize = Size(imgWidth, imgHeight);
    final canvasSize = Size(width.toDouble(), height.toDouble());

    final dst = PhotoFitCalculator.dstRect(
      image: imageSize,
      canvas: canvasSize,
      fitMode: currentPhoto.fitMode,
      scale: currentPhoto.scale,
      offsetX: currentPhoto.offsetX,
      offsetY: currentPhoto.offsetY,
    );

    // 🎬 Ken Burns + Cinematic с интенсивностью
    final elapsedMsForMotion = frameProgress * currentPhoto.durationMilliseconds;
    final motionT = currentPhoto.durationMilliseconds > 0
        ? (elapsedMsForMotion / currentPhoto.durationMilliseconds).clamp(0.0, 1.0)
        : 1.0;

    final cinematicResult = applyLiveMotionWithCinematic(
      dst,
      currentPhoto.liveMotion,
      motionT,
      intensity: project.cinematicIntensity,
    );
    final liveDst = cinematicResult.rect;

    final colorFilter =
        ColorFilter.matrix(FilterPresets.matrix(currentPhoto.filter));

    final elapsedMs = frameProgress * currentPhoto.durationMilliseconds;
    final rawT = currentPhoto.entranceDurationMs > 0
        ? (elapsedMs / currentPhoto.entranceDurationMs).clamp(0.0, 1.0)
        : 1.0;
    final entranceT = Curves.easeOut.transform(rawT);

    final transitionMs =
        currentPhoto.transitionDurationMs.clamp(300, 1500).toDouble();
    final tp = currentPhoto.durationMilliseconds > 0
        ? (elapsedMs / transitionMs).clamp(0.0, 1.0)
        : 1.0;

    double entranceOpacity = 1.0;

    canvas.save();

    switch (currentPhoto.entranceAnimation) {
      case EntranceAnimation.none:
        break;
      case EntranceAnimation.fadeIn:
        entranceOpacity *= entranceT;
        break;
      case EntranceAnimation.slideFromLeft:
        canvas.translate(-100 * (1 - entranceT), 0);
        entranceOpacity *= entranceT;
        break;
      case EntranceAnimation.slideFromRight:
        canvas.translate(100 * (1 - entranceT), 0);
        entranceOpacity *= entranceT;
        break;
      case EntranceAnimation.slideFromTop:
        canvas.translate(0, -100 * (1 - entranceT));
        entranceOpacity *= entranceT;
        break;
      case EntranceAnimation.slideFromBottom:
        canvas.translate(0, 100 * (1 - entranceT));
        entranceOpacity *= entranceT;
        break;
      case EntranceAnimation.zoomIn:
        _scaleAroundCenter(canvas, width, height, 0.5 + 0.5 * entranceT);
        entranceOpacity *= entranceT;
        break;
      case EntranceAnimation.rotateIn:
        _rotateAroundCenter(canvas, width, height, (1 - entranceT) * 0.5);
        entranceOpacity *= entranceT;
        break;
    }

    Paint photoPaint(double extraOpacity) {
      return Paint()
        ..colorFilter = colorFilter
        ..color = Colors.white
            .withOpacity((entranceOpacity * extraOpacity).clamp(0.0, 1.0));
    }

    if (currentPhoto.fitMode == FitMode.contain) {
      if (currentPhoto.backgroundType == BackgroundType.blur) {
        final sigma = (0.06 * width).clamp(24.0, 90.0);
        final bgScale =
            PhotoFitCalculator.coverScale(image: imageSize, canvas: canvasSize);
        final bgRect = Rect.fromCenter(
          center: Offset(width / 2, height / 2),
          width: imgWidth * bgScale,
          height: imgHeight * bgScale,
        );
        canvas.save();
        canvas.clipRect(fullRect);
        canvas.drawImageRect(
          uiImage,
          srcRect,
          bgRect,
          Paint()
            ..colorFilter = colorFilter
            ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)
            ..color = Colors.white.withOpacity(entranceOpacity),
        );
        canvas.drawRect(fullRect,
            Paint()..color = Colors.black.withOpacity(0.25 * entranceOpacity));
        canvas.restore();
      } else {
        canvas.drawRect(
          fullRect,
          Paint()
            ..colorFilter = colorFilter
            ..color =
                Color(currentPhoto.backgroundColor).withOpacity(entranceOpacity),
        );
      }
    }

    // ==========================================
    // Переход (фото рисуется в liveDst с учётом Ken Burns + Cinematic)
    // ==========================================
    switch (currentPhoto.transition) {
      case TransitionType.none:
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(1.0));
        break;

      case TransitionType.fade:
      case TransitionType.blur:
      case TransitionType.dissolve:
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(1.0));
        final fadeAlpha = (1.0 - tp).clamp(0.0, 1.0);
        if (fadeAlpha > 0) {
          canvas.drawRect(
              fullRect, Paint()..color = Colors.black.withOpacity(fadeAlpha));
        }
        break;

      case TransitionType.slideLeft:
        final offsetLeft = ui.lerpDouble(width.toDouble(), 0.0, tp) ?? 0.0;
        canvas.translate(offsetLeft, 0);
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(1.0));
        break;

      case TransitionType.slideRight:
        final offsetRight = ui.lerpDouble(-width.toDouble(), 0.0, tp) ?? 0.0;
        canvas.translate(offsetRight, 0);
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(1.0));
        break;

      case TransitionType.zoomIn:
        final scaleIn = ui.lerpDouble(0.8, 1.0, tp) ?? 1.0;
        _scaleAroundCenter(canvas, width, height, scaleIn);
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(1.0));
        break;

      case TransitionType.zoomOut:
        final scaleOut = ui.lerpDouble(1.2, 1.0, tp) ?? 1.0;
        _scaleAroundCenter(canvas, width, height, scaleOut);
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(1.0));
        break;

      case TransitionType.rotate:
        _rotateAroundCenter(canvas, width, height, (1 - tp) * 1.5708);
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(tp));
        break;

      case TransitionType.flip:
        final scaleX = tp < 0.5 ? -1.0 + 2 * tp : 1.0;
        canvas.translate(width / 2, height / 2);
        canvas.scale(scaleX, 1.0);
        canvas.translate(-width / 2, -height / 2);
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(tp));
        break;

      case TransitionType.wipe:
        canvas.clipRect(
            Rect.fromLTWH(0, 0, width.toDouble() * tp, height.toDouble()));
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(1.0));
        break;

      case TransitionType.glitch:
        if (tp < 0.5) {
          final o = (1.0 - tp * 2) * 10.0;
          canvas.save();
          canvas.translate(o, 0);
          canvas.drawImageRect(
              uiImage,
              srcRect,
              liveDst,
              Paint()
                ..colorFilter = const ColorFilter.mode(
                    Color(0xFFFF0000), BlendMode.srcATop)
                ..color = Colors.white.withOpacity(0.7));
          canvas.restore();
          canvas.save();
          canvas.translate(-o, 0);
          canvas.drawImageRect(
              uiImage,
              srcRect,
              liveDst,
              Paint()
                ..colorFilter = const ColorFilter.mode(
                    Color(0xFF00FF00), BlendMode.srcATop)
                ..color = Colors.white.withOpacity(0.7));
          canvas.restore();
        }
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(1.0));
        break;

      case TransitionType.whipPan:
        final wpPos = _easeInOutCubic(tp);
        final wpBlur = math.sin(math.pi * tp) * (width * 0.02);
        canvas.translate(width * (1 - wpPos), 0);
        canvas.drawImageRect(
            uiImage,
            srcRect,
            liveDst,
            photoPaint(1.0)
              ..imageFilter =
                  ui.ImageFilter.blur(sigmaX: wpBlur, sigmaY: wpBlur * 0.25));
        break;

      case TransitionType.crossZoom:
        final cz = _easeInOutCubic(tp);
        final czScale = 1.8 - 0.8 * cz;
        final czBlur = (1.0 - cz) * (width * 0.01);
        _scaleAroundCenter(canvas, width, height, czScale);
        canvas.drawImageRect(
            uiImage,
            srcRect,
            liveDst,
            photoPaint(cz)
              ..imageFilter = ui.ImageFilter.blur(sigmaX: czBlur, sigmaY: czBlur));
        break;

      case TransitionType.flash:
        canvas.drawImageRect(uiImage, srcRect, liveDst,
            photoPaint((tp / 0.25).clamp(0.0, 1.0)));
        final fl = tp < 0.35 ? 1.0 - (tp / 0.35) : 0.0;
        if (fl > 0) {
          canvas.drawRect(
              fullRect, Paint()..color = Colors.white.withOpacity(fl * 0.9));
        }
        break;

      case TransitionType.circleReveal:
        final cr = _easeOut(tp);
        final maxR =
            math.sqrt(width.toDouble() * width + height.toDouble() * height) / 2;
        canvas.save();
        canvas.clipPath(Path()
          ..addOval(Rect.fromCircle(
              center: Offset(width / 2, height / 2), radius: maxR * cr)));
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(1.0));
        canvas.restore();
        break;

      case TransitionType.spinBlur:
        final sb = _easeOut(tp);
        final sbBlur = (1.0 - sb) * (width * 0.012);
        _rotateAroundCenter(canvas, width, height, (1 - sb) * 0.6);
        _scaleAroundCenter(canvas, width, height, 0.75 + 0.25 * sb);
        canvas.drawImageRect(
            uiImage,
            srcRect,
            liveDst,
            photoPaint(sb)
              ..imageFilter = ui.ImageFilter.blur(sigmaX: sbBlur, sigmaY: sbBlur));
        break;

      case TransitionType.rgbSplit:
        if (tp < 0.6) {
          final k = 1.0 - tp / 0.6;
          final o = k * (width * 0.013);
          canvas.save();
          canvas.translate(o, -o * 0.3);
          canvas.drawImageRect(
              uiImage,
              srcRect,
              liveDst,
              Paint()
                ..colorFilter = const ColorFilter.mode(
                    Color(0xFFFF0000), BlendMode.srcATop)
                ..color = Colors.white.withOpacity(0.6));
          canvas.restore();
          canvas.save();
          canvas.translate(-o, o * 0.3);
          canvas.drawImageRect(
              uiImage,
              srcRect,
              liveDst,
              Paint()
                ..colorFilter = const ColorFilter.mode(
                    Color(0xFF00FF00), BlendMode.srcATop)
                ..color = Colors.white.withOpacity(0.6));
          canvas.restore();
          canvas.save();
          canvas.translate(o * 0.5, o * 0.5);
          canvas.drawImageRect(
              uiImage,
              srcRect,
              liveDst,
              Paint()
                ..colorFilter = const ColorFilter.mode(
                    Color(0xFF0000FF), BlendMode.srcATop)
                ..color = Colors.white.withOpacity(0.5));
          canvas.restore();
          canvas.save();
          final bandTop = height * (0.35 + 0.1 * math.sin(tp * 40) - 0.06);
          canvas.clipRect(
              Rect.fromLTWH(0, bandTop, width.toDouble(), height * 0.12));
          canvas.translate(-o * 1.5, 0);
          canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(1.0));
          canvas.restore();
        }
        canvas.drawImageRect(uiImage, srcRect, liveDst,
            photoPaint((tp / 0.6).clamp(0.0, 1.0)));
        break;
    }

    canvas.restore();
  }

  static void _scaleAroundCenter(
      Canvas canvas, int width, int height, double scale) {
    canvas.translate(width / 2, height / 2);
    canvas.scale(scale, scale);
    canvas.translate(-width / 2, -height / 2);
  }

  static void _rotateAroundCenter(
      Canvas canvas, int width, int height, double radians) {
    canvas.translate(width / 2, height / 2);
    canvas.rotate(radians);
    canvas.translate(-width / 2, -height / 2);
  }

  static double _easeInOutCubic(double t) {
    return t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;
  }

  static double _easeOut(double t) {
    return 1 - math.pow(1 - t, 3).toDouble();
  }

  static void _paintTexts(
    Canvas canvas,
    VideoProject project,
    int currentSegmentIndex,
    double frameProgress, {
    required int width,
    required int height,
  }) {
    final currentSegmentStartMs = project.photos
        .take(currentSegmentIndex)
        .fold<int>(0, (sum, photo) => sum + photo.durationMilliseconds);

    final currentTimeMs = currentSegmentStartMs +
        (frameProgress *
                project.photos[currentSegmentIndex].durationMilliseconds)
            .toInt();

    for (final text in project.texts) {
      if (currentTimeMs >= text.startTimeMilliseconds &&
          currentTimeMs <= text.endTimeMilliseconds) {
        _paintText(
          canvas,
          text,
          currentTimeMs - text.startTimeMilliseconds,
          text.endTimeMilliseconds - text.startTimeMilliseconds,
          width: width,
          height: height,
        );
      }
    }
  }

  static void _paintText(
    Canvas canvas,
    TextLayer text,
    int currentTimeMs,
    int totalDurationMs, {
    required int width,
    required int height,
  }) {
    final progress = totalDurationMs > 0 ? currentTimeMs / totalDurationMs : 1.0;

    final textStyle = TextStyle(
      color: Color(text.colorValue),
      fontSize: text.fontSize.toDouble(),
      fontWeight:
          text.fontFamily == 'Unbounded' ? FontWeight.w800 : FontWeight.w600,
      shadows: [
        Shadow(
          color: Colors.black.withOpacity(0.7),
          blurRadius: 4,
          offset: const Offset(2, 2),
        ),
      ],
    );

    final textPainter = TextPainter(
      text: TextSpan(text: text.text, style: textStyle),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout(maxWidth: width.toDouble() * 0.8);

    double x = text.positionX * width - textPainter.width / 2;
    double y = text.positionY * height - textPainter.height / 2;

    switch (text.animation) {
      case AnimationType.fadeIn:
        textPainter.paint(canvas, Offset(x, y));
        break;
      case AnimationType.slideUp:
        final offset =
            ui.lerpDouble(50.0, 0.0, progress.clamp(0.0, 0.2) / 0.2) ?? 0.0;
        textPainter.paint(canvas, Offset(x, y + offset));
        break;
      case AnimationType.slideDown:
        final offset =
            ui.lerpDouble(-50.0, 0.0, progress.clamp(0.0, 0.2) / 0.2) ?? 0.0;
        textPainter.paint(canvas, Offset(x, y + offset));
        break;
      case AnimationType.typewriter:
        final charCount =
            (text.text.length * progress.clamp(0.0, 0.5) / 0.5).round();
        final visibleText =
            text.text.substring(0, charCount.clamp(0, text.text.length));
        final visiblePainter = TextPainter(
          text: TextSpan(text: visibleText, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        visiblePainter.layout(maxWidth: width.toDouble() * 0.8);
        visiblePainter.paint(canvas, Offset(x, y));
        break;
      case AnimationType.none:
        textPainter.paint(canvas, Offset(x, y));
        break;
    }
  }

  // ==========================================
  // ✅ GIF-экспорт: ВЕСЬ клип сжимается в ≤10 с (ускорение),
  //    все кадры входят в GIF, ничего не обрезается
  // ==========================================
  static Future<String?> exportGif({
    required VideoProject project,
    VideoFormat? format,
    String? outputFileName,
    Function(double)? onProgress,
    bool Function()? cancelChecker,
  }) async {
    lastError = null;
    if (project.photos.isEmpty) {
      lastError = 'В проекте нет кадров';
      return null;
    }

    final fmt = format ?? project.format;
    const int gifW = 480;
    final int gifH = (gifW * fmt.height / fmt.width).round();
    const int fps = 10;
    const int maxSec = 10;

    final appDir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final base = (outputFileName != null && outputFileName.trim().isNotEmpty)
        ? _sanitizeFileName(outputFileName.trim())
        : 'tvoe_gif_$ts';
    final path = '${appDir.path}/$base.gif';

    // ✅ Весь проект сжимается в maxSec: шаг = totalMs / totalFrames
    final double totalMs = project.totalDurationMs.toDouble();
    final double targetMs = math.min(totalMs, maxSec * 1000.0);
    final int totalFrames = (targetMs / 1000 * fps).ceil();
    if (totalFrames <= 0) {
      lastError = 'Нулевая длительность проекта';
      return null;
    }
    final double msPerFrame = totalMs / totalFrames;

    print('🎞 GIF-план: totalMs=${totalMs.toStringAsFixed(0)}, '
        'targetMs=${targetMs.toStringAsFixed(0)}, кадров=$totalFrames, '
        'шаг=${msPerFrame.toStringAsFixed(0)}мс, '
        'ускорение=×${(totalMs / targetMs).toStringAsFixed(2)}');

    bool started = false;
    try {
      await _channel.invokeMethod('gifStart', {
        'width': gifW,
        'height': gifH,
        'fps': fps,
        'path': path,
      });
      started = true;

      int rendered = 0;
      int lastLoggedSeg = -1;
      for (int f = 0; f < totalFrames; f++) {
        if (cancelChecker != null && cancelChecker()) {
          try {
            await _channel.invokeMethod('gifCancel');
          } catch (_) {}
          _cleanup([path]);
          lastError = 'Экспорт отменён';
          return null;
        }
        final double tMs = f * msPerFrame;

        int acc = 0;
        int seg = 0;
        double local = 0;
        for (int i = 0; i < project.photos.length; i++) {
          final d = project.photos[i].durationMilliseconds;
          if (tMs < acc + d || i == project.photos.length - 1) {
            seg = i;
            local = d > 0 ? ((tMs - acc) / d).clamp(0.0, 1.0) : 0.0;
            break;
          }
          acc += d;
        }

        // ✅ Диагностика: логируем смену сегмента
        if (seg != lastLoggedSeg) {
          print('🎞 GIF: кадр $f → сегмент $seg (t=${tMs.toStringAsFixed(0)}мс)');
          lastLoggedSeg = seg;
        }

        final rgba = await _renderFrame(
          project: project,
          currentSegmentIndex: seg,
          frameProgress: local,
          width: gifW,
          height: gifH,
        );
        if (rgba == null) throw Exception('Не удалось отрисовать кадр $f');
        await _channel.invokeMethod('gifFrame', rgba);
        rendered++;
        onProgress?.call(rendered / totalFrames);
      }

      await _channel.invokeMethod('gifFinish');
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() < 100) {
        lastError = 'GIF не создан';
        _cleanup([path]);
        return null;
      }
      print('✅ GIF: $rendered кадров (ускорение ×${(totalMs / targetMs).toStringAsFixed(2)}), '
          '${(file.lengthSync() / 1024 / 1024).toStringAsFixed(2)} МБ');
      return path;
    } catch (e) {
      print('❌ Ошибка GIF: $e');
      lastError = 'Ошибка GIF: $e';
      if (started) {
        try {
          await _channel.invokeMethod('gifCancel');
        } catch (_) {}
      }
      _cleanup([path]);
      return null;
    } finally {
      _clearImageCache();
    }
  }

  // ==========================================
  // ✅ Cover: рендер одного кадра в PNG (превью для галереи/шеринга)
  // ==========================================
  static Future<String?> exportCover({
    required VideoProject project,
    required int photoIndex,
    VideoFormat? format,
    String? outputFileName,
  }) async {
    lastError = null;
    if (project.photos.isEmpty) {
      lastError = 'В проекте нет кадров';
      return null;
    }
    final idx = photoIndex.clamp(0, project.photos.length - 1);
    final fmt = format ?? project.format;

    final appDir = await getApplicationDocumentsDirectory();
    final base = (outputFileName != null && outputFileName.trim().isNotEmpty)
        ? _sanitizeFileName(outputFileName.trim())
        : 'tvoe_cover_${DateTime.now().millisecondsSinceEpoch}';
    final path = '${appDir.path}/${base}_cover.png';

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
          recorder, Rect.fromLTWH(0, 0, fmt.width.toDouble(), fmt.height.toDouble()));
      canvas.drawRect(
        Rect.fromLTWH(0, 0, fmt.width.toDouble(), fmt.height.toDouble()),
        Paint()..color = Colors.black,
      );
      // кадр на середине движения: Ken Burns/Cinematic в лучшей фазе
      await _paintPhotoWithTransition(
        canvas,
        project,
        idx,
        0.5,
        width: fmt.width,
        height: fmt.height,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(fmt.width, fmt.height);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      if (data == null) {
        lastError = 'Не удалось отрисовать обложку';
        return null;
      }
      final file = File(path);
      await file.writeAsBytes(data.buffer.asUint8List());
      print('✅ Обложка: $path (${(file.lengthSync() / 1024).round()} КБ)');
      return path;
    } catch (e) {
      print('❌ Ошибка обложки: $e');
      lastError = 'Ошибка обложки: $e';
      return null;
    }
  }

  static Future<bool> saveToGallery(String videoPath) async {
    try {
      await Gal.putVideo(videoPath);
      return true;
    } catch (e) {
      print('Ошибка сохранения в галерею: $e');
      return false;
    }
  }

  static void _cleanup(List<String> paths) {
    for (final p in paths) {
      try {
        final f = File(p);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }
}