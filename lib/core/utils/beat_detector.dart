import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:path_provider/path_provider.dart';

// ==========================================
// Детектор битов музыки через FFmpeg (RMS-пики)
// ==========================================

class BeatAnalysis {
  /// Времена ударов в секундах
  final List<double> beats;

  /// Оценка темпа
  final double bpm;

  const BeatAnalysis({required this.beats, required this.bpm});

  /// Достаточно данных для синхронизации
  bool get isValid => beats.length >= 4 && bpm > 40 && bpm < 220;
}

class BeatDetector {
  /// Окно анализа (~52 мс при 44.1 кГц)
  static const int _resetFrames = 2;

  /// Минимальный интервал между ударами (сек) = макс 240 BPM
  static const double _minInterval = 0.25;

  /// Чувствительность: пик должен превышать локальную среднюю в N раз
  static const double _sensitivity = 1.4;

  /// Анализ трека: возвращает времена ударов и BPM
  static Future<BeatAnalysis> detectBeats(String audioPath) async {
    try {
      final dir = await getTemporaryDirectory();
      final outFile = File(
          '${dir.path}/rms_${DateTime.now().millisecondsSinceEpoch}.txt');

      // Извлекаем RMS-уровень по окнам в текстовый файл
      final cmd = '-i "$audioPath" -af '
          '"astats=metadata=1:reset=$_resetFrames,'
          'ametadata=print:key=lavfi.astats.Overall.RMS_level:file=${outFile.path}" '
          '-f null -';

      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();

      if (!ReturnCode.isSuccess(rc) || !outFile.existsSync()) {
        print('⚠️ BeatDetector: FFmpeg не смог анализировать трек');
        return const BeatAnalysis(beats: [], bpm: 0);
      }

      final content = await outFile.readAsString();
      try {
        outFile.deleteSync();
      } catch (_) {}

      return _parseAndDetect(content);
    } catch (e) {
      print('⚠️ BeatDetector: $e');
      return const BeatAnalysis(beats: [], bpm: 0);
    }
  }

  // ==========================================
  // Парсинг вывода FFmpeg + детекция пиков
  // ==========================================
  static BeatAnalysis _parseAndDetect(String content) {
    final times = <double>[];
    final energies = <double>[];
    double? lastTime;

    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('frame:')) {
        final m = RegExp(r'pts_time:([0-9.]+)').firstMatch(line);
        if (m != null) lastTime = double.parse(m.group(1)!);
      } else if (line.startsWith('lavfi.astats.Overall.RMS_level=')) {
        final v = double.tryParse(line.split('=').last);
        if (v != null && lastTime != null) {
          times.add(lastTime);
          // дБ → линейная энергия
          energies.add(math.pow(10, v / 20).toDouble());
        }
      }
    }

    if (times.length < 8) {
      return const BeatAnalysis(beats: [], bpm: 0);
    }

    // ---- Поиск пиков относительно локальной средней ----
    final beats = <double>[];
    const window = 20; // ~1 сек окружения
    double lastBeat = -1;

    for (int i = 2; i < times.length - 2; i++) {
      final from = math.max(0, i - window);
      final to = math.min(times.length, i + window);
      double sum = 0;
      for (int j = from; j < to; j++) {
        sum += energies[j];
      }
      final avg = sum / (to - from);

      final isPeak = energies[i] > avg * _sensitivity &&
          energies[i] > energies[i - 1] &&
          energies[i] >= energies[i + 1];

      if (isPeak && (lastBeat < 0 || times[i] - lastBeat >= _minInterval)) {
        beats.add(times[i]);
        lastBeat = times[i];
      }
    }

    if (beats.length < 4) {
      return const BeatAnalysis(beats: [], bpm: 0);
    }

    // ---- BPM по медиане интервалов ----
    final intervals = <double>[];
    for (int i = 1; i < beats.length; i++) {
      intervals.add(beats[i] - beats[i - 1]);
    }
    intervals.sort();
    final median = intervals[intervals.length ~/ 2];
    final bpm = median > 0 ? 60 / median : 0.0;

    print('🎵 BeatDetector: ${beats.length} битов, BPM ~${bpm.round()}');
    return BeatAnalysis(beats: beats, bpm: bpm);
  }
}