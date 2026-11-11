import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/beat_detector.dart';
import '../../data/models/photo_layer.dart';
import '../../data/models/text_layer.dart';
import '../../data/providers/project_provider.dart';
import '../../data/providers/projects_provider.dart';

// ==========================================
// 🎬 Timeline Studio: полноэкранный мультитрек-таймлайн
// ✅ Логарифмический зум (0.15–3.0), плавный
// ✅ Дорожки по центру экрана
// ==========================================
class TimelineStudioScreen extends ConsumerStatefulWidget {
  const TimelineStudioScreen({super.key});

  @override
  ConsumerState<TimelineStudioScreen> createState() => _TimelineStudioScreenState();
}

class _TimelineStudioScreenState extends ConsumerState<TimelineStudioScreen> {
  final ScrollController _scroll = ScrollController();

  // ✅ ЛОГАРИФМИЧЕСКИЙ ЗУМ: слайдер 0..1 → zoom 0.15..3.0
  double _sliderValue = 0.4; // начальная позиция (~zoom 0.6)
  double _playheadMs = 0;
  List<double>? _editedBeats;
  BeatAnalysis? _analysis;
  bool _loading = true;

  static const double _videoH = 96;
  static const double _audioH = 88;
  static const double _textH = 48;
  static const double _padLeft = 40;

  static const double _minZoom = 0.15;
  static const double _maxZoom = 3.0;

  /// Слайдер (0..1) → реальный зум (логарифмически)
  double get _zoom => _minZoom * math.pow(_maxZoom / _minZoom, _sliderValue);
  double get _pxPerMs => 0.1 * _zoom;

