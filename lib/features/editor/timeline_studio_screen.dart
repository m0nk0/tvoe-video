import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/beat_detector.dart';
import '../../data/models/keyframe.dart';
import '../../data/models/photo_layer.dart';
import '../../data/models/text_layer.dart';
import '../../data/providers/project_provider.dart';
import '../../data/providers/projects_provider.dart';
import 'audio_tools.dart';
import 'crop/crop_editor_screen.dart';
import 'playback.dart';
import 'sheets/effects_sheet.dart';
import 'sheets/format_sheet.dart';
import 'sheets/keyframe_sheet.dart';
import 'sheets/live_motion_sheet.dart';
import 'sheets/photo_settings_sheet.dart';
import 'sheets/transitions_sheet.dart';
import 'text_tools.dart' hide frameStartMs;

// ==========================================
// 🎬 Timeline Studio v4.6 (под-срез 2: кейфреймы)
// ✅ ромбики ◆ на клипах
// ✅ кнопка "◆ Кейфрейм" + "Удалить ◆"
// ✅ подсветка границ клипа при drag кейфрейма
// ✅ троттлинг drag плейхеда до 60 fps
// ==========================================
class TimelineStudioScreen extends ConsumerStatefulWidget {
  const TimelineStudioScreen({super.key});

  @override
  ConsumerState<TimelineStudioScreen> createState() => _TimelineStudioScreenState();
}

class _TimelineStudioScreenState extends ConsumerState<TimelineStudioScreen> {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _playheadVN = ValueNotifier(0.0);

  double _sliderValue = 0.4;
  bool _showBeats = true;
  List<double>? _editedBeats;
  BeatAnalysis? _analysis;
  bool _loading = true;
  int? _kfDragPhoto;
  double _kfPendingDx = 0;
  int _lastKfCommit = 0;
  int _lastPlayheadVNUpdate = 0;

  static const double _videoH = 96;
  static const double _audioH = 88;
  static const double _textH = 48;
  static const double _padLeft = 40;
  static const double _minZoom = 0.15;
  static const double _maxZoom = 3.0;
  static const int _frameMs = 33;
  static const double _baseTracksH = _videoH + _audioH + _textH + 2;

