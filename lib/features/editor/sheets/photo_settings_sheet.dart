import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/colors.dart';
import '../../../data/models/photo_layer.dart';
import '../../../data/models/video_project.dart'; // ✅ ДОБАВЛЕНО: для OverlayType
import '../../../data/providers/project_provider.dart';
import '../../../data/providers/selection_provider.dart';
import '../crop/crop_editor_screen.dart';
import 'effects_sheet.dart';
import 'live_motion_sheet.dart';
import 'transitions_sheet.dart';

// ==========================================
// Настройки кадра: информативная шторка
// ==========================================
void showPhotoSettingsSheet(BuildContext context, WidgetRef ref, int index) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      final systemBottomInset = MediaQuery.of(sheetContext).padding.bottom;

      return SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: systemBottomInset),
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final current = ref.read(currentProjectProvider);
            if (index >= current.photos.length) return const SizedBox.shrink();
            final photo = current.photos[index];
            final ms = photo.durationMilliseconds;

            final targets = SelectionController(ref).targetIndices(index);
            final isMulti = targets.length > 1;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.primary.withValues(alpha: 0.3))),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ColorFiltered(
                            colorFilter: ColorFilter.matrix(FilterPresets.matrix(photo.filter)),
                            child: Image.file(File(photo.imagePath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceLight, child: const Icon(Icons.broken_image, size: 24))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Кадр ${index + 1}', style: GoogleFonts.unbounded(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                            const SizedBox(height: 4),
                            Text('${(ms / 1000).toStringAsFixed(1)} сек • ${photo.fitMode == FitMode.cover ? 'Заполнить' : 'Вписать'}', style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _InfoTile(
                    icon: Icons.palette_outlined, iconColor: Colors.orange, label: 'Фильтр', value: FilterPresets.label(photo.filter),
                    onTap: () { Navigator.pop(sheetContext); showEffectsSheet(context, ref, [index]); },
                  ),
                  const SizedBox(height: 8),

                  if (index > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _InfoTile(
                        icon: Icons.swap_horiz, iconColor: Colors.blue, label: 'Переход',
                        value: photo.transition == TransitionType.none ? 'Нет' : TransitionPresets.label(photo.transition),
                        onTap: () { Navigator.pop(sheetContext); showTransitionsSheet(context, ref, [index]); },
                      ),
                    ),

                  _InfoTile(
                    icon: Icons.auto_awesome, iconColor: Colors.purple, label: 'Появление',
                    value: photo.entranceAnimation == EntranceAnimation.none ? 'Нет' : '${_entranceLabel(photo.entranceAnimation)} (${(photo.entranceDurationMs / 1000).toStringAsFixed(1)}с)',
                    onTap: () { Navigator.pop(sheetContext); showEffectsSheet(context, ref, [index]); },
                  ),
                  const SizedBox(height: 8),

                  _InfoTile(
                    icon: Icons.motion_photos_on, iconColor: Colors.pink, label: 'Движение', value: LiveMotionPresets.label(photo.liveMotion),
                    onTap: () { Navigator.pop(sheetContext); showLiveMotionSheet(context, ref); },
                  ),
                  const SizedBox(height: 8),

                                    // ✅ НОВОЕ: Карточка Оверлея кадра
                  _InfoTile(
                    icon: Icons.layers_outlined, iconColor: Colors.indigo, label: 'Оверлей кадра',
                    value: photo.overlayType == OverlayType.none ? 'Нет (как у проекта)' : '${_overlayLabel(photo.overlayType)} (${(photo.overlayIntensity * 100).round()}%)',
                    onTap: () {
                      // ✅ ИСПРАВЛЕНО: Оборачиваем setSheetState в VoidCallback
                      showFrameOverlayPicker(context, ref, targets, () => setSheetState(() {}));
                    },
                  ),
                  const SizedBox(height: 8),

                  _InfoTile(
                    icon: Icons.crop_free, iconColor: Colors.teal, label: 'Кадрирование',
                    value: photo.fitMode == FitMode.cover ? 'Заполнить' : 'Вписать${photo.scale != 1.0 ? ' ×${photo.scale.toStringAsFixed(2)}' : ''}',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => CropEditorScreen(photoIndex: index)));
                    },
                  ),

                  const SizedBox(height: 20),
                  const Divider(color: AppColors.surfaceLight),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text('Длительность', style: GoogleFonts.manrope(fontSize: 14, color: AppColors.textSecondary)),
                        ],
                      ),
                      Text('${(ms / 1000).toStringAsFixed(1)} сек', style: GoogleFonts.jetBrainsMono(fontSize: 14, color: AppColors.primary)),
                    ],
                  ),

                  if (isMulti)
                    Container(
                      width: double.infinity, margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.primary.withValues(alpha: 0.4))),
                      child: Row(
                        children: [
                          const Icon(Icons.layers_outlined, size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Применится к ${targets.length} выбранным кадрам', style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary))),
                        ],
                      ),
                    ),

                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final sec in [1.0, 2.0, 3.0, 5.0])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: () {
                                final notifier = ref.read(currentProjectProvider.notifier);
                                for (final i in targets) notifier.updatePhotoDuration(i, (sec * 1000).round());
                                setSheetState(() {});
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: (ms / 1000 - sec).abs() < 0.01 ? AppColors.primary : AppColors.surfaceLight,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                ),
                                child: Text('${sec.toStringAsFixed(0)}с', textAlign: TextAlign.center, style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w700, color: (ms / 1000 - sec).abs() < 0.01 ? Colors.white : AppColors.textSecondary)),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),

                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8), activeTrackColor: AppColors.primary,
                      inactiveTrackColor: AppColors.surfaceLight, thumbColor: AppColors.primary, overlayColor: AppColors.primary.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: (ms / 1000).clamp(1.0, 5.0), min: 1.0, max: 5.0, divisions: 8,
                      onChanged: (value) {
                        final notifier = ref.read(currentProjectProvider.notifier);
                        final newMs = (value * 1000).round();
                        for (final i in targets) notifier.updatePhotoDuration(i, newMs);
                        setSheetState(() {});
                      },
                    ),
                  ),

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ref.read(currentProjectProvider.notifier).removePhoto(index);
                        final remaining = ref.read(currentProjectProvider).photos.length;
                        final selected = ref.read(selectedPhotoIndexProvider);
                        if (remaining == 0) {
                          ref.read(selectedPhotoIndexProvider.notifier).state = 0;
                          ref.read(playheadMsProvider.notifier).state = 0;
                        } else if (selected >= remaining) {
                          ref.read(selectedPhotoIndexProvider.notifier).state = remaining - 1;
                        }
                        Navigator.pop(sheetContext);
                      },
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error), padding: const EdgeInsets.symmetric(vertical: 14)),
                      icon: const Icon(Icons.delete_outline),
                      label: Text('Удалить кадр', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

// ==========================================
// ✅ НОВОЕ: Пикер оверлея для кадра (с поддержкой мультивыбора)
// ==========================================
void showFrameOverlayPicker(BuildContext context, WidgetRef ref, List<int> targets, VoidCallback onUpdated) {
  final currentProject = ref.read(currentProjectProvider);
  final firstPhoto = currentProject.photos[targets.first];
  
  OverlayType selectedType = firstPhoto.overlayType;
  double selectedIntensity = firstPhoto.overlayIntensity;

  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (pickerContext) {
      return StatefulBuilder(
        builder: (pickerContext, setPickerState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(2)))),
                  Text('Оверлей кадра', style: GoogleFonts.unbounded(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  
                  if (targets.length > 1) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.primary.withValues(alpha: 0.4))),
                      child: Row(
                        children: [
                          const Icon(Icons.layers_outlined, size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Применится к ${targets.length} выбранным кадрам', style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary))),
                        ],
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 20),
                  Text('Тип оверлея', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: OverlayType.values.map((type) {
                      final isSelected = selectedType == type;
                      return GestureDetector(
                        onTap: () => setPickerState(() => selectedType = type),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isSelected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            _overlayLabel(type),
                            style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : AppColors.textPrimary),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Интенсивность', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      Text('${(selectedIntensity * 100).round()}%', style: GoogleFonts.jetBrainsMono(fontSize: 14, color: AppColors.primary)),
                    ],
                  ),
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8), activeTrackColor: AppColors.primary,
                      inactiveTrackColor: AppColors.surfaceLight, thumbColor: AppColors.primary, overlayColor: AppColors.primary.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: selectedIntensity, min: 0.1, max: 1.0, divisions: 9,
                      onChanged: (val) => setPickerState(() => selectedIntensity = val),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final notifier = ref.read(currentProjectProvider.notifier);
                        for (final i in targets) {
                          notifier.updatePhotoOverlay(i, selectedType, selectedIntensity);
                        }
                        Navigator.pop(pickerContext); // Закрываем пикер
                        onUpdated(); // Обновляем родительскую шторку настроек
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: Text('Применить', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

// ==========================================
// Вспомогательные функции
// ==========================================
String _overlayLabel(OverlayType type) {
  switch (type) {
    case OverlayType.none: return 'Нет';
    case OverlayType.film: return 'Плёнка';
    case OverlayType.cinema: return 'Кино';
    case OverlayType.vhs: return 'VHS';
    case OverlayType.lightleak: return 'Засветка';
    case OverlayType.dreamy: return 'Мечта';
    case OverlayType.bokeh: return 'Боке';
    case OverlayType.snow: return 'Снег';
    case OverlayType.cyber: return 'Кибер';
  }
}

String _entranceLabel(EntranceAnimation e) {
  const names = {
    'fadeIn': 'Fade In', 'zoomIn': 'Zoom In', 'slideFromLeft': 'Слева',
    'slideFromRight': 'Справа', 'slideFromTop': 'Сверху', 'slideFromBottom': 'Снизу', 'rotateIn': 'Поворот',
  };
  return names[e.name] ?? 'Нет';
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _InfoTile({required this.icon, required this.iconColor, required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withValues(alpha: 0.15))),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GoogleFonts.manrope(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(value, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 22),
          ],
        ),
      ),
    );
  }
}