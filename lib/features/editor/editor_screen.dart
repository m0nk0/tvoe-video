import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/colors.dart';
import '../../data/models/photo_layer.dart';
import '../../data/providers/project_provider.dart';
import '../../data/providers/projects_provider.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  double timelineZoom = 1.0;
  bool isPlaying = false;

  /// Сохраняем проект в Hive и выходим
  Future<void> _saveAndPop() async {
    final project = ref.read(currentProjectProvider);
    if (project.photos.isNotEmpty) {
      await ref.read(projectRepositoryProvider).saveProject(project);
      ref.read(projectsProvider.notifier).refresh();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(currentProjectProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _saveAndPop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.chevron_left, size: 28),
            color: AppColors.textPrimary,
            onPressed: _saveAndPop,
          ),
          title: Text(
            project.name,
            style: GoogleFonts.unbounded(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // TODO: Переход на экран экспорта
              },
              child: Text(
                'Экспорт',
                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.primary),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // A. Превью (45%)
              Expanded(
                flex: 45,
                child: _PreviewArea(
                  isPlaying: isPlaying,
                  onPlayPause: () => setState(() => isPlaying = !isPlaying),
                ),
              ),
              Container(height: 1, color: AppColors.surfaceLight),

              // B. Панель инструментов (15%)
              Expanded(
                flex: 15,
                child: _Toolbar(
                  onAddPhoto: () => ref.read(currentProjectProvider.notifier).addPhotosFromGallery(),
                ),
              ),
              Container(height: 1, color: AppColors.surfaceLight),

              // C. Таймлайн (40%)
              Expanded(
                flex: 40,
                child: _Timeline(
                  zoom: timelineZoom,
                  onZoomChanged: (value) => setState(() => timelineZoom = value),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// A. Область превью (честные 9:16)
// ==========================================
class _PreviewArea extends ConsumerWidget {
  final bool isPlaying;
  final VoidCallback onPlayPause;

  const _PreviewArea({required this.isPlaying, required this.onPlayPause});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(currentProjectProvider);
    final selectedIndex = ref.watch(selectedPhotoIndexProvider);
    final hasPhotos = project.photos.isNotEmpty;
    final safeIndex = hasPhotos ? selectedIndex.clamp(0, project.photos.length - 1) : 0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 2),
            ),
            child: !hasPhotos
                ? const Center(child: Icon(Icons.crop_portrait, size: 64, color: AppColors.textMuted))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(project.photos[safeIndex].imagePath),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image, color: AppColors.error),
                          ),
                        ),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(40),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.skip_previous, color: Colors.white, size: 28),
                                  disabledColor: AppColors.textMuted.withValues(alpha: 0.3),
                                  onPressed: safeIndex > 0
                                      ? () => ref.read(selectedPhotoIndexProvider.notifier).state = safeIndex - 1
                                      : null,
                                ),
                                IconButton(
                                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 36),
                                  onPressed: onPlayPause,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.skip_next, color: Colors.white, size: 28),
                                  disabledColor: AppColors.textMuted.withValues(alpha: 0.3),
                                  onPressed: safeIndex < project.photos.length - 1
                                      ? () => ref.read(selectedPhotoIndexProvider.notifier).state = safeIndex + 1
                                      : null,
                                ),
                              ],
                            ),
                          ),
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

// ==========================================
// B. Панель инструментов
// ==========================================
class _Toolbar extends StatelessWidget {
  final VoidCallback onAddPhoto;

  const _Toolbar({required this.onAddPhoto});

