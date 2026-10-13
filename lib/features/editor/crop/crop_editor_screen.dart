import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/colors.dart';
import '../../../core/utils/photo_fit.dart';
import '../../../core/utils/smart_crop.dart';
import '../../../data/models/photo_layer.dart';
import '../../../data/providers/project_provider.dart';

class CropEditorScreen extends ConsumerStatefulWidget {
  final int photoIndex;

  const CropEditorScreen({super.key, required this.photoIndex});

  @override
  ConsumerState<CropEditorScreen> createState() => _CropEditorScreenState();
}

class _CropEditorScreenState extends ConsumerState<CropEditorScreen> {
  ui.Size _imageSize = ui.Size.zero;
  Size _lastCanvas = Size.zero;

  late FitMode _fitMode;
  late double _scale;
  late double _offsetX;
  late double _offsetY;
  late BackgroundType _backgroundType;
  late int _backgroundColor;

  double _panBaseX = 0;
  double _panBaseY = 0;
  double _scaleBase = 1;
  Offset _startFocal = Offset.zero;

  bool _showZoomBadge = false;
  Timer? _zoomBadgeTimer;

  bool _isSmartCropping = false;

  static const List<int> _palette = [
    0xFF000000,
    0xFFFFFFFF,
    0xFF808080,
    0xFF1A1025,
    0xFF2D1B3D,
    0xFFD640F0,
  ];

  static const double _minScale = 0.5;
  static const double _maxScale = 3.0;

  @override
  void initState() {
    super.initState();
    final photo = ref.read(currentProjectProvider).photos[widget.photoIndex];
    _fitMode = photo.fitMode;
    _scale = photo.fitMode == FitMode.cover ? 1.0 : photo.scale;
    _offsetX = photo.offsetX;
    _offsetY = photo.offsetY;
    _backgroundType = photo.backgroundType;
    _backgroundColor = photo.backgroundColor;
    _loadSize(photo.imagePath);
  }

  @override
  void dispose() {
    _zoomBadgeTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSize(String path) async {
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
      if (mounted) setState(() => _imageSize = size);
    } catch (e) {
      print('⚠️ Кроп: не удалось прочитать размер фото: $e');
    }
  }

  void _save() {
    ref.read(currentProjectProvider.notifier).updatePhotoFit(
          index: widget.photoIndex,
          fitMode: _fitMode,
          scale: _fitMode == FitMode.cover ? 1.0 : _scale,
          offsetX: _offsetX,
          offsetY: _offsetY,
          backgroundType: _backgroundType,
          backgroundColor: _backgroundColor,
        );
    Navigator.pop(context);
  }

  void _reset() {
    setState(() {
      _scale = 1.0;
      _offsetX = 0.0;
      _offsetY = 0.0;
    });
  }

