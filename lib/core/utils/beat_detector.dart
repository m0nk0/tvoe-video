import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;

// ==========================================
// Детектор битов через нативный MediaCodec (без FFmpeg)
// ✅ Кэш + waveform + октавная нормализация BPM + отладка
// ==========================================

/// Логи бит-детектора только в debug-сборках
const bool kBeatDebug = !kReleaseMode;

class BeatAnalysis {
  final List<double> beats;
  final double bpm;
  final List<double> waveform;
  final double durationSec;

  const BeatAnalysis({
    required this.beats,
    required this.bpm,
    this.waveform = const [],
    this.durationSec = 0,
  });

  // ✅ Валидность = есть биты; BPM уже нормализован по октавам
  bool get isValid => beats.length >= 4 && bpm > 0;
  bool get hasWaveform => waveform.isNotEmpty;

  /// Медианный интервал между битами (сек)
  double get medianInterval {
    if (beats.length < 2) return 0;
    final d = <double>[];
    for (int i = 1; i < beats.length; i++) {
      d.add(beats[i] - beats[i - 1]);
    }
    d.sort();
    return d[d.length ~/ 2];
  }
}

class BeatDetector {
  static const MethodChannel _channel =
      MethodChannel('com.tvoymagazine.tvoe_video/exporter');

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
      if (kBeatDebug) {
        print('⚡ BeatDetector: кэш ${audioPath.split('/').last} '
            '(${cached.beats.length} битов, BPM ~${cached.bpm.round()})');
      }
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
      if (kBeatDebug) {
        print('✏️ BeatDetector: биты отредактированы вручную (${newBeats.length})');
      }
    }
  }

  static void clearCache() {
    _cache.clear();
    _inFlight.clear();
  }

  // ==========================================
  // Нативный анализ + октавная нормализация BPM
  // ==========================================
  static Future<BeatAnalysis> _detectBeatsInternal(String audioPath) async {
    try {
      final file = File(audioPath);
      if (!file.existsSync()) {
        print('⚠️ BeatDetector: файл не найден: $audioPath');
        return const BeatAnalysis(beats: [], bpm: 0);
      }

      final result = await _channel.invokeMethod('analyzeBeats', {
        'audioPath': audioPath,
      });

      if (result is! Map) {
        print('⚠️ BeatDetector: неожиданный ответ от натива: $result');
        return const BeatAnalysis(beats: [], bpm: 0);
      }

      final beatsRaw = result['beats'];
      final bpmRaw = result['bpm'];
      final waveRaw = result['waveform'];
      final durRaw = result['durationSec'];

      final beats = <double>[];
      if (beatsRaw is List) {
        for (final v in beatsRaw) {
          if (v is num) beats.add(v.toDouble());
        }
      }

      final rawBpm = bpmRaw is num ? bpmRaw.toDouble() : 0.0;

      // ✅ Октавная нормализация: приводим BPM в 40..220
      double bpm = rawBpm;
      if (bpm > 0) {
        while (bpm < 40) bpm *= 2;
        while (bpm > 220) bpm /= 2;
      }

      final waveform = <double>[];
      if (waveRaw is List) {
        for (final v in waveRaw) {
          if (v is num) waveform.add(v.toDouble());
        }
      }

      final durationSec = durRaw is num ? durRaw.toDouble() : 0.0;

      if (kBeatDebug) {
        final interval = beats.length >= 2
            ? (beats[beats.length ~/ 2] - beats[beats.length ~/ 2 - 1])
            : 0.0;
        print('🎵 BeatDetector: ${beats.length} битов, '
            'BPM raw=${rawBpm.toStringAsFixed(1)} → norm=${bpm.toStringAsFixed(1)}, '
            'интервал≈${interval.toStringAsFixed(2)}с, '
            'первый=${beats.isNotEmpty ? beats.first.toStringAsFixed(2) : '-'}с, '
            'последний=${beats.isNotEmpty ? beats.last.toStringAsFixed(2) : '-'}с, '
            'длительность=${durationSec.toStringAsFixed(1)}с');
        if (beats.length < 4) {
          print('⚠️ BeatDetector: мало битов (${beats.length}) — синк будет отклонён');
        }
      }

      return BeatAnalysis(
        beats: beats,
        bpm: bpm,
        waveform: waveform,
        durationSec: durationSec,
      );
    } catch (e) {
      print('⚠️ BeatDetector: $e');
      return const BeatAnalysis(beats: [], bpm: 0);
    }
  }
}