  @override
  Widget build(BuildContext context) {
    final tools = [
      {'icon': Icons.add_photo_alternate, 'label': 'Фото', 'action': onAddPhoto},
      {'icon': Icons.content_cut, 'label': 'Обрезать', 'action': () {}},
      {'icon': Icons.music_note, 'label': 'Музыка', 'action': () {}},
      {'icon': Icons.auto_fix_high, 'label': 'Эффекты', 'action': () {}},
      {'icon': Icons.text_fields, 'label': 'Текст', 'action': () {}},
      {'icon': Icons.tune, 'label': 'Фильтры', 'action': () {}},
    ];

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: tools.length,
      itemBuilder: (context, index) {
        final tool = tools[index];
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: tool['action'] as VoidCallback,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Icon(tool['icon'] as IconData, color: AppColors.primary, size: 24),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tool['label'] as String,
                style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ==========================================
// C. Таймлайн (drag-and-drop + зум над навигацией)
// ==========================================
class _Timeline extends ConsumerWidget {
  final double zoom;
  final ValueChanged<double> onZoomChanged;

  const _Timeline({required this.zoom, required this.onZoomChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(currentProjectProvider);
    final selectedIndex = ref.watch(selectedPhotoIndexProvider);

    return Stack(
      children: [
        if (project.photos.isEmpty)
          Center(
            child: Text(
              'Нажмите "Фото", чтобы добавить изображения',
              style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 14),
            ),
          )
        else
          ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            itemCount: project.photos.length,
            onReorder: (oldIndex, newIndex) =>
                ref.read(currentProjectProvider.notifier).reorderPhotos(oldIndex, newIndex),
            itemBuilder: (context, index) {
              final photo = project.photos[index];
              return _TimelineItem(
                key: ValueKey('${photo.imagePath}_$index'),
                photo: photo,
                isSelected: index == selectedIndex,
                zoom: zoom,
                onTap: () {
                  ref.read(selectedPhotoIndexProvider.notifier).state = index;
                  showPhotoSettingsSheet(context, ref, index);
                },
              );
            },
          ),

        // Плейхед по центру
        if (project.photos.isNotEmpty)
          IgnorePointer(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomPaint(size: const Size(16, 12), painter: _TrianglePainter(color: AppColors.primary)),
                  Container(width: 2, height: 110, color: AppColors.primary),
                ],
              ),
            ),
          ),

        // Зум-контрол (внутри SafeArea, над системной навигацией)
        Positioned(
          right: 12,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.remove, color: AppColors.textMuted, size: 16),
                SizedBox(
                  width: 60,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: AppColors.surfaceLight,
                      thumbColor: AppColors.primary,
                      overlayColor: AppColors.primary.withValues(alpha: 0.2),
                    ),
                    child: Slider(value: zoom, min: 0.8, max: 1.5, onChanged: onZoomChanged),
                  ),
                ),
                const Icon(Icons.add, color: AppColors.textMuted, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// Миниатюра кадра на таймлайне
// ==========================================
class _TimelineItem extends StatelessWidget {
  final PhotoLayer photo;
  final bool isSelected;
  final double zoom;
  final VoidCallback onTap;

  const _TimelineItem({
    super.key,
    required this.photo,
    required this.isSelected,
    required this.zoom,
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
              width: 80 * zoom,
              height: 80 * zoom,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(photo.imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: AppColors.error),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(photo.durationMilliseconds / 1000).toStringAsFixed(1)}s',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: isSelected ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// Bottom sheet: длительность + удаление кадра
// ==========================================
void showPhotoSettingsSheet(BuildContext context, WidgetRef ref, int index) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      // Двойная защита: если SafeArea не сработал,
      // добавляем высоту системной панели вручную
      final systemBottomInset = MediaQuery.of(sheetContext).padding.bottom;

      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final current = ref.read(currentProjectProvider);
          if (index >= current.photos.length) return const SizedBox.shrink();
          final ms = current.photos[index].durationMilliseconds;

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + systemBottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ручка для перетаскивания панели
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Настройки кадра ${index + 1}',
                  style: GoogleFonts.unbounded(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Длительность', style: GoogleFonts.manrope(fontSize: 14, color: AppColors.textSecondary)),
                    Text(
                      '${(ms / 1000).toStringAsFixed(1)} сек',
                      style: GoogleFonts.jetBrainsMono(fontSize: 14, color: AppColors.primary),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: AppColors.surfaceLight,
                    thumbColor: AppColors.primary,
                    overlayColor: AppColors.primary.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: (ms / 1000).clamp(1.0, 5.0),
                    min: 1.0,
                    max: 5.0,
                    divisions: 8,
                    onChanged: (value) {
                      ref.read(currentProjectProvider.notifier).updatePhotoDuration(index, (value * 1000).round());
                      setSheetState(() {});
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ref.read(currentProjectProvider.notifier).removePhoto(index);
                      final remaining = ref.read(currentProjectProvider).photos.length;
                      final selected = ref.read(selectedPhotoIndexProvider);
                      if (remaining == 0) {
                        ref.read(selectedPhotoIndexProvider.notifier).state = 0;
                      } else if (selected >= remaining) {
                        ref.read(selectedPhotoIndexProvider.notifier).state = remaining - 1;
                      }
                      Navigator.pop(sheetContext);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: Text('Удалить кадр', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

// ==========================================
// Треугольник плейхеда
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