import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/colors.dart';
import '../../../core/utils/photo_fit.dart';
import '../../../data/models/photo_layer.dart';
import '../../../data/providers/project_provider.dart';
import '../../../data/providers/selection_provider.dart';
import '../playback.dart';
import '../sheets/photo_settings_sheet.dart';

// ==========================================
// Таймлайн: непрерывный плейхед (в мс)
// ✅ Режим мультивыбора кадров
// ==========================================
class EditorTimeline extends ConsumerStatefulWidget {
  final double zoom;
  final ValueChanged<double> onZoomChanged;

  const EditorTimeline({
    super.key,
    required this.zoom,
    required this.onZoomChanged,
  });

  @override
  ConsumerState<EditorTimeline> createState() => _EditorTimelineState();
}

class _EditorTimelineState extends ConsumerState<EditorTimeline> {
  final ScrollController _controller = ScrollController();
  bool _scrubbing = false;

  static const double _padLeft = 40.0;

  double get _pxPerMs => (80 / 3000) * widget.zoom;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _widthOf(PhotoLayer p) =>
      (p.durationMilliseconds * _pxPerMs).clamp(48.0, 400.0);

  double _xForMs(List<PhotoLayer> photos, double ms) {
    double x = _padLeft;
    for (int i = 0; i < photos.length; i++) {
      final w = _widthOf(photos[i]);
      final d = photos[i].durationMilliseconds.toDouble();
      if (ms <= d) {
        return x + (d > 0 ? (ms / d) * w : 0);
      }
      x += w;
      ms -= d;
    }
    return x;
  }

  double _msPerPxAt(List<PhotoLayer> photos, double ms) {
    if (photos.isEmpty) return 0;
    final idx = frameIndexForMs(photos, ms.round());
    final p = photos[idx];
    final w = _widthOf(p);
    if (w <= 0) return 0;
    return p.durationMilliseconds / w;
  }

  void _followPlayhead(double xContent, bool active) {
    if (!active || !_controller.hasClients) return;
    final vp = _controller.position.viewportDimension;
    final max = _controller.position.maxScrollExtent;
    final xs = xContent - _controller.offset;
    if (xs > vp - 24) {
      _controller
          .jumpTo((_controller.offset + (xs - (vp - 24))).clamp(0.0, max));
    } else if (xs < 24 && _controller.offset > 0) {
      _controller.jumpTo((_controller.offset + (xs - 24)).clamp(0.0, max));
    }
  }

  void _goStart() {
    ref.read(isPlayingProvider.notifier).state = false;
    ref.read(playheadMsProvider.notifier).state = 0;
    if (_controller.hasClients) _controller.jumpTo(0);
    setState(() {});
  }

