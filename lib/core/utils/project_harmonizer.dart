import 'package:flutter/material.dart';
import '../../data/models/photo_layer.dart';
import 'smart_analyzer.dart';

/// Модуль для автоматического улучшения всего проекта
class ProjectHarmonizer {
  
  /// Анализирует все фото и возвращает map: imagePath -> матрица коррекции
  static Future<Map<String, List<double>>> harmonizeProject(
    List<PhotoLayer> photos,
    void Function(double progress) onProgress,
  ) async {
    if (photos.isEmpty) return {};

    // 1. Анализируем все фото
    final analyses = <SmartPhotoAnalysis>[];
    for (int i = 0; i < photos.length; i++) {
      final analysis = await SmartAnalyzer.analyzePhoto(photos[i].imagePath);
      analyses.add(analysis);
      onProgress((i + 1) / photos.length * 0.5); // 50% времени на анализ
    }

    // 2. Выбираем эталонное фото (самое светлое, с лицами, высокой сложностью)
    final reference = _selectReferencePhoto(analyses);
    final refIndex = analyses.indexOf(reference);
    debugPrint('✨ Эталон для гармонизации: фото #$refIndex (${photos[refIndex].imagePath})');

    // 3. Вычисляем целевой профиль на основе эталона
    final target = _calculateTargetProfile(reference);

    // 4. Генерируем матрицы для каждого фото
    final matrices = <String, List<double>>{};
    for (int i = 0; i < photos.length; i++) {
      // Интенсивность 0.7 = мягкая, естественная коррекция (70%)
      final matrix = _generateHarmonyMatrix(analyses[i], target, 0.7);
      matrices[photos[i].imagePath] = matrix;
      onProgress(0.5 + (i + 1) / photos.length * 0.5); // 50-100% на генерацию
    }

    return matrices;
  }

  static SmartPhotoAnalysis _selectReferencePhoto(List<SmartPhotoAnalysis> analyses) {
    if (analyses.isEmpty) return analyses.first;
    SmartPhotoAnalysis? best;
    double bestScore = -1;

    for (final a in analyses) {
      double score = 0;
      // Яркость (идеал 0.5-0.7)
      if (a.brightness >= 0.5 && a.brightness <= 0.7) score += 0.3;
      else if (a.brightness >= 0.4 && a.brightness <= 0.8) score += 0.2;
      
      // Наличие лиц и эмоций
      if (a.faceCount > 0) score += 0.3;
      if (a.hasSmile) score += 0.2;
      
      // Сложность сцены
      score += a.complexityScore * 0.2;

      if (score > bestScore) {
        bestScore = score;
        best = a;
      }
    }
    return best ?? analyses.first;
  }

  static Map<String, double> _calculateTargetProfile(SmartPhotoAnalysis reference) {
    final refR = (reference.dominantColor >> 16) & 0xFF;
    final refG = (reference.dominantColor >> 8) & 0xFF;
    final refB = reference.dominantColor & 0xFF;

    return {
      'r': refR.toDouble(),
      'g': refG.toDouble(),
      'b': refB.toDouble(),
      'brightness': reference.brightness,
    };
  }

  static List<double> _generateHarmonyMatrix(
    SmartPhotoAnalysis analysis,
    Map<String, double> target,
    double intensity,
  ) {
    final curR = (analysis.dominantColor >> 16) & 0xFF;
    final curG = (analysis.dominantColor >> 8) & 0xFF;
    final curB = analysis.dominantColor & 0xFF;
    final curBrightness = analysis.brightness;

    final targetR = target['r']!;
    final targetG = target['g']!;
    final targetB = target['b']!;
    final targetBrightness = target['brightness']!;

    // 1. Контраст: подтягиваем к целевому
    final currentContrast = 0.5 + (curBrightness - 0.5).abs();
    final targetContrast = 0.7;
    final contrastFactor = 1.0 + (targetContrast - currentContrast) * intensity * 0.5;

    // 2. Яркость и цвет: вычисляем смещение
    final brightnessOffset = (targetBrightness - curBrightness) * 255.0 * intensity;
    final rOffset = (targetR - curR) * intensity;
    final gOffset = (targetG - curG) * intensity;
    final bOffset = (targetB - curB) * intensity;

    // 3. Строим матрицу 5x5 (20 элементов) для ColorFilter.matrix
    final matrix = List<double>.filled(20, 0.0);
    matrix[0] = contrastFactor;  // R scale
    matrix[6] = contrastFactor;  // G scale
    matrix[12] = contrastFactor; // B scale
    matrix[18] = 1.0;            // Alpha scale

    // Компенсация контраста + сдвиг яркости + сдвиг цвета
    final contrastCompensation = 128.0 * (1.0 - contrastFactor);
    matrix[4] = rOffset + brightnessOffset + contrastCompensation;
    matrix[9] = gOffset + brightnessOffset + contrastCompensation;
    matrix[14] = bOffset + brightnessOffset + contrastCompensation;

    return matrix;
  }
}