  double get _zoom => _minZoom * math.pow(_maxZoom / _minZoom, _sliderValue);
  double get _pxPerMs => 0.1 * _zoom;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _playheadVN.value = ref.read(playheadMsProvider);
    _loadBeats();
  }

  void _onScroll() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _playheadVN.dispose();
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
    final i1 =
        ((_audioOffsetMs + audioVisibleMs) / totalMsAudio * n).ceil().clamp(i0 + 1, n);
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

  void _snack(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }

  void _splitAtPlayhead() {
    final photos = ref.read(currentProjectProvider).photos;
    if (photos.isEmpty) return;
    final idx = ref.read(selectedPhotoIndexProvider).clamp(0, photos.length - 1);
    final start = frameStartMs(photos, idx);
    final local = (ref.read(playheadMsProvider) - start).round();
    if (local <= 0 || local >= photos[idx].durationMilliseconds) {
      _snack('Поставь плейхед внутрь кадра, чтобы разделить', Colors.orange);
      return;
    }
    ref.read(currentProjectProvider.notifier).splitPhoto(idx, local);
    HapticFeedback.mediumImpact();
    _snack('✂️ Кадр разделён', Colors.green);
  }

  void _stepFrame(int dir) {
    final photos = ref.read(currentProjectProvider).photos;
    final total = photos.fold<int>(0, (s, p) => s + p.durationMilliseconds).toDouble();
    final next = (ref.read(playheadMsProvider) + dir * _frameMs).clamp(0.0, total).toDouble();
    ref.read(playheadMsProvider.notifier).state = next;
  }

  bool _isKeyframeSelected(int photoIndex, int kfIndex) {
    final sel = ref.watch(selectedKeyframeProvider);
    return sel != null && sel[0] == photoIndex && sel[1] == kfIndex;
  }

  void _addKeyframeAtPlayhead() {
    final photos = ref.read(currentProjectProvider).photos;
    if (photos.isEmpty) return;
    final idx = ref.read(selectedPhotoIndexProvider).clamp(0, photos.length - 1);
    final start = frameStartMs(photos, idx);
    final localMs = (ref.read(playheadMsProvider) - start)
        .clamp(0.0, photos[idx].durationMilliseconds.toDouble());
    ref.read(currentProjectProvider.notifier).addKeyframe(idx, Keyframe(tMs: localMs));
    HapticFeedback.lightImpact();
    _snack('◆ Кейфрейм добавлен', Colors.green);
  }

  void _removeSelectedKeyframe() {
    final sel = ref.read(selectedKeyframeProvider);
    if (sel == null) return;
    ref.read(currentProjectProvider.notifier).removeKeyframe(sel[0], sel[1]);
    ref.read(selectedKeyframeProvider.notifier).state = null;
    HapticFeedback.lightImpact();
    _snack('◆ Кейфрейм удалён', Colors.orange);
  }

  Widget _playheadTimeLabel(double totalMs) {
    return ValueListenableBuilder<double>(
      valueListenable: _playheadVN,
      builder: (context, ph, _) => Text(
        '${(ph / 1000).toStringAsFixed(1)}s / ${(totalMs / 1000).toStringAsFixed(1)}s',
        style: GoogleFonts.jetBrainsMono(fontSize: 12, color: AppColors.primary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(currentProjectProvider);
    final photos = project.photos;
    final texts = project.texts;
    final starts = _frameStarts(photos);
    final selectedIndex = ref.watch(selectedPhotoIndexProvider);
    final selectedText = ref.watch(selectedTextIndexProvider);
    final selectedKf = ref.watch(selectedKeyframeProvider);
    if (selectedKf != null &&
        (selectedKf[0] >= photos.length ||
            selectedKf[1] >= photos[selectedKf[0]].keyframes.length)) {
      Future.microtask(() => ref.read(selectedKeyframeProvider.notifier).state = null);
    }
    ref.listen<double>(playheadMsProvider, (_, next) {
      _playheadVN.value = next;
    });
    final isPlaying = ref.watch(isPlayingProvider);
    final notifier = ref.read(currentProjectProvider.notifier);
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

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
    final scrollOffset = _scroll.hasClients ? _scroll.offset : 0.0;

    final textMode = selectedText != null && selectedText < texts.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, size: 24),
          color: AppColors.textPrimary,
          tooltip: 'Свернуть',
          onPressed: () {
            ref.read(isPlayingProvider.notifier).state = false;
            Navigator.pop(context);
          },
        ),
        title: Text(
          'Таймлайн-студия',
          style: GoogleFonts.unbounded(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo, size: 20),
            color: notifier.canUndo ? AppColors.textPrimary : AppColors.textMuted.withValues(alpha: 0.3),
            tooltip: 'Отменить',
            onPressed: notifier.canUndo ? () => notifier.undo() : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo, size: 20),
            color: notifier.canRedo ? AppColors.textPrimary : AppColors.textMuted.withValues(alpha: 0.3),
            tooltip: 'Вернуть',
            onPressed: notifier.canRedo ? () => notifier.redo() : null,
          ),
          IconButton(
            icon: const Icon(Icons.check, size: 24),
            color: AppColors.primary,
            tooltip: 'Готово (сохранить)',
            onPressed: () async {
              ref.read(isPlayingProvider.notifier).state = false;
              await ref.read(projectRepositoryProvider).saveProject(ref.read(currentProjectProvider));
              ref.read(projectsProvider.notifier).refresh();
              if (mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: isLandscape ? 4 : 6),
            child: Row(
              children: [
                _AddChip(icon: Icons.add_photo_alternate_outlined, label: 'Фото', onTap: () {
                  ref.read(currentProjectProvider.notifier).addPhotosFromGallery();
                }),
                _AddChip(icon: Icons.text_fields, label: 'Текст', onTap: () {
                  showTextManagerSheet(context, ref);
                }),
                _AddChip(icon: Icons.music_note, label: 'Музыка', onTap: () {
                  showMusicSourcePicker(context, ref);
                }),
                _AddChip(icon: Icons.crop_free, label: 'Формат', onTap: () {
                  showFormatSheet(context, ref);
                }),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final double scale = (((constraints.maxHeight - 2) / (_baseTracksH - 2)).clamp(0.30, 1.0)).toDouble();
                      final double vH = _videoH * scale;
                      final double aH = _audioH * scale;
                      final double tH = _textH * scale;
                      final double tracksH = vH + aH + tH + 2;
                      final double topOffset = (((constraints.maxHeight - tracksH) / 2).clamp(0.0, constraints.maxHeight)).toDouble();

                      return Stack(
                        children: [
                          Positioned(
                            top: topOffset - 12,
                            left: 8, right: 8,
                            height: tracksH + 24,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF16181A),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                              ),
                            ),
                          ),
                          Positioned(
                            top: topOffset,
                            left: 0, right: 0,
                            height: tracksH,
                            child: SingleChildScrollView(
                              controller: _scroll,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: contentWidth,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildVideoTrack(photos, starts, vH),
                                    Container(height: 1, color: AppColors.divider),
                                    _buildAudioTrack(totalVideo, audioVisibleMs, aH),
                                    Container(height: 1, color: AppColors.divider),
                                    _buildTextTrack(texts, tH),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: topOffset,
                            left: 0, right: 0,
                            height: tracksH,
                            child: ValueListenableBuilder<double>(
                              valueListenable: _playheadVN,
                              builder: (context, ph, _) {
                                final x = _padLeft + ph * _pxPerMs - scrollOffset;
                                return IgnorePointer(
                                  child: CustomPaint(
                                    painter: _PlayheadPainter(x: x, color: AppColors.primary),
                                  ),
                                );
                              },
                            ),
                          ),
                          ValueListenableBuilder<double>(
                            valueListenable: _playheadVN,
                            builder: (context, ph, _) {
                              final x = _padLeft + ph * _pxPerMs - scrollOffset;
                              return Positioned(
                                top: topOffset - 28,
                                left: x - 18,
                                child: _PlayheadHandle(
                                  onDrag: (dx) {
                                    final next = (ph + dx / _pxPerMs).clamp(0.0, totalMs).toDouble();
                                    final now = DateTime.now().millisecondsSinceEpoch;
                                    if (now - _lastPlayheadVNUpdate >= 16) {
                                      _lastPlayheadVNUpdate = now;
                                      _playheadVN.value = next;
                                    }
                                  },
                                  onDragEnd: () {
                                    ref.read(playheadMsProvider.notifier).state = _playheadVN.value;
                                    _lastPlayheadVNUpdate = 0;
                                  },
                                ),
                              );
                            },
                          ),
                          Positioned(
                            top: topOffset,
                            left: 0,
                            height: tracksH,
                            child: Container(
                              width: _padLeft,
                              color: const Color(0xFF16181A).withOpacity(0.85),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(height: vH, child: const Center(child: Icon(Icons.videocam_outlined, size: 16, color: AppColors.textMuted))),
                                  SizedBox(height: aH, child: const Center(child: Icon(Icons.music_note, size: 16, color: AppColors.textMuted))),
                                  SizedBox(height: tH, child: const Center(child: Icon(Icons.text_fields, size: 16, color: AppColors.textMuted))),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (textMode || photos.isNotEmpty)
            Container(
              color: AppColors.surface,
              height: isLandscape ? 40 : 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                children: textMode
                    ? [
                        _CtxChip(icon: Icons.edit_outlined, label: 'Редактор', onTap: () => showTextManagerSheet(context, ref)),
                        _CtxChip(icon: Icons.content_copy, label: 'Дубль', onTap: () {
                          ref.read(currentProjectProvider.notifier).duplicateText(selectedText!);
                          HapticFeedback.lightImpact();
                        }),
                        _CtxChip(icon: Icons.delete_outline, label: 'Удалить', danger: true, onTap: () {
                          ref.read(currentProjectProvider.notifier).removeText(selectedText!);
                          ref.read(selectedTextIndexProvider.notifier).state = null;
                          HapticFeedback.lightImpact();
                        }),
                      ]
                    : [
                        _CtxChip(icon: Icons.diamond_outlined, label: '◆ Кейфрейм', onTap: _addKeyframeAtPlayhead),
                        if (ref.watch(selectedKeyframeProvider) != null)
                          _CtxChip(icon: Icons.diamond_outlined, label: 'Удалить ◆', danger: true, onTap: _removeSelectedKeyframe),
                        _CtxChip(icon: Icons.tune, label: 'Настройки', onTap: () => showPhotoSettingsSheet(context, ref, selectedIndex)),
                        _CtxChip(icon: Icons.palette_outlined, label: 'Фильтр', onTap: () => showEffectsSheet(context, ref, [selectedIndex])),
                        _CtxChip(icon: Icons.swap_horiz, label: 'Переход', onTap: () => showTransitionsSheet(context, ref, [selectedIndex])),
                        _CtxChip(icon: Icons.motion_photos_on, label: 'Движение', onTap: () => showLiveMotionSheet(context, ref)),
                        _CtxChip(icon: Icons.layers_outlined, label: 'Оверлей', onTap: () => showFrameOverlayPicker(context, ref, [selectedIndex], () {})),
                        _CtxChip(icon: Icons.crop, label: 'Кроп', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CropEditorScreen(photoIndex: selectedIndex)))),
                        _CtxChip(icon: Icons.content_copy, label: 'Дубль', onTap: () {
                          ref.read(currentProjectProvider.notifier).duplicatePhoto(selectedIndex);
                          HapticFeedback.lightImpact();
                        }),
                        _CtxChip(icon: Icons.content_cut, label: 'Разделить', onTap: _splitAtPlayhead),
                        _CtxChip(icon: Icons.delete_outline, label: 'Удалить', danger: true, onTap: () {
                          ref.read(currentProjectProvider.notifier).removePhoto(selectedIndex);
                          HapticFeedback.lightImpact();
                        }),
                      ],
              ),
            ),
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SafeArea(
              top: false,
              child: isLandscape
                  ? Row(
                      children: [
                        _TransportButton(icon: Icons.skip_previous, onTap: () {
                          ref.read(isPlayingProvider.notifier).state = false;
                          ref.read(playheadMsProvider.notifier).state = 0;
                          if (_scroll.hasClients) _scroll.jumpTo(0);
                        }),
                        const SizedBox(width: 6),
                        _TransportButton(icon: Icons.chevron_left, onTap: () => _stepFrame(-1)),
                        const SizedBox(width: 6),
                        _TransportButton(icon: isPlaying ? Icons.pause : Icons.play_arrow, accent: true, onTap: () => togglePlayback(ref)),
                        const SizedBox(width: 6),
                        _TransportButton(icon: Icons.chevron_right, onTap: () => _stepFrame(1)),
                        const SizedBox(width: 6),
                        _TransportButton(icon: Icons.skip_next, onTap: () {
                          ref.read(isPlayingProvider.notifier).state = false;
                          ref.read(playheadMsProvider.notifier).state = totalMs;
                          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
                        }),
                        const SizedBox(width: 12),
                        _playheadTimeLabel(totalMs),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.graphic_eq, size: 20, color: _showBeats ? AppColors.primary : AppColors.textMuted),
                          tooltip: _showBeats ? 'Скрыть биты' : 'Показать биты',
                          onPressed: () => setState(() => _showBeats = !_showBeats),
                        ),
                        const Icon(Icons.zoom_out, size: 18, color: AppColors.textMuted),
                        SizedBox(
                          width: 150,
                          child: Slider(
                            value: _sliderValue, min: 0.0, max: 1.0,
                            activeColor: AppColors.primary, inactiveColor: AppColors.surfaceLight,
                            onChanged: (v) => setState(() => _sliderValue = v),
                          ),
                        ),
                        const Icon(Icons.zoom_in, size: 18, color: AppColors.textMuted),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            _TransportButton(icon: Icons.skip_previous, onTap: () {
                              ref.read(isPlayingProvider.notifier).state = false;
                              ref.read(playheadMsProvider.notifier).state = 0;
                              if (_scroll.hasClients) _scroll.jumpTo(0);
                            }),
                            const SizedBox(width: 6),
                            _TransportButton(icon: Icons.chevron_left, onTap: () => _stepFrame(-1)),
                            const SizedBox(width: 6),
                            _TransportButton(icon: isPlaying ? Icons.pause : Icons.play_arrow, accent: true, onTap: () => togglePlayback(ref)),
                            const SizedBox(width: 6),
                            _TransportButton(icon: Icons.chevron_right, onTap: () => _stepFrame(1)),
                            const SizedBox(width: 6),
                            _TransportButton(icon: Icons.skip_next, onTap: () {
                              ref.read(isPlayingProvider.notifier).state = false;
                              ref.read(playheadMsProvider.notifier).state = totalMs;
                              if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
                            }),
                            const SizedBox(width: 12),
                            _playheadTimeLabel(totalMs),
                            const Spacer(),
                            IconButton(
                              icon: Icon(Icons.graphic_eq, size: 20, color: _showBeats ? AppColors.primary : AppColors.textMuted),
                              tooltip: _showBeats ? 'Скрыть биты' : 'Показать биты',
                              onPressed: () => setState(() => _showBeats = !_showBeats),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.zoom_out, size: 18, color: AppColors.textMuted),
                            Expanded(
                              child: Slider(
                                value: _sliderValue, min: 0.0, max: 1.0,
                                activeColor: AppColors.primary, inactiveColor: AppColors.surfaceLight,
                                onChanged: (v) => setState(() => _sliderValue = v),
                              ),
                            ),
                            const Icon(Icons.zoom_in, size: 18, color: AppColors.textMuted),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoTrack(List<PhotoLayer> photos, List<double> starts, double h) {
    return SizedBox(
      height: h,
      child: Stack(
        children: [
          for (int i = 0; i < photos.length; i++)
            Positioned(
              left: _padLeft + starts[i] * _pxPerMs,
              width: math.max(8.0, photos[i].durationMilliseconds * _pxPerMs - 2),
              top: 6, bottom: 6,
              child: LongPressDraggable<int>(
                data: i,
                feedback: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: math.max(40.0, photos[i].durationMilliseconds * _pxPerMs - 2),
                    height: h - 12,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(File(photos[i].imagePath), fit: BoxFit.cover),
                    ),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.3,
                  child: _videoBlock(photos, i, h, false),
                ),
                child: DragTarget<int>(
                  onWillAccept: (from) => from != null && from != i,
                  onAccept: (from) {
                    ref.read(currentProjectProvider.notifier).movePhoto(from, i);
                    HapticFeedback.mediumImpact();
                  },
                  builder: (ctx, cand, rej) => _videoBlock(photos, i, h, cand.isNotEmpty),
                ),
              ),
            ),
          for (int i = 1; i < photos.length; i++)
            Positioned(
              left: _padLeft + starts[i] * _pxPerMs - 11,
              top: (h / 2) - 11,
              width: 22, height: 22,
              child: _TransitionHandle(
                active: photos[i].transition != TransitionType.none,
                onTap: () => showTransitionsSheet(context, ref, [i]),
                onDragStart: () => ref.read(currentProjectProvider.notifier).beginBatch(),
                onDrag: (dx) {
                  final cur = photos[i].transitionDurationMs;
                  final next = (cur + dx / _pxPerMs).round().clamp(300, 1500);
                  ref.read(currentProjectProvider.notifier).updatePhotoTransitionDuration(i, next);
                },
                onDragEnd: () => ref.read(currentProjectProvider.notifier).endBatch(),
              ),
            ),
          if (_kfDragPhoto != null && _kfDragPhoto! < photos.length)
            Positioned(
              left: _padLeft + starts[_kfDragPhoto!] * _pxPerMs,
              width: math.max(8.0, photos[_kfDragPhoto!].durationMilliseconds * _pxPerMs - 2),
              top: 2, bottom: 2,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.aiAccent.withOpacity(0.8), width: 2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          for (int i = 0; i < photos.length; i++)
            for (int k = 0; k < photos[i].keyframes.length; k++)
              Positioned(
                left: _padLeft + (starts[i] + photos[i].keyframes[k].tMs) * _pxPerMs - 16,
                top: (h / 2) - 16,
                width: 32, height: 32,
                child: _KeyframeHandle(
                  selected: _isKeyframeSelected(i, k),
                  onTap: () {
                    ref.read(selectedKeyframeProvider.notifier).state = [i, k];
                    showKeyframeSheet(context, ref, i, k);
                  },
                  onDragStart: () {
                    ref.read(currentProjectProvider.notifier).beginBatch();
                    _kfPendingDx = 0;
                    _lastKfCommit = 0;
                    setState(() => _kfDragPhoto = i);
                  },
                  onDrag: (dx) {
                    _kfPendingDx += dx;
                    final now = DateTime.now().millisecondsSinceEpoch;
                    if (now - _lastKfCommit < 33) return;
                    _lastKfCommit = now;
                    final delta = _kfPendingDx;
                    _kfPendingDx = 0;
                    final kf = photos[i].keyframes[k];
                    final newT = (kf.tMs + delta / _pxPerMs)
                        .clamp(0.0, photos[i].durationMilliseconds.toDouble());
                    ref.read(currentProjectProvider.notifier)
                        .updateKeyframe(i, k, kf.copyWith(tMs: newT));
                  },
                  onDragEnd: () {
                    if (_kfPendingDx != 0) {
                      final kf = photos[i].keyframes[k];
                      final newT = (kf.tMs + _kfPendingDx / _pxPerMs)
                          .clamp(0.0, photos[i].durationMilliseconds.toDouble());
                      ref.read(currentProjectProvider.notifier)
                          .updateKeyframe(i, k, kf.copyWith(tMs: newT));
                      _kfPendingDx = 0;
                    }
                    ref.read(currentProjectProvider.notifier).normalizeKeyframes(i);
                    ref.read(currentProjectProvider.notifier).endBatch();
                    setState(() => _kfDragPhoto = null);
                  },
                ),
              ),
        ],
      ),
    );
  }

  Widget _videoBlock(List<PhotoLayer> photos, int i, double h, bool dropHighlight) {
    return _VideoBlock(
      photo: photos[i],
      isSelected: i == ref.watch(selectedPhotoIndexProvider),
      dropHighlight: dropHighlight,
      pxPerMs: _pxPerMs,
      onTap: () {
        ref.read(selectedPhotoIndexProvider.notifier).state = i;
        ref.read(selectedTextIndexProvider.notifier).state = null;
        ref.read(selectedKeyframeProvider.notifier).state = null;
      },
      onResizeStart: () => ref.read(currentProjectProvider.notifier).beginBatch(),
      onResize: (deltaMs) {
        final starts = _frameStarts(photos);
        final start = starts[i];
        double newDur = photos[i].durationMilliseconds + deltaMs;
        final boundary = start + newDur;
        final snapped = _snapToBeat(boundary, 12 / _pxPerMs);
        if ((snapped - boundary).abs() > 0.01) newDur = snapped - start;
        newDur = newDur.clamp(300.0, 10000.0).toDouble();
        ref.read(currentProjectProvider.notifier).updatePhotoDuration(i, newDur.round());
      },
      onResizeEnd: () => ref.read(currentProjectProvider.notifier).endBatch(),
    );
  }

  Widget _buildAudioTrack(double totalVideo, double audioVisibleMs, double h) {
    final track = ref.watch(currentProjectProvider).audioTrack;
    final wave = _visibleWave(audioVisibleMs);
    final offsetMs = _audioOffsetMs;
    final double blockLeft = _padLeft + offsetMs * _pxPerMs;
    final double blockWidth = math.max(8.0, (totalVideo - offsetMs) * _pxPerMs);
    final double pad = ((h * 0.07).clamp(2.0, 6.0)).toDouble();
    final compact = h < 50;

    return SizedBox(
      height: h,
      child: GestureDetector(
        onTap: () => showMusicSourcePicker(context, ref),
        onHorizontalDragStart: (_) => ref.read(currentProjectProvider.notifier).beginBatch(),
        onHorizontalDragUpdate: (d) {
          if (track == null) return;
          final cur = ref.read(currentProjectProvider).audioTrack?.startTime ?? 0;
          final next = (cur + (d.delta.dx / _pxPerMs) / 1000).clamp(0.0, totalVideo / 1000).toDouble();
          ref.read(currentProjectProvider.notifier).updateAudioStartTime(next);
        },
        onHorizontalDragEnd: (_) => ref.read(currentProjectProvider.notifier).endBatch(),
        child: Stack(
          children: [
            Positioned(
              left: blockLeft,
              width: blockWidth,
              top: pad, bottom: pad,
              child: Container(
                decoration: BoxDecoration(
                  color: track != null ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surfaceLight.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: track != null ? AppColors.primary.withValues(alpha: 0.4) : AppColors.surfaceLight),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Icon(track != null ? Icons.music_note : Icons.add,
                          color: track != null ? AppColors.primary : AppColors.textMuted,
                          size: compact ? 14 : 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(track?.title ?? 'Добавить музыку',
                                style: GoogleFonts.manrope(
                                    fontSize: compact ? 10 : 12,
                                    fontWeight: FontWeight.w600,
                                    color: track != null ? AppColors.textPrimary : AppColors.textMuted),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (track != null && !compact)
                                Text(
                                  '${(audioVisibleMs / 1000).toStringAsFixed(1)}s • Громкость ${(track.volume * 100).round()}%'
                                  '${offsetMs > 0 ? ' • старт +${(offsetMs / 1000).toStringAsFixed(1)}s' : ''}',
                                  style: GoogleFonts.manrope(fontSize: 10, color: AppColors.textMuted),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: AppColors.textMuted, size: compact ? 14 : 18),
                    ],
                  ),
                ),
              ),
            ),
            if (wave.isNotEmpty)
              Positioned(
                left: blockLeft,
                width: audioVisibleMs * _pxPerMs,
                top: 0, bottom: 0,
                child: IgnorePointer(
                  child: CustomPaint(painter: _WaveformPainter(wave: wave, color: AppColors.primary.withValues(alpha: 0.45))),
                ),
              ),
            if (_showBeats)
              for (int i = 0; i < _beats.length; i++)
                if (_beatMs(i) <= totalVideo)
                  Positioned(
                    left: _padLeft + _beatMs(i) * _pxPerMs - 6,
                    width: 12, top: 0, bottom: 0,
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
                        if (_editedBeats != null) BeatDetector.overrideBeats(track!.filePath, _editedBeats!);
                      },
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextTrack(List<TextLayer> texts, double h) {
    if (texts.isEmpty) {
      return SizedBox(
        height: h,
        child: Center(child: Text('Текста нет', style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textMuted))),
      );
    }
    final double pad = ((h * 0.17).clamp(2.0, 8.0)).toDouble();
    final selectedText = ref.watch(selectedTextIndexProvider);
    return SizedBox(
      height: h,
      child: Stack(
        children: [
          for (int i = 0; i < texts.length; i++)
            Positioned(
              left: _padLeft + texts[i].startTimeMilliseconds * _pxPerMs,
              width: math.max(24.0, (texts[i].endTimeMilliseconds - texts[i].startTimeMilliseconds) * _pxPerMs - 2),
              top: pad, bottom: pad,
              child: _TextBlock(
                label: texts[i].text,
                isSelected: selectedText == i,
                onTap: () => ref.read(selectedTextIndexProvider.notifier).state = i,
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
                onResizeStart: () => ref.read(currentProjectProvider.notifier).beginBatch(),
                onResizeLeft: (deltaMs) {
                  final clone = _cloneText(texts[i]);
                  final newStart = (clone.startTimeMilliseconds + deltaMs).round().clamp(0, clone.endTimeMilliseconds - 200);
                  clone.startTimeMilliseconds = newStart;
                  ref.read(currentProjectProvider.notifier).updateText(i, clone);
                },
                onResizeRight: (deltaMs) {
                  final clone = _cloneText(texts[i]);
                  final newEnd = (clone.endTimeMilliseconds + deltaMs).round().clamp(clone.startTimeMilliseconds + 200, 1000000);
                  clone.endTimeMilliseconds = newEnd;
                  ref.read(currentProjectProvider.notifier).updateText(i, clone);
                },
                onResizeEnd: () => ref.read(currentProjectProvider.notifier).endBatch(),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AddChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(label, style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CtxChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _CtxChip({required this.icon, required this.label, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(label, style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600, color: danger ? AppColors.error : AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool accent;
  const _TransportButton({required this.icon, required this.onTap, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: accent ? 44 : 32,
        height: 32,
        decoration: BoxDecoration(
          color: accent ? AppColors.primary : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, size: accent ? 20 : 18, color: accent ? Colors.white : AppColors.textPrimary),
      ),
    );
  }
}

class _TransitionHandle extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;
  const _TransitionHandle({required this.active, required this.onTap, required this.onDragStart, required this.onDrag, required this.onDragEnd});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onHorizontalDragStart: (_) => onDragStart(),
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      onHorizontalDragEnd: (_) => onDragEnd(),
      child: Container(
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.surfaceLight,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.6), width: 1.5),
        ),
        child: Icon(Icons.swap_horiz, size: 13, color: active ? Colors.white : AppColors.textMuted),
      ),
    );
  }
}

class _KeyframeHandle extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<double> onDrag;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  const _KeyframeHandle({
    required this.selected,
    required this.onTap,
    required this.onDrag,
    required this.onDragStart,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32, height: 32,
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          onHorizontalDragStart: (_) => onDragStart(),
          onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
          onHorizontalDragEnd: (_) => onDragEnd(),
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: selected ? AppColors.aiAccent : AppColors.primary,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: (selected ? AppColors.aiAccent : AppColors.primary).withOpacity(0.7),
                    blurRadius: selected ? 12 : 6,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoBlock extends StatefulWidget {
  final PhotoLayer photo;
  final bool isSelected;
  final bool dropHighlight;
  final double pxPerMs;
  final VoidCallback onTap;
  final VoidCallback onResizeStart;
  final ValueChanged<double> onResize;
  final VoidCallback onResizeEnd;

  const _VideoBlock({
    required this.photo, required this.isSelected, required this.pxPerMs,
    required this.onTap, required this.onResizeStart, required this.onResize, required this.onResizeEnd,
    this.dropHighlight = false,
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
          border: Border.all(
            color: widget.dropHighlight ? AppColors.aiAccent : (widget.isSelected ? AppColors.primary : Colors.transparent),
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              right: 10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(File(widget.photo.imagePath), fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 18)),
              ),
            ),
            Positioned(
              right: 0, top: 0, bottom: 0, width: 10,
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
      child: Center(child: Container(width: 1.5, height: double.infinity, color: AppColors.aiAccent.withOpacity(0.45))),
    );
  }
}

class _TextBlock extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onMoveStart;
  final ValueChanged<double> onMove;
  final VoidCallback onMoveEnd;
  final VoidCallback onResizeStart;
  final ValueChanged<double> onResizeLeft;
  final ValueChanged<double> onResizeRight;
  final VoidCallback onResizeEnd;

  const _TextBlock({
    required this.label, required this.onTap,
    required this.onMoveStart, required this.onMove, required this.onMoveEnd,
    required this.onResizeStart, required this.onResizeLeft, required this.onResizeRight, required this.onResizeEnd,
    this.isSelected = false,
  });

  @override
  State<_TextBlock> createState() => _TextBlockState();
}

class _TextBlockState extends State<_TextBlock> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onHorizontalDragStart: (_) => widget.onMoveStart(),
      onHorizontalDragUpdate: (d) => widget.onMove(d.delta.dx),
      onHorizontalDragEnd: (_) => widget.onMoveEnd(),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(widget.isSelected ? 0.4 : 0.25),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: widget.isSelected ? AppColors.primary : AppColors.primary.withOpacity(0.6), width: widget.isSelected ? 2 : 1),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              left: 8, right: 8,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(fontSize: 11, color: AppColors.textPrimary)),
              ),
            ),
            Positioned(
              left: 0, top: 0, bottom: 0, width: 8,
              child: GestureDetector(
                onHorizontalDragStart: (_) => widget.onResizeStart(),
                onHorizontalDragUpdate: (d) => widget.onResizeLeft(d.delta.dx),
                onHorizontalDragEnd: (_) => widget.onResizeEnd(),
                child: Container(color: AppColors.primary.withOpacity(0.5)),
              ),
            ),
            Positioned(
              right: 0, top: 0, bottom: 0, width: 8,
              child: GestureDetector(
                onHorizontalDragStart: (_) => widget.onResizeStart(),
                onHorizontalDragUpdate: (d) => widget.onResizeRight(d.delta.dx),
                onHorizontalDragEnd: (_) => widget.onResizeEnd(),
                child: Container(color: AppColors.primary.withOpacity(0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayheadHandle extends StatefulWidget {
  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;
  const _PlayheadHandle({required this.onDrag, this.onDragEnd});

  @override
  State<_PlayheadHandle> createState() => _PlayheadHandleState();
}

class _PlayheadHandleState extends State<_PlayheadHandle> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
      onHorizontalDragEnd: (_) => widget.onDragEnd?.call(),
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: AppColors.aiAccent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(color: AppColors.aiAccent.withOpacity(0.6), blurRadius: 10),
          ],
        ),
        child: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 28),
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
    final paint = Paint()..color = color..strokeWidth = 1.5;
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
    final paint = Paint()..color = color..strokeWidth = 2;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _PlayheadPainter old) => old.x != x;
}