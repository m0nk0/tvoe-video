import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
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

/// Сервис экспорта проекта в MP4 видео
class ExportService {
  static const int _defaultFps = 30;
  static const int _defaultBitrate = 5000000; // 5 Mbps

  static String _sanitizeFileName(String name) {
    var clean = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) clean = 'Мой клип';
    if (clean.length > 100) clean = clean.substring(0, 100);
    clean = clean.replaceAll(RegExp(r'\.+$'), '');
    return clean.isEmpty ? 'Мой клип' : clean;
  }

  static Future<ExportResult?> exportVideo({
    required VideoProject project,
    VideoFormat? format,
    String? outputFileName,
    Function(double)? onProgress,
    bool Function()? cancelChecker,
  }) async {
    if (project.photos.isEmpty) return null;

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
      );

      if (silentResult == null) return null;

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

        try {
          final silentFile = File(silentVideoPath);
          if (silentFile.existsSync()) silentFile.deleteSync();
        } catch (_) {}

        if (mixed) {
          return ExportResult(videoPath: finalVideoPath, hasAudio: true);
        } else {
          try {
            final silentFile = File(silentVideoPath);
            if (silentFile.existsSync()) silentFile.renameSync(finalVideoPath);
          } catch (_) {}
          return ExportResult(
            videoPath: finalVideoPath,
            hasAudio: false,
            warning: 'Не удалось добавить музыку. Видео сохранено без звука.',
          );
        }
      } else {
        onProgress?.call(1.0);
        try {
          final silentFile = File(silentVideoPath);
          if (silentFile.existsSync()) silentFile.renameSync(finalVideoPath);
        } catch (_) {}
        return ExportResult(videoPath: finalVideoPath, hasAudio: false);
      }
    } catch (e) {
      print('Ошибка экспорта видео: $e');
      _cleanup([silentVideoPath, finalVideoPath]);
      return null;
    }
  }

  static Future<String?> _renderSilentVideo({
    required VideoProject project,
    required int width,
    required int height,
    required String outputPath,
    required Function(double) onProgress,
    bool Function()? cancelChecker,
  }) async {
    try {
      await FlutterQuickVideoEncoder.setup(
        width: width,
        height: height,
        fps: _defaultFps,
        videoBitrate: _defaultBitrate,
        profileLevel: ProfileLevel.any,
        audioBitrate: 0,
        audioChannels: 0,
        sampleRate: 0,
        filepath: outputPath,
      );

      int totalFrames = 0;
      for (final photo in project.photos) {
        totalFrames += (_defaultFps * photo.durationMilliseconds / 1000).ceil();
      }

      int renderedFrames = 0;

      for (int segIndex = 0; segIndex < project.photos.length; segIndex++) {
        final photo = project.photos[segIndex];
        final framesForSegment = (_defaultFps * photo.durationMilliseconds / 1000).ceil();

        for (int frameIndex = 0; frameIndex < framesForSegment; frameIndex++) {
          if (cancelChecker != null && cancelChecker()) {
            await FlutterQuickVideoEncoder.finish();
            _cleanup([outputPath]);
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

          if (rgbaBytes != null) {
            await FlutterQuickVideoEncoder.appendVideoFrame(rgbaBytes);
          }

          renderedFrames++;
          onProgress(renderedFrames / totalFrames);
        }
      }

      await FlutterQuickVideoEncoder.finish();
      return outputPath;
    } catch (e) {
      print('Ошибка рендера видео: $e');
      _cleanup([outputPath]);
      return null;
    }
  }

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
      if (!audioFile.existsSync()) return false;

      final totalSec = totalDurationMs / 1000.0;
      final startSec = startTime.clamp(0.0, totalSec);
      final availableSec = (totalSec - startSec).clamp(0.0, totalSec);

      if (availableSec <= 0) return false;

      final fadeStart = (availableSec - 1.0).clamp(0.0, availableSec);

      final command =
          '-ss $startSec -i "$audioPath" -i "$videoPath" -filter_complex "[0:a]atrim=0:${availableSec.toStringAsFixed(3)},asetpts=PTS-STARTPTS,volume=$volume,afade=t=out:st=${fadeStart.toStringAsFixed(2)}:d=1[a]" -map 1:v -map "[a]" -c:v copy -c:a aac -b:a 192k -shortest -t ${totalSec.toStringAsFixed(3)} "$outputPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        return true;
      } else {
        _cleanup([outputPath]);
        return false;
      }
    } catch (e) {
      print('Ошибка микширования FFmpeg: $e');
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
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

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
          (frameProgress * project.photos[currentSegmentIndex].durationMilliseconds).toInt();
      
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
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return byteData?.buffer.asUint8List();
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
    final imageFile = File(currentPhoto.imagePath);
    if (!imageFile.existsSync()) return;

    final bytes = await imageFile.readAsBytes();
    final uiImage = await decodeImageFromList(bytes);

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
      intensity: project.cinematicIntensity, // ✅ Именованный параметр
    );
    final liveDst = cinematicResult.rect;

    final colorFilter = ColorFilter.matrix(FilterPresets.matrix(currentPhoto.filter));

    final elapsedMs = frameProgress * currentPhoto.durationMilliseconds;
    final rawT = currentPhoto.entranceDurationMs > 0
        ? (elapsedMs / currentPhoto.entranceDurationMs).clamp(0.0, 1.0)
        : 1.0;
    final entranceT = Curves.easeOut.transform(rawT);

    final transitionMs = currentPhoto.transitionDurationMs.clamp(300, 1500).toDouble();
    final tp = currentPhoto.durationMilliseconds > 0
        ? (elapsedMs / transitionMs).clamp(0.0, 1.0)
        : 1.0;

    double entranceOpacity = 1.0;

    canvas.save();

    switch (currentPhoto.entranceAnimation) {
      case EntranceAnimation.none: break;
      case EntranceAnimation.fadeIn: entranceOpacity *= entranceT; break;
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
        ..color = Colors.white.withOpacity((entranceOpacity * extraOpacity).clamp(0.0, 1.0));
    }

    if (currentPhoto.fitMode == FitMode.contain) {
      if (currentPhoto.backgroundType == BackgroundType.blur) {
        final sigma = (0.06 * width).clamp(24.0, 90.0);
        final bgScale = PhotoFitCalculator.coverScale(image: imageSize, canvas: canvasSize);
        final bgRect = Rect.fromCenter(
          center: Offset(width / 2, height / 2),
          width: imgWidth * bgScale,
          height: imgHeight * bgScale,
        );
        canvas.save();
        canvas.clipRect(fullRect);
        canvas.drawImageRect(
          uiImage, srcRect, bgRect,
          Paint()
            ..colorFilter = colorFilter
            ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)
            ..color = Colors.white.withOpacity(entranceOpacity),
        );
        canvas.drawRect(fullRect, Paint()..color = Colors.black.withOpacity(0.25 * entranceOpacity));
        canvas.restore();
      } else {
        canvas.drawRect(
          fullRect,
          Paint()
            ..colorFilter = colorFilter
            ..color = Color(currentPhoto.backgroundColor).withOpacity(entranceOpacity),
        );
      }
    }

    // ==========================================
    // 2. Переход (фото рисуется в liveDst с учетом Ken Burns + Cinematic)
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
          canvas.drawRect(fullRect, Paint()..color = Colors.black.withOpacity(fadeAlpha));
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
        canvas.clipRect(Rect.fromLTWH(0, 0, width.toDouble() * tp, height.toDouble()));
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(1.0));
        break;

      case TransitionType.glitch:
        if (tp < 0.5) {
          final o = (1.0 - tp * 2) * 10.0;
          canvas.save();
          canvas.translate(o, 0);
          canvas.drawImageRect(uiImage, srcRect, liveDst, Paint()
            ..colorFilter = const ColorFilter.mode(Color(0xFFFF0000), BlendMode.srcATop)
            ..color = Colors.white.withOpacity(0.7));
          canvas.restore();
          canvas.save();
          canvas.translate(-o, 0);
          canvas.drawImageRect(uiImage, srcRect, liveDst, Paint()
            ..colorFilter = const ColorFilter.mode(Color(0xFF00FF00), BlendMode.srcATop)
            ..color = Colors.white.withOpacity(0.7));
          canvas.restore();
        }
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(1.0));
        break;

      case TransitionType.whipPan:
        final wpPos = _easeInOutCubic(tp);
        final wpBlur = math.sin(math.pi * tp) * (width * 0.02);
        canvas.translate(width * (1 - wpPos), 0);
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(1.0)
          ..imageFilter = ui.ImageFilter.blur(sigmaX: wpBlur, sigmaY: wpBlur * 0.25));
        break;

      case TransitionType.crossZoom:
        final cz = _easeInOutCubic(tp);
        final czScale = 1.8 - 0.8 * cz;
        final czBlur = (1.0 - cz) * (width * 0.01);
        _scaleAroundCenter(canvas, width, height, czScale);
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(cz)
          ..imageFilter = ui.ImageFilter.blur(sigmaX: czBlur, sigmaY: czBlur));
        break;

      case TransitionType.flash:
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint((tp / 0.25).clamp(0.0, 1.0)));
        final fl = tp < 0.35 ? 1.0 - (tp / 0.35) : 0.0;
        if (fl > 0) {
          canvas.drawRect(fullRect, Paint()..color = Colors.white.withOpacity(fl * 0.9));
        }
        break;

      case TransitionType.circleReveal:
        final cr = _easeOut(tp);
        final maxR = math.sqrt(width.toDouble() * width + height.toDouble() * height) / 2;
        canvas.save();
        canvas.clipPath(Path()
          ..addOval(Rect.fromCircle(center: Offset(width / 2, height / 2), radius: maxR * cr)));
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(1.0));
        canvas.restore();
        break;

      case TransitionType.spinBlur:
        final sb = _easeOut(tp);
        final sbBlur = (1.0 - sb) * (width * 0.012);
        _rotateAroundCenter(canvas, width, height, (1 - sb) * 0.6);
        _scaleAroundCenter(canvas, width, height, 0.75 + 0.25 * sb);
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(sb)
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sbBlur, sigmaY: sbBlur));
        break;

      case TransitionType.rgbSplit:
        if (tp < 0.6) {
          final k = 1.0 - tp / 0.6;
          final o = k * (width * 0.013);
          canvas.save();
          canvas.translate(o, -o * 0.3);
          canvas.drawImageRect(uiImage, srcRect, liveDst, Paint()
            ..colorFilter = const ColorFilter.mode(Color(0xFFFF0000), BlendMode.srcATop)
            ..color = Colors.white.withOpacity(0.6));
          canvas.restore();
          canvas.save();
          canvas.translate(-o, o * 0.3);
          canvas.drawImageRect(uiImage, srcRect, liveDst, Paint()
            ..colorFilter = const ColorFilter.mode(Color(0xFF00FF00), BlendMode.srcATop)
            ..color = Colors.white.withOpacity(0.6));
          canvas.restore();
          canvas.save();
          canvas.translate(o * 0.5, o * 0.5);
          canvas.drawImageRect(uiImage, srcRect, liveDst, Paint()
            ..colorFilter = const ColorFilter.mode(Color(0xFF0000FF), BlendMode.srcATop)
            ..color = Colors.white.withOpacity(0.5));
          canvas.restore();
          canvas.save();
          final bandTop = height * (0.35 + 0.1 * math.sin(tp * 40) - 0.06);
          canvas.clipRect(Rect.fromLTWH(0, bandTop, width.toDouble(), height * 0.12));
          canvas.translate(-o * 1.5, 0);
          canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint(1.0));
          canvas.restore();
        }
        canvas.drawImageRect(uiImage, srcRect, liveDst, photoPaint((tp / 0.6).clamp(0.0, 1.0)));
        break;
    }

    canvas.restore();
  }

  static void _scaleAroundCenter(Canvas canvas, int width, int height, double scale) {
    canvas.translate(width / 2, height / 2);
    canvas.scale(scale, scale);
    canvas.translate(-width / 2, -height / 2);
  }

  static void _rotateAroundCenter(Canvas canvas, int width, int height, double radians) {
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
        (frameProgress * project.photos[currentSegmentIndex].durationMilliseconds).toInt();

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
      fontWeight: text.fontFamily == 'Unbounded' ? FontWeight.w800 : FontWeight.w600,
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
        final offset = ui.lerpDouble(50.0, 0.0, progress.clamp(0.0, 0.2) / 0.2) ?? 0.0;
        textPainter.paint(canvas, Offset(x, y + offset));
        break;
      case AnimationType.slideDown:
        final offset = ui.lerpDouble(-50.0, 0.0, progress.clamp(0.0, 0.2) / 0.2) ?? 0.0;
        textPainter.paint(canvas, Offset(x, y + offset));
        break;
      case AnimationType.typewriter:
        final charCount = (text.text.length * progress.clamp(0.0, 0.5) / 0.5).round();
        final visibleText = text.text.substring(0, charCount.clamp(0, text.text.length));
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