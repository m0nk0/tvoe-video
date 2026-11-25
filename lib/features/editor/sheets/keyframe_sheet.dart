import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/colors.dart';
import '../../../data/models/keyframe.dart';
import '../../../data/providers/project_provider.dart';

void showKeyframeSheet(BuildContext context, WidgetRef ref, int photoIndex, int kfIndex) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    builder: (_) => KeyframeSheet(photoIndex: photoIndex, kfIndex: kfIndex),
  );
}

class KeyframeSheet extends ConsumerStatefulWidget {
  final int photoIndex;
  final int kfIndex;
  const KeyframeSheet({super.key, required this.photoIndex, required this.kfIndex});

  @override
  ConsumerState<KeyframeSheet> createState() => _KeyframeSheetState();
}

class _KeyframeSheetState extends ConsumerState<KeyframeSheet> {
  late double scale;
  late double offsetX;
  late double offsetY;
  late double opacity;
  late double rotation;

  @override
  void initState() {
    super.initState();
    final photos = ref.read(currentProjectProvider).photos;
    if (widget.photoIndex < photos.length && widget.kfIndex < photos[widget.photoIndex].keyframes.length) {
      final kf = photos[widget.photoIndex].keyframes[widget.kfIndex];
      scale = kf.scale;
      offsetX = kf.offsetX;
      offsetY = kf.offsetY;
      opacity = kf.opacity;
      rotation = kf.rotation;
    } else {
      scale = 1.0;
      offsetX = 0.0;
      offsetY = 0.0;
      opacity = 1.0;
      rotation = 0.0;
    }
  }

  void _update() {
    final photos = ref.read(currentProjectProvider).photos;
    if (widget.photoIndex >= photos.length) return;
    final p = photos[widget.photoIndex];
    if (widget.kfIndex >= p.keyframes.length) return;
    
    final old = p.keyframes[widget.kfIndex];
    final updated = old.copyWith(
      scale: scale,
      offsetX: offsetX,
      offsetY: offsetY,
      opacity: opacity,
      rotation: rotation,
    );
    ref.read(currentProjectProvider.notifier).updateKeyframe(widget.photoIndex, widget.kfIndex, updated);
  }

  void _reset() {
    setState(() {
      scale = 1.0;
      offsetX = 0.0;
      offsetY = 0.0;
      opacity = 1.0;
      rotation = 0.0;
    });
    _update();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '◆ Кейфрейм',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Сброс'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _buildSlider(
            label: 'Масштаб',
            value: scale,
            min: 0.5,
            max: 3.0,
            displayValue: '${scale.toStringAsFixed(2)}x',
            onChanged: (v) => setState(() { scale = v; _update(); }),
          ),

          _buildSlider(
            label: 'Сдвиг по X',
            value: offsetX,
            min: -1.0,
            max: 1.0,
            displayValue: '${(offsetX * 100).round()}%',
            onChanged: (v) => setState(() { offsetX = v; _update(); }),
          ),

          _buildSlider(
            label: 'Сдвиг по Y',
            value: offsetY,
            min: -1.0,
            max: 1.0,
            displayValue: '${(offsetY * 100).round()}%',
            onChanged: (v) => setState(() { offsetY = v; _update(); }),
          ),

          _buildSlider(
            label: 'Прозрачность',
            value: opacity,
            min: 0.0,
            max: 1.0,
            displayValue: '${(opacity * 100).round()}%',
            onChanged: (v) => setState(() { opacity = v; _update(); }),
          ),

          _buildSlider(
            label: 'Поворот',
            value: rotation,
            min: -3.14159,
            max: 3.14159,
            displayValue: '${(rotation * 180 / 3.14159).round()}°',
            onChanged: (v) => setState(() { rotation = v; _update(); }),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                displayValue,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            activeColor: AppColors.primary,
            inactiveColor: AppColors.surfaceLight,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}