  @override
  void initState() {
    super.initState();
    _playheadMs = ref.read(playheadMsProvider);
    _loadBeats();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadBeats() async {
    final track = ref.read(currentProjectProvider).audioTrack;
    if (track == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final a = await BeatDetector.detectBeats(track.filePath);
    if (!mounted) return;
    setState(() {
      _analysis = a;
      _loading = false;
    });
  }

  List<double> get _beats => _editedBeats ?? _analysis?.beats ?? const [];

  double get _audioOffsetMs =>
      (ref.read(currentProjectProvider).audioTrack?.startTime ?? 0) * 1000;

  double _beatMs(int i) => _audioOffsetMs + _beats[i] * 1000;

  double _snapToBeat(double ms, double thresholdMs) {
    double best = ms;
    double bestDist = thresholdMs;
    for (int i = 0; i < _beats.length; i++) {
      final d = (ms - _beatMs(i)).abs();
      if (d < bestDist) {
        bestDist = d;
        best = _beatMs(i);
      }
    }
    return best;
  }

  List<double> _frameStarts(List<PhotoLayer> photos) {
    final starts = <double>[0];
    double acc = 0;
    for (final p in photos) {
      acc += p.durationMilliseconds;
      starts.add(acc);
    }
    return starts;
  }

  List<double> _visibleWave(double audioVisibleMs) {
    final a = _analysis;
    if (a == null || a.waveform.isEmpty || a.durationSec <= 0) return const [];
    final totalMsAudio = a.durationSec * 1000;
    final n = a.waveform.length;
    final i0 = (_audioOffsetMs / totalMsAudio * n).floor().clamp(0, n - 1);
    final i1 = ((_audioOffsetMs + audioVisibleMs) / totalMsAudio * n).ceil().clamp(i0 + 1, n);
    return a.waveform.sublist(i0, i1);
  }

  TextLayer _cloneText(TextLayer t) => TextLayer(
        text: t.text,
        fontFamily: t.fontFamily,
        fontSize: t.fontSize,
        colorValue: t.colorValue,
        startTimeMilliseconds: t.startTimeMilliseconds,
        endTimeMilliseconds: t.endTimeMilliseconds,
        animation: t.animation,
        positionX: t.positionX,
        positionY: t.positionY,
      );

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(currentProjectProvider);
    final photos = project.photos;
    final texts = project.texts;
    final starts = _frameStarts(photos);

    final totalVideo = photos.fold<int>(0, (s, p) => s + p.durationMilliseconds).toDouble();
    final textEnd = texts.isEmpty
        ? 0.0
        : texts.map((t) => t.endTimeMilliseconds.toDouble()).reduce(math.max);
    final totalMs = [totalVideo, textEnd, 1000.0].reduce(math.max);

    final audioDurMs = (_analysis?.durationSec ?? 0) * 1000;
    final audioVisibleMs = (totalVideo > _audioOffsetMs)
        ? math.min(audioDurMs, totalVideo - _audioOffsetMs).clamp(0.0, audioDurMs).toDouble()
        : 0.0;

    final contentWidth = _padLeft + totalMs * _pxPerMs + 160;

    // ✅ Высота блока дорожек для центрирования
    const double tracksHeight = _videoH + _audioH + _textH + 2;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, size: 24),
          color: AppColors.textPrimary,
          tooltip: 'Свернуть',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Таймлайн-студия',
          style: GoogleFonts.unbounded(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, size: 24),
            color: AppColors.primary,
            tooltip: 'Готово (сохранить)',
            onPressed: () async {
              ref.read(playheadMsProvider.notifier).state = _playheadMs;
              await ref.read(projectRepositoryProvider).saveProject(ref.read(currentProjectProvider));
              ref.read(projectsProvider.notifier).refresh();
              if (mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ✅ ЦЕНТРИРОВАНИЕ: дорожки по вертикали в центре доступного пространства
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Сдвигаем блок дорожек вниз, чтобы он был по центру
                      // (минус нижняя панель зума учтена через Expanded)
                      final topOffset = (constraints.maxHeight - tracksHeight) / 2;
                      return Stack(
  children: [
    // ✅ ФОНОВАЯ ПАНЕЛЬ под дорожками
    Positioned(
      top: topOffset.clamp(0.0, constraints.maxHeight) - 12,
      left: 8,
      right: 8,
      height: tracksHeight + 24,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF16181A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
        ),
      ),
    ),
    // Дорожки
    Positioned(
      top: topOffset.clamp(0.0, constraints.maxHeight),
      left: 0,
      right: 0,
      height: tracksHeight,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: contentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildVideoTrack(photos, starts),
              Container(height: 1, color: AppColors.divider),
              _buildAudioTrack(totalVideo, audioVisibleMs),
              Container(height: 1, color: AppColors.divider),
              _buildTextTrack(texts),
            ],
          ),
        ),
      ),
    ),
    // Плейхед
    Positioned(
      top: topOffset.clamp(0.0, constraints.maxHeight),
      left: 0,
      right: 0,
      height: tracksHeight,
      child: IgnorePointer(
        child: CustomPaint(
          painter: _PlayheadPainter(
            x: _padLeft + _playheadMs * _pxPerMs - (_scroll.hasClients ? _scroll.offset : 0),
            color: AppColors.primary,
          ),
        ),
      ),
    ),
    // Ручка плейхеда
    Positioned(
      top: topOffset.clamp(0.0, constraints.maxHeight) - 4,
      left: _padLeft + _playheadMs * _pxPerMs - (_scroll.hasClients ? _scroll.offset : 0) - 12,
      child: _PlayheadHandle(
        onDrag: (dx) {
          setState(() {
            _playheadMs += dx / _pxPerMs;
            _playheadMs = _playheadMs.clamp(0.0, totalMs).toDouble();
          });
        },
        onEnd: () {
          ref.read(playheadMsProvider.notifier).state = _playheadMs;
        },
      ),
    ),
    // Подписи дорожек
    Positioned(
      top: topOffset.clamp(0.0, constraints.maxHeight),
      left: 0,
      height: tracksHeight,
      child: Container(
        width: _padLeft,
        color: const Color(0xFF16181A).withOpacity(0.85),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: _videoH, child: const Center(child: Icon(Icons.videocam_outlined, size: 16, color: AppColors.textMuted))),
            SizedBox(height: _audioH, child: const Center(child: Icon(Icons.music_note, size: 16, color: AppColors.textMuted))),
            SizedBox(height: _textH, child: const Center(child: Icon(Icons.text_fields, size: 16, color: AppColors.textMuted))),
          ],
        ),
      ),
    ),
  ],
);
                    },
                  ),
          ),
          // Нижняя панель: зум + время
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.zoom_out, size: 18, color: AppColors.textMuted),
                Expanded(
                  // ✅ ЛОГАРИФМИЧЕСКИЙ СЛАЙДЕР: плавный на всём диапазоне
                  child: Slider(
                    value: _sliderValue,
                    min: 0.0,
                    max: 1.0,
                    activeColor: AppColors.primary,
                    inactiveColor: AppColors.surfaceLight,
                    onChanged: (v) => setState(() => _sliderValue = v),
                  ),
                ),
                const Icon(Icons.zoom_in, size: 18, color: AppColors.textMuted),
                const SizedBox(width: 12),
                Text(
                  '${(_playheadMs / 1000).toStringAsFixed(1)}s / ${(totalMs / 1000).toStringAsFixed(1)}s',
                  style: GoogleFonts.jetBrainsMono(fontSize: 12, color: AppColors.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoTrack(List<PhotoLayer> photos, List<double> starts) {
    return SizedBox(
      height: _videoH,
      child: Stack(
        children: [
          for (int i = 0; i < photos.length; i++)
            Positioned(
              left: _padLeft + starts[i] * _pxPerMs,
              width: math.max(8, photos[i].durationMilliseconds * _pxPerMs - 2),
              top: 6,
              bottom: 6,
              child: _VideoBlock(
                photo: photos[i],
                isSelected: i == ref.watch(selectedPhotoIndexProvider),
                pxPerMs: _pxPerMs,
                onTap: () {
                  ref.read(selectedPhotoIndexProvider.notifier).state = i;
                },
                onResizeStart: () {
                  ref.read(currentProjectProvider.notifier).beginBatch();
                },
                onResize: (deltaMs) {
                  final start = starts[i];
                  double newDur = photos[i].durationMilliseconds + deltaMs;
                  final boundary = start + newDur;
                  final snapped = _snapToBeat(boundary, 12 / _pxPerMs);
                  if ((snapped - boundary).abs() > 0.01) {
                    newDur = snapped - start;
                  }
                  newDur = newDur.clamp(300.0, 10000.0).toDouble();
                  ref.read(currentProjectProvider.notifier).updatePhotoDuration(i, newDur.round());
                },
                onResizeEnd: () {
                  ref.read(currentProjectProvider.notifier).endBatch();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAudioTrack(double totalVideo, double audioVisibleMs) {
    final track = ref.watch(currentProjectProvider).audioTrack;
    if (track == null) {
      return SizedBox(
        height: _audioH,
        child: Center(
          child: Text('Музыка не добавлена', style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textMuted)),
        ),
      );
    }

    final wave = _visibleWave(audioVisibleMs);
    final audioWidth = audioVisibleMs * _pxPerMs;

    return SizedBox(
      height: _audioH,
      child: Stack(
        children: [
          if (wave.isNotEmpty)
            Positioned(
              left: _padLeft + _audioOffsetMs * _pxPerMs,
              width: audioWidth,
              top: 0,
              bottom: 0,
              child: CustomPaint(painter: _WaveformPainter(wave: wave, color: AppColors.primary.withOpacity(0.55))),
            ),
          for (int i = 0; i < _beats.length; i++)
            if (_beatMs(i) <= totalVideo)
              Positioned(
                left: _padLeft + _beatMs(i) * _pxPerMs - 12,
                width: 24,
                top: 0,
                bottom: 0,
                child: _BeatMarker(
                  onDrag: (dx) {
                    setState(() {
                      _editedBeats = List<double>.from(_beats);
                      final deltaSec = (dx / _pxPerMs) / 1000;
                      final min = i > 0 ? _editedBeats![i - 1] + 0.05 : 0.0;
                      final max = i < _editedBeats!.length - 1 ? _editedBeats![i + 1] - 0.05 : 9999.0;
                      _editedBeats![i] = (_editedBeats![i] + deltaSec).clamp(min, max).toDouble();
                    });
                  },
                  onEnd: () {
                    if (_editedBeats != null) {
                      BeatDetector.overrideBeats(track.filePath, _editedBeats!);
                    }
                  },
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildTextTrack(List<TextLayer> texts) {
    if (texts.isEmpty) {
      return SizedBox(
        height: _textH,
        child: Center(
          child: Text('Текста нет', style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textMuted)),
        ),
      );
    }
    return SizedBox(
      height: _textH,
      child: Stack(
        children: [
          for (int i = 0; i < texts.length; i++)
            Positioned(
              left: _padLeft + texts[i].startTimeMilliseconds * _pxPerMs,
              width: math.max(12, (texts[i].endTimeMilliseconds - texts[i].startTimeMilliseconds) * _pxPerMs - 2),
              top: 8,
              bottom: 8,
              child: _TextBlock(
                label: texts[i].text,
                onMoveStart: () => ref.read(currentProjectProvider.notifier).beginBatch(),
                onMove: (deltaMs) {
                  final clone = _cloneText(texts[i]);
                  final dur = clone.endTimeMilliseconds - clone.startTimeMilliseconds;
                  int newStart = (clone.startTimeMilliseconds + deltaMs).round();
                  newStart = newStart.clamp(0, 1000000);
                  clone.startTimeMilliseconds = newStart;
                  clone.endTimeMilliseconds = newStart + dur;
                  ref.read(currentProjectProvider.notifier).updateText(i, clone);
                },
                onMoveEnd: () => ref.read(currentProjectProvider.notifier).endBatch(),
              ),
            ),
        ],
      ),
    );
  }
}

class _VideoBlock extends StatefulWidget {
  final PhotoLayer photo;
  final bool isSelected;
  final double pxPerMs;
  final VoidCallback onTap;
  final VoidCallback onResizeStart;
  final ValueChanged<double> onResize;
  final VoidCallback onResizeEnd;

  const _VideoBlock({
    required this.photo,
    required this.isSelected,
    required this.pxPerMs,
    required this.onTap,
    required this.onResizeStart,
    required this.onResize,
    required this.onResizeEnd,
  });

  @override
  State<_VideoBlock> createState() => _VideoBlockState();
}

class _VideoBlockState extends State<_VideoBlock> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: widget.isSelected ? AppColors.primary : Colors.transparent, width: 2),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              right: 10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  File(widget.photo.imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 18),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 10,
              child: GestureDetector(
                onHorizontalDragStart: (_) => widget.onResizeStart(),
                onHorizontalDragUpdate: (d) => widget.onResize(d.delta.dx / widget.pxPerMs),
                onHorizontalDragEnd: (_) => widget.onResizeEnd(),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.6),
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                  ),
                  child: const Center(child: Icon(Icons.drag_handle, size: 12, color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeatMarker extends StatefulWidget {
  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;

  const _BeatMarker({required this.onDrag, required this.onEnd});

  @override
  State<_BeatMarker> createState() => _BeatMarkerState();
}

class _BeatMarkerState extends State<_BeatMarker> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
      onHorizontalDragEnd: (_) => widget.onEnd(),
      child: Center(
        child: Container(width: 2, height: double.infinity, color: AppColors.aiAccent.withOpacity(0.8)),
      ),
    );
  }
}

class _TextBlock extends StatefulWidget {
  final String label;
  final VoidCallback onMoveStart;
  final ValueChanged<double> onMove;
  final VoidCallback onMoveEnd;

  const _TextBlock({
    required this.label,
    required this.onMoveStart,
    required this.onMove,
    required this.onMoveEnd,
  });

  @override
  State<_TextBlock> createState() => _TextBlockState();
}

class _TextBlockState extends State<_TextBlock> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: (_) => widget.onMoveStart(),
      onHorizontalDragUpdate: (d) => widget.onMove(d.delta.dx),
      onHorizontalDragEnd: (_) => widget.onMoveEnd(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.25),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.primary.withOpacity(0.6)),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(fontSize: 11, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _PlayheadHandle extends StatefulWidget {
  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;

  const _PlayheadHandle({required this.onDrag, required this.onEnd});

  @override
  State<_PlayheadHandle> createState() => _PlayheadHandleState();
}

class _PlayheadHandleState extends State<_PlayheadHandle> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
      onHorizontalDragEnd: (_) => widget.onEnd(),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        child: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> wave;
  final Color color;

  const _WaveformPainter({required this.wave, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (wave.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    final step = size.width / wave.length;
    final mid = size.height / 2;
    for (int i = 0; i < wave.length; i++) {
      final h = wave[i] * mid;
      final x = i * step;
      canvas.drawLine(Offset(x, mid - h), Offset(x, mid + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) => old.wave != wave;
}

class _PlayheadPainter extends CustomPainter {
  final double x;
  final Color color;

  const _PlayheadPainter({required this.x, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (x < 0 || x > size.width) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _PlayheadPainter old) => old.x != x;
}