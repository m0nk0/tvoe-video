import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/colors.dart';
import '../../../core/utils/cinematic_render.dart';
import '../../../core/utils/live_motion.dart';
import '../../../core/utils/overlay_render.dart';
import '../../../core/utils/photo_fit.dart';
import '../../../data/models/photo_layer.dart';
import '../../../data/models/text_layer.dart';
import '../../../data/models/video_project.dart';
import '../../../data/providers/project_provider.dart';
import '../playback.dart';
import '../text_tools.dart';
import 'transitions_render.dart';

class EditorPreviewArea extends ConsumerStatefulWidget {
  const EditorPreviewArea({super.key});

  @override
  ConsumerState<EditorPreviewArea> createState() => _EditorPreviewAreaState();
}

class _EditorPreviewAreaState extends ConsumerState<EditorPreviewArea> with SingleTickerProviderStateMixin {
  bool _showControls = false;
  Timer? _hideTimer;
  bool _isEditingText = false;
  late AnimationController _entranceController;

  ui.Size _imageSize = ui.Size.zero;
  String _loadedPath = '';
  final ValueNotifier<int> _overlayTimeMs = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _entranceController.dispose();
    _overlayTimeMs.dispose();
    super.dispose();
  }

  Future<void> _loadSize(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final completer = Completer<ui.Size>();
      ui.decodeImageFromList(bytes, (img) {
        if (!completer.isCompleted) completer.complete(ui.Size(img.width.toDouble(), img.height.toDouble()));
      });
      final size = await completer.future.timeout(const Duration(seconds: 3), onTimeout: () => const ui.Size(1, 1));
      if (mounted && _loadedPath == path) setState(() => _imageSize = size);
    } catch (e) {
      print('⚠️ Превью: не удалось прочитать размер фото: $e');
    }
  }

  void _ensureSize(String path) {
    if (_loadedPath == path) return;
    _loadedPath = path;
    _imageSize = ui.Size.zero;
    _loadSize(path);
  }

  void _showControlsTemporarily() {
    setState(() { _showControls = true; });
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() { _showControls = false; });
    });
  }

  void _togglePlay() {
    if (_isEditingText) setState(() => _isEditingText = false);
    togglePlayback(ref);
    _showControlsTemporarily();
  }

  void _onStep(int delta) {
    stepPlayback(ref, delta);
    _showControlsTemporarily();
  }

  void _toggleTextEditing() {
    setState(() {
      _isEditingText = !_isEditingText;
      if (_isEditingText) { _showControls = true; _hideTimer?.cancel(); }
    });
  }

  void _updateTextPosition(int index, double x, double y) {
    final project = ref.read(currentProjectProvider);
    if (index >= project.texts.length) return;
    final text = project.texts[index];
    final updated = TextLayer(
      text: text.text, fontFamily: text.fontFamily, fontSize: text.fontSize, colorValue: text.colorValue,
      startTimeMilliseconds: text.startTimeMilliseconds, endTimeMilliseconds: text.endTimeMilliseconds,
      animation: text.animation, positionX: x, positionY: y,
    );
    ref.read(currentProjectProvider.notifier).updateText(index, updated);
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(currentProjectProvider);
    final selectedIndex = ref.watch(selectedPhotoIndexProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final hasPhotos = project.photos.isNotEmpty;
    final safeIndex = hasPhotos ? selectedIndex.clamp(0, project.photos.length - 1) : 0;
    final currentPhoto = hasPhotos ? project.photos[safeIndex] : null;
    final currentTransition = currentPhoto?.transition ?? TransitionType.none;
    final currentFilter = currentPhoto?.filter;
    final overlayType = project.overlayType;
    final overlayIntensity = project.overlayIntensity;
    final liveMotion = currentPhoto?.liveMotion ?? LiveMotion.none;
    final cinematicIntensity = project.cinematicIntensity;

    if (currentPhoto != null) _ensureSize(currentPhoto.imagePath);

    ref.listen<double>(playheadMsProvider, (prev, ms) {
      final newMs = ms.toInt();
      if (_overlayTimeMs.value != newMs) _overlayTimeMs.value = newMs;
    });

    ref.listen<int>(selectedPhotoIndexProvider, (prev, next) {
      if (prev != next && hasPhotos) {
        final photo = project.photos[next];
        _entranceController.duration = Duration(milliseconds: photo.entranceDurationMs);
        _entranceController.forward(from: 0);
      }
    });

    final frameDurationMs = currentPhoto?.durationMilliseconds ?? 3000;
    final playheadMs = ref.watch(playheadMsProvider);
    final segmentStartMs = hasPhotos ? project.photos.sublist(0, safeIndex).fold<int>(0, (s, p) => s + p.durationMilliseconds) : 0;
    final elapsedInSegment = (playheadMs - segmentStartMs).clamp(0.0, frameDurationMs.toDouble());
    final frameProgress = elapsedInSegment / frameDurationMs;
    final liveT = frameProgress.clamp(0.0, 1.0);

    return Center(
      child: Row(
        children: [
          _PreviewArrow(icon: Icons.chevron_left, enabled: hasPhotos && safeIndex > 0, onTap: () => _onStep(-1)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AspectRatio(
                aspectRatio: project.format.aspectRatio,
                child: Container(
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 2)),
                  child: !hasPhotos
                      ? const Center(child: Icon(Icons.crop_portrait, size: 64, color: AppColors.textMuted))
                      : GestureDetector(
                          onTap: _showControlsTemporarily,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Positioned.fill(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 450),
                                    switchInCurve: Curves.easeOut,
                                    switchOutCurve: Curves.easeIn,
                                    transitionBuilder: (child, animation) => buildTransition(child, animation, currentTransition),
                                    child: SizedBox.expand(
                                      key: ValueKey('${currentPhoto!.imagePath}_$safeIndex'),
                                      child: AnimatedBuilder(
                                        animation: _entranceController,
                                        builder: (context, child) => applyEntranceAnimation(currentPhoto.entranceAnimation, _entranceController, child!),
                                        child: ColorFiltered(
                                          colorFilter: ColorFilter.matrix(FilterPresets.matrix(currentFilter)),
                                          child: LayoutBuilder(
                                            builder: (context, constraints) {
                                              final canvas = Size(constraints.maxWidth, constraints.maxHeight);
                                              final dst = _imageSize == ui.Size.zero ? null : PhotoFitCalculator.dstRect(
                                                image: _imageSize, canvas: canvas, fitMode: currentPhoto.fitMode,
                                                scale: currentPhoto.scale, offsetX: currentPhoto.offsetX, offsetY: currentPhoto.offsetY,
                                              );

                                              if (dst == null) return const SizedBox.expand();

                                              final cinematicResult = applyLiveMotionWithCinematic(dst, liveMotion, liveT, intensity: cinematicIntensity);
                                              final liveDst = cinematicResult.rect;
                                              final cinematicParams = cinematicResult.params;

                                              return Stack(
                                                children: [
                                                  if (currentPhoto.fitMode == FitMode.contain)
                                                    Positioned.fill(
                                                      child: currentPhoto.backgroundType == BackgroundType.blur
                                                          ? _buildBlurBackground(currentPhoto)
                                                          : Container(color: Color(currentPhoto.backgroundColor)),
                                                    ),
                                                  Positioned(
                                                    left: liveDst.left,
                                                    top: liveDst.top,
                                                    width: liveDst.width,
                                                    height: liveDst.height,
                                                    child: 
                                                    // 🎨 НОВОЕ: Применяем матрицу гармонизации, если она есть в модели
                                                    currentPhoto.harmonizationMatrix != null
                                                        ? ColorFiltered(
                                                            colorFilter: ColorFilter.matrix(currentPhoto.harmonizationMatrix!),
                                                            child: Image.file(File(currentPhoto.imagePath), fit: BoxFit.fill, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: AppColors.error))),
                                                          )
                                                        : Image.file(File(currentPhoto.imagePath), fit: BoxFit.fill, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: AppColors.error))),
                                                  ),
                                                  if (cinematicIntensity > 0.01)
                                                    Positioned.fill(
                                                      child: IgnorePointer(
                                                        child: CustomPaint(painter: _CinematicPainter(params: cinematicParams)),
                                                      ),
                                                    ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                ...buildTextOverlays(project, safeIndex, isEditing: _isEditingText, onPositionChanged: _updateTextPosition),
                                if (overlayType != OverlayType.none)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: ValueListenableBuilder<int>(
                                        valueListenable: _overlayTimeMs,
                                        builder: (context, timeMs, _) => CustomPaint(painter: _OverlayPainter(type: overlayType, timeMs: timeMs, intensity: overlayIntensity)),
                                      ),
                                    ),
                                  ),
                                if (_isEditingText)
                                  Positioned(
                                    top: 16, left: 16,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(color: Colors.yellow.withOpacity(0.9), borderRadius: BorderRadius.circular(20)),
                                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.drag_indicator, size: 16, color: Colors.black),
                                        SizedBox(width: 6),
                                        Text('Перетащите текст', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black)),
                                      ]),
                                    ),
                                  ),
                                if (_showControls)
                                  Center(
                                    child: AnimatedOpacity(
                                      opacity: _showControls ? 1.0 : 0.0,
                                      duration: const Duration(milliseconds: 200),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(40)),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(icon: const Icon(Icons.skip_previous, color: Colors.white, size: 28), disabledColor: AppColors.textMuted.withValues(alpha: 0.3), onPressed: safeIndex > 0 ? () => _onStep(-1) : null),
                                            IconButton(icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 36), onPressed: _togglePlay),
                                            IconButton(icon: const Icon(Icons.skip_next, color: Colors.white, size: 28), disabledColor: AppColors.textMuted.withValues(alpha: 0.3), onPressed: safeIndex < project.photos.length - 1 ? () => _onStep(1) : null),
                                            const SizedBox(width: 8),
                                            IconButton(icon: Icon(_isEditingText ? Icons.check : Icons.text_fields, color: _isEditingText ? Colors.yellow : Colors.white, size: 28), onPressed: _toggleTextEditing),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
          _PreviewArrow(icon: Icons.chevron_right, enabled: hasPhotos && safeIndex < project.photos.length - 1, onTap: () => _onStep(1)),
        ],
      ),
    );
  }

  Widget _buildBlurBackground(PhotoLayer photo) {
    return Stack(
      children: [
        Positioned.fill(child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: Image.file(File(photo.imagePath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()))),
        Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.25))),
      ],
    );
  }
}

class _PreviewArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _PreviewArrow({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, border: Border.all(color: enabled ? AppColors.primary.withValues(alpha: 0.4) : AppColors.primary.withValues(alpha: 0.1))),
          child: Icon(icon, color: enabled ? AppColors.primary : AppColors.textMuted.withValues(alpha: 0.3), size: 28),
        ),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final OverlayType type;
  final int timeMs;
  final double intensity;
  _OverlayPainter({required this.type, required this.timeMs, required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    paintOverlay(canvas, type, timeMs, size.width.toInt(), size.height.toInt(), intensity);
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) => old.type != type || old.timeMs != timeMs || old.intensity != intensity;
}

class _CinematicPainter extends CustomPainter {
  final CinematicParams params;
  _CinematicPainter({required this.params});

  @override
  void paint(Canvas canvas, Size size) {
    paintCinematicEffects(canvas, params, size.width.toInt(), size.height.toInt());
  }

  @override
  bool shouldRepaint(covariant _CinematicPainter old) => old.params != params;
}