  void _goEnd() {
    ref.read(isPlayingProvider.notifier).state = false;
    final photos = ref.read(currentProjectProvider).photos;
    final total =
        photos.fold<int>(0, (s, p) => s + p.durationMilliseconds).toDouble();
    ref.read(playheadMsProvider.notifier).state = total;
    if (_controller.hasClients) {
      _controller.jumpTo(_controller.position.maxScrollExtent);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<double>(playheadMsProvider, (prev, ms) {
      final photos = ref.read(currentProjectProvider).photos;
      if (photos.isEmpty) return;
      final idx = frameIndexForMs(photos, ms.round());
      if (idx != ref.read(selectedPhotoIndexProvider)) {
        ref.read(selectedPhotoIndexProvider.notifier).state = idx;
      }
      _followPlayhead(
          _xForMs(photos, ms), ref.read(isPlayingProvider) || _scrubbing);
      setState(() {});
    });

    final project = ref.watch(currentProjectProvider);
    final selectedIndex = ref.watch(selectedPhotoIndexProvider);
    final playheadMs = ref.watch(playheadMsProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final isSelection = ref.watch(isSelectionModeProvider);
    final selectedFrames = ref.watch(selectedFramesProvider);
    final totalMs =
        project.photos.fold<int>(0, (sum, p) => sum + p.durationMilliseconds);
    final offset = _controller.hasClients ? _controller.offset : 0.0;
    final xScreen = _xForMs(project.photos, playheadMs) - offset;

    return Column(
      children: [
        // ==========================================
        // Шапка: плеер ИЛИ панель выделения
        // ==========================================
        SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: isSelection
                ? Row(
                    children: [
                      _EdgeButton(
                        icon: Icons.close,
                        onTap: () => SelectionController(ref).exit(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Center(
                          child: Text(
                            'Выбрано: ${selectedFrames.length}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      // ✅ КНОПКА "ДЛИТЕЛЬНОСТЬ ВЫБРАННЫХ"
                      Tooltip(
                        message: 'Длительность выбранных кадров',
                        child: _EdgeButton(
                          icon: Icons.timer_outlined,
                          onTap: () {
                            if (selectedFrames.isEmpty) return;
                            final sorted = selectedFrames.toList()..sort();
                            showPhotoSettingsSheet(context, ref, sorted.first);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => SelectionController(ref)
                            .selectAll(project.photos.length),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.primary
                                    .withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            'Все',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => SelectionController(ref).clear(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.primary
                                    .withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            'Сброс',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      _EdgeButton(icon: Icons.first_page, onTap: _goStart),
                      Expanded(
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => togglePlayback(ref),
                                child: Container(
                                  width: 34,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isPlaying ? Icons.pause : Icons.play_arrow,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '${_fmtMs(playheadMs.round())} / ${_fmtMs(totalMs)}',
                                style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // ✅ Кнопка входа в режим выделения (с подсказкой)
                      Tooltip(
                        message: 'Выбрать несколько кадров',
                        child: GestureDetector(
                          onTap: () {
                            if (project.photos.isEmpty) return;
                            SelectionController(ref).enter(selectedIndex);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Отмечайте кадры тапом. ⏱ — длительность для всех, ✕ — выход'),
                                duration: Duration(seconds: 3),
                              ),
                            );
                          },
                          child: Container(
                            width: 40,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.3)),
                            ),
                            child: const Icon(Icons.checklist,
                                size: 16, color: AppColors.primary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ZoomControl(
                          zoom: widget.zoom, onZoomChanged: widget.onZoomChanged),
                      const SizedBox(width: 8),
                      _EdgeButton(icon: Icons.last_page, onTap: _goEnd),
                    ],
                  ),
          ),
        ),

        Expanded(
          child: Stack(
            children: [
              if (project.photos.isEmpty)
                Center(
                  child: Text(
                    'Нажмите "Фото", чтобы добавить изображения',
                    style: GoogleFonts.manrope(
                        color: AppColors.textMuted, fontSize: 14),
                  ),
                )
              else
                ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  scrollController: _controller,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  itemCount: project.photos.length,
                  onReorder: (oldIndex, newIndex) => ref
                      .read(currentProjectProvider.notifier)
                      .reorderPhotos(oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final photo = project.photos[index];
                    return _TimelineItem(
                      key: ValueKey('${photo.imagePath}_$index'),
                      photo: photo,
                      isSelected: index == selectedIndex,
                      selectionMode: isSelection,
                      isChecked: selectedFrames.contains(index),
                      width: _widthOf(photo),
                      onTap: () {
                        if (isSelection) {
                          // ✅ В режиме выделения — переключаем галочку
                          SelectionController(ref).toggle(index);
                        } else {
                          ref.read(selectedPhotoIndexProvider.notifier).state =
                              index;
                          ref.read(playheadMsProvider.notifier).state =
                              frameStartMs(project.photos, index).toDouble();
                          showPhotoSettingsSheet(context, ref, index);
                        }
                      },
                    );
                  },
                ),

              if (project.photos.isNotEmpty && !isSelection)
                Positioned(
                  left: xScreen - 12,
                  width: 24,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onHorizontalDragStart: (_) => _scrubbing = true,
                    onHorizontalDragUpdate: (details) {
                      final photos = ref.read(currentProjectProvider).photos;
                      if (photos.isEmpty) return;
                      final ms = ref.read(playheadMsProvider);
                      final deltaMs = details.delta.dx * _msPerPxAt(photos, ms);
                      ref.read(playheadMsProvider.notifier).state =
                          (ms + deltaMs).clamp(0.0, totalMs.toDouble());
                    },
                    onHorizontalDragEnd: (_) => _scrubbing = false,
                    child: Container(
                      color: Colors.transparent,
                      child: Column(
                        children: [
                          CustomPaint(
                            size: const Size(16, 12),
                            painter: _TrianglePainter(color: AppColors.primary),
                          ),
                          Expanded(
                            child: Container(width: 2, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ==========================================
// Вспомогательные виджеты таймлайна
// ==========================================
class _EdgeButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _EdgeButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, size: 18, color: AppColors.primary),
      ),
    );
  }
}

class _ZoomControl extends StatelessWidget {
  final double zoom;
  final ValueChanged<double> onZoomChanged;

  const _ZoomControl({required this.zoom, required this.onZoomChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.remove, color: AppColors.textMuted, size: 14),
          SizedBox(
            width: 56,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: AppColors.surfaceLight,
                thumbColor: AppColors.primary,
                overlayColor: AppColors.primary.withValues(alpha: 0.2),
              ),
              child: Slider(
                  value: zoom, min: 0.8, max: 1.3, onChanged: onZoomChanged),
            ),
          ),
          const Icon(Icons.add, color: AppColors.textMuted, size: 14),
        ],
      ),
    );
  }
}

String _fmtMs(int ms) {
  final d = Duration(milliseconds: ms);
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

// ==========================================
// Миниатюра кадра (с галочкой в режиме выделения)
// ==========================================
class _TimelineItem extends StatelessWidget {
  final PhotoLayer photo;
  final bool isSelected;
  final bool selectionMode;
  final bool isChecked;
  final double width;
  final VoidCallback onTap;

  const _TimelineItem({
    super.key,
    required this.photo,
    required this.isSelected,
    required this.selectionMode,
    required this.isChecked,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: width,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selectionMode
                      ? (isChecked ? AppColors.primary : Colors.transparent)
                      : (isSelected ? AppColors.primary : Colors.transparent),
                  width: 2,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Opacity(
                      opacity: selectionMode && !isChecked ? 0.45 : 1.0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: _FittedThumb(photo: photo),
                      ),
                    ),
                  ),
                  // ✅ Галочка в режиме выделения
                  if (selectionMode)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: isChecked ? AppColors.primary : Colors.black54,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: isChecked
                            ? const Icon(Icons.check,
                                size: 14, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(photo.durationMilliseconds / 1000).toStringAsFixed(1)}s',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: isSelected && !selectionMode
                    ? AppColors.primary
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// Миниатюра с учётом кропа/вписывания и фильтра
// ==========================================
class _FittedThumb extends StatefulWidget {
  final PhotoLayer photo;

  const _FittedThumb({required this.photo});

  @override
  State<_FittedThumb> createState() => _FittedThumbState();
}

class _FittedThumbState extends State<_FittedThumb> {
  ui.Size _size = ui.Size.zero;
  String _loadedPath = '';

  @override
  void initState() {
    super.initState();
    _load(widget.photo.imagePath);
  }

  @override
  void didUpdateWidget(covariant _FittedThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.imagePath != widget.photo.imagePath) {
      _load(widget.photo.imagePath);
    }
  }

  Future<void> _load(String path) async {
    _loadedPath = path;
    try {
      final bytes = await File(path).readAsBytes();
      final completer = Completer<ui.Size>();
      ui.decodeImageFromList(bytes, (img) {
        if (!completer.isCompleted) {
          completer.complete(
              ui.Size(img.width.toDouble(), img.height.toDouble()));
        }
      });
      final size = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => const ui.Size(1, 1),
      );
      if (mounted && _loadedPath == path) {
        setState(() => _size = size);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;

    return ColorFiltered(
      colorFilter: ColorFilter.matrix(FilterPresets.matrix(photo.filter)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvas = Size(constraints.maxWidth, constraints.maxHeight);

          if (_size == ui.Size.zero) {
            return Image.file(
              File(photo.imagePath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: AppColors.error),
            );
          }

          final dst = PhotoFitCalculator.dstRect(
            image: _size,
            canvas: canvas,
            fitMode: photo.fitMode,
            scale: photo.scale,
            offsetX: photo.offsetX,
            offsetY: photo.offsetY,
          );

          return Stack(
            children: [
              if (photo.fitMode == FitMode.contain)
                Positioned.fill(
                  child: Container(
                    color: photo.backgroundType == BackgroundType.color
                        ? Color(photo.backgroundColor)
                        : AppColors.surface,
                  ),
                ),
              Positioned(
                left: dst.left,
                top: dst.top,
                width: dst.width,
                height: dst.height,
                child: Image.file(
                  File(photo.imagePath),
                  fit: BoxFit.fill,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image, color: AppColors.error),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ==========================================
// Треугольник плейхеда (исправлено)
// ==========================================
class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}