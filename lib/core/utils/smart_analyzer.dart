import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// ==========================================
// Умный анализатор фото для автоматического монтажа
// ==========================================

/// Настроение фото (на основе цветовой палитры)
enum PhotoMood {
  warm, // тёплые закаты, романтика
  cool, // холодные пейзажи, ночь
  vibrant, // яркие цвета, вечеринка
  muted, // приглушённые, семейные/ностальгические
  neutral, // нейтральные
}

/// Тип композиции
enum CompositionType {
  portrait, // вертикальное фото
  landscape, // горизонтальное
  square, // квадратное
  group, // групповое фото
}

/// Результат анализа одного фото
class SmartPhotoAnalysis {
  final String imagePath;

  // Лица
  final int faceCount;
  final bool hasSmile;
  final bool hasOpenEyes;

  // Цвета
  final PhotoMood mood;
  final double brightness; // 0..1
  final int dominantColor; // ARGB

  // Композиция
  final CompositionType composition;
  final double aspectRatio;

  // Метрики
  final double complexityScore; // 0..1, насколько "сложная" сцена

  // Центр группы лиц (нормализованный 0..1), null если лиц нет
  final double? faceCenterX;
  final double? faceCenterY;

  const SmartPhotoAnalysis({
    required this.imagePath,
    this.faceCount = 0,
    this.hasSmile = false,
    this.hasOpenEyes = true,
    this.mood = PhotoMood.neutral,
    this.brightness = 0.5,
    this.dominantColor = 0xFF808080,
    this.composition = CompositionType.landscape,
    this.aspectRatio = 1.0,
    this.complexityScore = 0.5,
    this.faceCenterX,
    this.faceCenterY,
  });

  /// Является ли фото "эмоциональным" (хорошо для ключевых кадров)
  bool get isEmotional => hasSmile || faceCount >= 2;

  /// Подходит для "медленного" показа (портрет, пейзаж)
  bool get isSlowPaced =>
      composition == CompositionType.portrait ||
      faceCount == 1 ||
      mood == PhotoMood.muted;

  /// Подходит для "быстрого" показа (вечеринка, группа)
  bool get isFastPaced =>
      faceCount >= 3 ||
      mood == PhotoMood.vibrant ||
      composition == CompositionType.group;
}

class SmartAnalyzer {
  static final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: false,
      enableContours: false,
      enableTracking: false,
    ),
  );

  /// Анализ одного фото
  static Future<SmartPhotoAnalysis> analyzePhoto(String imagePath) async {
    try {
      // 1. Читаем байты для анализа цвета
      final bytes = await _readImageBytes(imagePath);
      if (bytes == null) {
        return SmartPhotoAnalysis(imagePath: imagePath);
      }

      // 2. Декодируем изображение (через колбэк → Completer)
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, (img) {
        if (!completer.isCompleted) completer.complete(img);
      });
      final image =
          await completer.future.timeout(const Duration(seconds: 5));
      final width = image.width;
      final height = image.height;

      // 3. Анализ цвета и настроения
      final colorAnalysis = await _analyzeColors(image);

      // 4. Композиция
      final composition = _detectComposition(width, height);
      final aspectRatio = width / height;

      // 5. Распознавание лиц
      final faces = await _faceDetector.processImage(
        InputImage.fromFilePath(imagePath),
      );

      final faceCount = faces.length;
      bool hasSmile = false;
      bool hasOpenEyes = true;

      for (final face in faces) {
        final smileProb = face.smilingProbability ?? 0.0;
        if (smileProb > 0.6) hasSmile = true;

        final leftEyeOpen = face.leftEyeOpenProbability ?? 1.0;
        final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;
        if (leftEyeOpen < 0.4 || rightEyeOpen < 0.4) {
          hasOpenEyes = false;
        }
      }

      // 5.5. Центр группы лиц (для умного центрирования)
      double? faceCenterX;
      double? faceCenterY;
      if (faces.isNotEmpty) {
        double left = double.infinity;
        double top = double.infinity;
        double right = -double.infinity;
        double bottom = -double.infinity;
        for (final f in faces) {
          final b = f.boundingBox;
          left = math.min(left, b.left);
          top = math.min(top, b.top);
          right = math.max(right, b.right);
          bottom = math.max(bottom, b.bottom);
        }
        faceCenterX = ((left + right) / 2) / width;
        faceCenterY = ((top + bottom) / 2) / height;
      }

      // 6. Сложность сцены (эвристически)
      final complexity =
          _estimateComplexity(faceCount, colorAnalysis.brightness);

      return SmartPhotoAnalysis(
        imagePath: imagePath,
        faceCount: faceCount,
        hasSmile: hasSmile,
        hasOpenEyes: hasOpenEyes,
        mood: colorAnalysis.mood,
        brightness: colorAnalysis.brightness,
        dominantColor: colorAnalysis.dominantColor,
        composition: faceCount >= 3 ? CompositionType.group : composition,
        aspectRatio: aspectRatio,
        complexityScore: complexity,
        faceCenterX: faceCenterX,
        faceCenterY: faceCenterY,
      );
    } catch (e) {
      print('⚠️ SmartAnalyzer ошибка для $imagePath: $e');
      return SmartPhotoAnalysis(imagePath: imagePath);
    }
  }

  // ==========================================
  // Вспомогательные методы
  // ==========================================

  static Future<Uint8List?> _readImageBytes(String path) async {
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static CompositionType _detectComposition(int w, int h) {
    final ratio = w / h;
    if (ratio > 1.3) return CompositionType.landscape;
    if (ratio < 0.77) return CompositionType.portrait;
    return CompositionType.square;
  }

  static double _estimateComplexity(int faceCount, double brightness) {
    final faceFactor = (faceCount / 5).clamp(0.0, 1.0);
    final brightnessFactor = 1.0 - (brightness - 0.5).abs();
    return (faceFactor * 0.7 + brightnessFactor * 0.3).clamp(0.0, 1.0);
  }
}