  // ==========================================
  // 🤖 Умное кадрирование: центрирование лиц
  // ==========================================
  Future<void> _smartCrop() async {
    if (_imageSize == ui.Size.zero || _lastCanvas == Size.zero) return;

    final photo =
        ref.read(currentProjectProvider).photos[widget.photoIndex];

    setState(() => _isSmartCropping = true);

    try {
      final result = await SmartCropService.computeCoverOffsets(
        imagePath: photo.imagePath,
        imageSize: Size(_imageSize.width, _imageSize.height),
        canvas: _lastCanvas,
      );

      if (!mounted) return;

      setState(() {
        _offsetX = result.offsetX;
        _offsetY = result.offsetY;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.faceFound
                ? '🤖 Лица центрированы (лиц: ${result.faceCount})'
                : '🤖 Лица не найдены — оставил как есть',
          ),
          backgroundColor: result.faceFound ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('⚠️ SmartCrop ошибка: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось проанализировать фото'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSmartCropping = false);
    }
  }

  // ==========================================
  // Жесты: panBase + startFocal для корректного накопления
  // ==========================================
  void _onScaleStart(ScaleStartDetails details) {
    _panBaseX = _offsetX;
    _panBaseY = _offsetY;
    _scaleBase = _scale;
    _startFocal = details.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size canvas) {
    if (_imageSize == ui.Size.zero) return;

    setState(() {
      final isPinch = details.pointerCount >= 2;

      // ✅ ПОЛНОЕ смещение пальца от начала жеста
      final totalDx = details.focalPoint.dx - _startFocal.dx;
      final totalDy = details.focalPoint.dy - _startFocal.dy;

      if (_fitMode == FitMode.cover) {
        // ✅ COVER: только панорама, без зума
        final base = PhotoFitCalculator.coverScale(
            image: _imageSize, canvas: canvas);
        final drawW = _imageSize.width * base;
        final drawH = _imageSize.height * base;
        final freeX = (canvas.width - drawW).abs() / 2;
        final freeY = (canvas.height - drawH).abs() / 2;

        if (freeX > 1) {
          _offsetX = (_panBaseX + totalDx / freeX).clamp(-1.0, 1.0);
        }
        if (freeY > 1) {
          _offsetY = (_panBaseY + totalDy / freeY).clamp(-1.0, 1.0);
        }
      } else {
        // ✅ CONTAIN: зум (2 пальца) + панорама (1 палец)
        if (isPinch) {
          _scale = (_scaleBase * details.scale).clamp(_minScale, _maxScale);
          _showZoomBadge = true;
          _zoomBadgeTimer?.cancel();
          _zoomBadgeTimer = Timer(const Duration(milliseconds: 800), () {
            if (mounted) setState(() => _showZoomBadge = false);
          });
          return;
        }

        final base = PhotoFitCalculator.fitScale(
            image: _imageSize, canvas: canvas);
        final drawW = _imageSize.width * base * _scale;
        final drawH = _imageSize.height * base * _scale;
        final freeX = (canvas.width - drawW).abs() / 2;
        final freeY = (canvas.height - drawH).abs() / 2;

        if (freeX > 1) {
          _offsetX = (_panBaseX + totalDx / freeX).clamp(-1.0, 1.0);
        }
        if (freeY > 1) {
          _offsetY = (_panBaseY + totalDy / freeY).clamp(-1.0, 1.0);
        }
      }
    });
  }

  // ==========================================
  // Кнопки позиционирования (contain)
  // ==========================================
  void _setPosition(double x, double y) {
    setState(() {
      _offsetX = x.clamp(-1.0, 1.0);
      _offsetY = y.clamp(-1.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(currentProjectProvider);
    final photos = project.photos;
    if (widget.photoIndex >= photos.length) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final photo = photos[widget.photoIndex];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          'Кадрирование',
          style: GoogleFonts.unbounded(
              fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              'Готово',
              style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AspectRatio(
                    aspectRatio: project.format.aspectRatio,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final canvas = Size(
                            constraints.maxWidth, constraints.maxHeight);
                        _lastCanvas = canvas;

                        final dst = _imageSize == ui.Size.zero
                            ? Rect.zero
                            : PhotoFitCalculator.dstRect(
                                image: _imageSize,
                                canvas: canvas,
                                fitMode: _fitMode,
                                scale:
                                    _fitMode == FitMode.cover ? 1.0 : _scale,
                                offsetX: _offsetX,
                                offsetY: _offsetY,
                              );

                        return GestureDetector(
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: (d) => _onScaleUpdate(d, canvas),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.4),
                                  width: 2),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Stack(
                                children: [
                                  // ✅ Подложка только в contain
                                  if (_fitMode == FitMode.contain)
                                    Positioned.fill(
                                      child: _backgroundType ==
                                              BackgroundType.blur
                                          ? _buildBlurBackground(photo)
                                          : Container(
                                              color: Color(_backgroundColor)),
                                    ),

                                  if (dst != Rect.zero)
                                    Positioned(
                                      left: dst.left,
                                      top: dst.top,
                                      width: dst.width,
                                      height: dst.height,
                                      child: Image.file(
                                        File(photo.imagePath),
                                        fit: BoxFit.fill,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.broken_image,
                                                color: AppColors.error),
                                      ),
                                    ),

                                  if (_showZoomBadge &&
                                      _fitMode == FitMode.contain)
                                    Positioned(
                                      top: 12,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 14, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.black
                                                .withValues(alpha: 0.75),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            '×${_scale.toStringAsFixed(2)}',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                  Positioned(
                                    bottom: 8,
                                    left: 0,
                                    right: 0,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.5),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          _fitMode == FitMode.cover
                                              ? 'Двигай пальцем — выбирай область'
                                              : '2 пальца — зум · 1 палец — двигай',
                                          style: GoogleFonts.manrope(
                                              fontSize: 11,
                                              color: Colors.white70),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Выбор режима
                  Row(
                    children: [
                      Expanded(
                        child: _ModeButton(
                          label: 'Заполнить',
                          icon: Icons.crop_free,
                          isActive: _fitMode == FitMode.cover,
                          onTap: () => setState(() {
                            _fitMode = FitMode.cover;
                            _scale = 1.0;
                            _offsetX = 0.0;
                            _offsetY = 0.0;
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ModeButton(
                          label: 'Вписать',
                          icon: Icons.crop_original,
                          isActive: _fitMode == FitMode.contain,
                          onTap: () => setState(() {
                            _fitMode = FitMode.contain;
                            _scale = 1.0;
                            _offsetX = 0.0;
                            _offsetY = 0.0;
                          }),
                        ),
                      ),
                    ],
                  ),

                  // ✅ COVER: кнопка умного кадрирования
                  if (_fitMode == FitMode.cover) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSmartCropping ? null : _smartCrop,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _isSmartCropping
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.auto_awesome, size: 18),
                        label: Text(
                          _isSmartCropping
                              ? 'Анализирую...'
                              : 'AI: центрировать лица',
                          style: GoogleFonts.manrope(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],

                  // ✅ CONTAIN: зум + кнопки позиционирования + подложка
                  if (_fitMode == FitMode.contain) ...[
                    const SizedBox(height: 12),
                    // Зум
                    Row(
                      children: [
                        const Icon(Icons.zoom_out,
                            size: 18, color: AppColors.textMuted),
                        Expanded(
                          child: Slider(
                            value: _scale,
                            min: _minScale,
                            max: _maxScale,
                            divisions: 50,
                            activeColor: AppColors.primary,
                            inactiveColor: AppColors.surfaceLight,
                            onChanged: (v) => setState(() => _scale = v),
                          ),
                        ),
                        const Icon(Icons.zoom_in,
                            size: 18, color: AppColors.textMuted),
                        SizedBox(
                          width: 48,
                          child: Text(
                            '×${_scale.toStringAsFixed(1)}',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 12, color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    // Кнопки позиционирования
                    Text(
                      'Позиция',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _PosButton(
                            icon: Icons.arrow_upward,
                            onTap: () => _setPosition(_offsetX, -1.0)),
                        const SizedBox(width: 4),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                _PosButton(
                                    icon: Icons.arrow_back,
                                    onTap: () => _setPosition(-1.0, _offsetY)),
                                const SizedBox(width: 4),
                                _PosButton(
                                    icon: Icons.center_focus_strong,
                                    isActive: _offsetX == 0 && _offsetY == 0,
                                    onTap: () => _setPosition(0.0, 0.0)),
                                const SizedBox(width: 4),
                                _PosButton(
                                    icon: Icons.arrow_forward,
                                    onTap: () => _setPosition(1.0, _offsetY)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(width: 4),
                        _PosButton(
                            icon: Icons.arrow_downward,
                            onTap: () => _setPosition(_offsetX, 1.0)),
                      ],
                    ),

                    const SizedBox(height: 12),
                    // Подложка
                    Row(
                      children: [
                        Text(
                          'Фон:',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ModeButton(
                          label: 'Блюр',
                          icon: Icons.blur_on,
                          isActive: _backgroundType == BackgroundType.blur,
                          onTap: () => setState(
                              () => _backgroundType = BackgroundType.blur),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _palette
                                  .map(
                                    (colorValue) => GestureDetector(
                                      onTap: () => setState(() {
                                        _backgroundType = BackgroundType.color;
                                        _backgroundColor = colorValue;
                                      }),
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        margin:
                                            const EdgeInsets.only(right: 6),
                                        decoration: BoxDecoration(
                                          color: Color(colorValue),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _backgroundType ==
                                                        BackgroundType.color &&
                                                    _backgroundColor ==
                                                        colorValue
                                                ? AppColors.primary
                                                : Colors.white24,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _reset,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                        side: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: Text('Сброс',
                          style: GoogleFonts.manrope(fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlurBackground(PhotoLayer photo) {
    return Stack(
      children: [
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Image.file(
              File(photo.imagePath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.25)),
        ),
      ],
    );
  }
}

// ==========================================
// Кнопка режима (широкая)
// ==========================================
class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: isActive ? Colors.white : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// Кнопка позиционирования (компактная)
// ==========================================
class _PosButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _PosButton({
    required this.icon,
    this.isActive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isActive ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }
}