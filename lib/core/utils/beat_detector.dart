import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:path_provider/path_provider.dart';

// ==========================================
// Детектор битов музыки через FFmpeg (RMS-пики)
// ✅ Кэш + ✅ Waveform для визуализации
// ==========================================

class BeatAnalysis {
  /// Времена ударов в секундах
  final List<double> beats;

  /// Оценка темпа
  final double bpm;

  /// ✅ НОВОЕ: нормализованный амплитудный профиль (0..1) для waveform
  final List<double> waveform;

  /// ✅ НОВОЕ: общая длительность трека в секундах
  final double durationSec;

  const BeatAnalysis({
    required this.beats,
    required this.bpm,
    this.waveform = const [],
    this.durationSec = 0,
  });

  bool get isValid => beats.length >= 4 && bpm > 40 && bpm < 220;
  bool get hasWaveform => waveform.isNotEmpty;
}

class BeatDetector {
  static const int _resetFrames = 2;
  static const double _minInterval = 0.25;
  static const double _sensitivity = 1.4;

  // ==========================================
  // КЭШ результатов анализа
  // ==========================================
  static final Map<String, BeatAnalysis> _cache = {};
  static final Map<String, Future<BeatAnalysis>> _inFlight = {};

  static Future<String> _cacheKey(String path) async {
    try {
      final stat = await File(path).stat();
      return '$path|${stat.modified.millisecondsSinceEpoch}|${stat.size}';
    } catch (_) {
      return '$path|unknown';
    }
  }

  static Future<BeatAnalysis> detectBeats(String audioPath) async {
    final key = await _cacheKey(audioPath);

    final cached = _cache[key];
    if (cached != null) {
      print('⚡ BeatDetector: кэш для ${audioPath.split('/').last} (${cached.beats.length} битов, BPM ~${cached.bpm.round()})');
      return cached;
    }

    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;

    final future = _detectBeatsInternal(audioPath).then((result) {
      _inFlight.remove(key);
      _cache[key] = result;
      return result;
    }).catchError((Object e) {
      _inFlight.remove(key);
      throw e;
    });

    _inFlight[key] = future;
    return future;
  }

  /// ✅ НОВОЕ: ручная корректировка битов (сохраняется в кэш)
  static Future<void> overrideBeats(String audioPath, List<double> newBeats) async {
    final key = await _cacheKey(audioPath);
    final cur = _cache[key];
    if (cur != null) {
      _cache[key] = BeatAnalysis(
        beats: newBeats,
        bpm: cur.bpm,
        waveform: cur.waveform,
        durationSec: cur.durationSec,
      );
      print('✏️ BeatDetector: биты отредактированы вручную (${newBeats.length})');
    }
  }

  static void clearCache() {
    _cache.clear();
    _inFlight.clear();
  }

  // ==========================================
  // Реальный анализ трека
  // ==========================================
  static Future<BeatAnalysis> _detectBeatsInternal(String audioPath) async {
    try {
      final dir = await getTemporaryDirectory();
      final outFile = File(
          '${dir.path}/rms_${DateTime.now().millisecondsSinceEpoch}.txt');

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
  // Парсинг вывода FFmpeg + детекция пиков + waveform
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
          energies.add(math.pow(10, v / 20).toDouble());
        }
      }
    }

    if (times.length < 8) {
      return const BeatAnalysis(beats: [], bpm: 0);
    }

    // ---- Waveform: сжимаем энергии в 240 корзин по времени ----
    final totalSec = times.last;
        final buckets = (totalSec * 20).round().clamp(64, 4000); // 1 корзина на 50 мс
    final waveform = List<double>.filled(buckets, 0);
    final bucketSec = totalSec / buckets;
    for (int i = 0; i < times.length; i++) {
      final b = (times[i] / bucketSec).floor().clamp(0, buckets - 1);
      if (energies[i] > waveform[b]) waveform[b] = energies[i];
    }
    final maxAmp = waveform.reduce(math.max);
    if (maxAmp > 0) {
      for (int i = 0; i < buckets; i++) {
        waveform[i] = (waveform[i] / maxAmp).clamp(0.0, 1.0).toDouble();
      }
    }

    // ---- Поиск пиков относительно локальной средней ----
    final beats = <double>[];
    const window = 20;
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
      return BeatAnalysis(beats: const [], bpm: 0, waveform: waveform, durationSec: totalSec);
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
    return BeatAnalysis(beats: beats, bpm: bpm, waveform: waveform, durationSec: totalSec);
  }
}