// ==========================================
// Результат анализа цветов
// ==========================================
class _ColorAnalysis {
  final PhotoMood mood;
  final double brightness;
  final int dominantColor;

  _ColorAnalysis({
    required this.mood,
    required this.brightness,
    required this.dominantColor,
  });
}

/// Анализ цветовой палитры и настроения
Future<_ColorAnalysis> _analyzeColors(ui.Image image) async {
  try {
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      return _ColorAnalysis(
        mood: PhotoMood.neutral,
        brightness: 0.5,
        dominantColor: 0xFF808080,
      );
    }

    final pixels = byteData.buffer.asUint32List();
    final sampleSize = math.min(pixels.length, 10000);
    final step = (pixels.length / sampleSize).ceil();

    double totalR = 0, totalG = 0, totalB = 0;
    int warmPixels = 0;
    int coolPixels = 0;
    int vibrantPixels = 0;
    int mutedPixels = 0;
    int count = 0;

    for (int i = 0; i < pixels.length; i += step) {
      final pixel = pixels[i];
      final r = (pixel) & 0xFF;
      final g = (pixel >> 8) & 0xFF;
      final b = (pixel >> 16) & 0xFF;

      totalR += r;
      totalG += g;
      totalB += b;

      final hsl = _rgbToHsl(r, g, b);
      final h = hsl[0];
      final s = hsl[1];
      final l = hsl[2];

      // Тёплые: красный/оранжевый/жёлтый (0-60°, 300-360°)
      if ((h < 60 || h > 300) && s > 0.3) warmPixels++;
      // Холодные: синий/зелёный (180-270°)
      if (h > 180 && h < 270 && s > 0.3) coolPixels++;
      // Яркие: высокая насыщенность
      if (s > 0.6) vibrantPixels++;
      // ✅ Приглушённые: ужесточённый порог (реже срабатывает)
      if (s < 0.25 && l > 0.35 && l < 0.65) mutedPixels++;

      count++;
    }

    if (count == 0) {
      return _ColorAnalysis(
        mood: PhotoMood.neutral,
        brightness: 0.5,
        dominantColor: 0xFF808080,
      );
    }

    final avgR = totalR / count;
    final avgG = totalG / count;
    final avgB = totalB / count;
    final brightness =
        (0.299 * avgR + 0.587 * avgG + 0.114 * avgB) / 255.0;

    final total = warmPixels + coolPixels + vibrantPixels + mutedPixels;
    PhotoMood mood;
    if (total == 0) {
      mood = PhotoMood.neutral;
    } else {
      final warmRatio = warmPixels / total;
      final coolRatio = coolPixels / total;
      final vibrantRatio = vibrantPixels / total;
      final mutedRatio = mutedPixels / total;

      if (vibrantRatio > 0.4) {
        mood = PhotoMood.vibrant;
      } else if (warmRatio > coolRatio && warmRatio > mutedRatio) {
        mood = PhotoMood.warm;
      } else if (coolRatio > warmRatio && coolRatio > mutedRatio) {
        mood = PhotoMood.cool;
      } else if (mutedRatio > 0.55) {
        // ✅ Ужесточённый порог (было 0.3)
        mood = PhotoMood.muted;
      } else {
        mood = PhotoMood.neutral;
      }
    }

    final dominantColor = _colorToArgb(avgR, avgG, avgB);

    return _ColorAnalysis(
      mood: mood,
      brightness: brightness,
      dominantColor: dominantColor,
    );
  } catch (e) {
    print('⚠️ Анализ цветов: $e');
    return _ColorAnalysis(
      mood: PhotoMood.neutral,
      brightness: 0.5,
      dominantColor: 0xFF808080,
    );
  }
}

/// RGB → HSL (hue в градусах 0-360, S и L в 0..1)
List<double> _rgbToHsl(int r, int g, int b) {
  final rn = r / 255.0;
  final gn = g / 255.0;
  final bn = b / 255.0;
  final max = [rn, gn, bn].reduce(math.max);
  final min = [rn, gn, bn].reduce(math.min);
  final delta = max - min;

  double h = 0;
  if (delta != 0) {
    if (max == rn) {
      h = 60 * (((gn - bn) / delta) % 6);
    } else if (max == gn) {
      h = 60 * (((bn - rn) / delta) + 2);
    } else {
      h = 60 * (((rn - gn) / delta) + 4);
    }
    if (h < 0) h += 360;
  }

  final l = (max + min) / 2;
  final s = delta == 0 ? 0.0 : delta / (1 - (2 * l - 1).abs());

  return [h, s, l];
}

int _colorToArgb(double r, double g, double b) {
  final ir = r.toInt().clamp(0, 255);
  final ig = g.toInt().clamp(0, 255);
  final ib = b.toInt().clamp(0, 255);
  return 0xFF000000 | (ib << 16) | (ig << 8) | ir;
}