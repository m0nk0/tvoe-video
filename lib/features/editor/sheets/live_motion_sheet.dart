import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/colors.dart';
import '../../../data/models/photo_layer.dart';
import '../../../data/providers/project_provider.dart';

void showLiveMotionSheet(BuildContext context, WidgetRef ref) {
  final selectedIndex = ref.read(selectedPhotoIndexProvider);
  final project = ref.read(currentProjectProvider);
  
  if (project.photos.isEmpty || selectedIndex >= project.photos.length) return;
  
  final currentMotion = project.photos[selectedIndex].liveMotion;
  final cinematicIntensity = project.cinematicIntensity;

  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            // ✅ Читаем текущее движение из проекта (обновляется при изменении)
            final currentProject = ref.read(currentProjectProvider);
            final currentPhoto = currentProject.photos[selectedIndex];
            final selectedMotion = currentPhoto.liveMotion;
            final currentIntensity = currentProject.cinematicIntensity;

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                    'Движение кадра',
                    style: GoogleFonts.unbounded(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Делает фото «живым» при просмотре',
                    style: GoogleFonts.manrope(fontSize: 13, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 16),
                  
                  // Список режимов
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: LiveMotion.values.map((motion) {
                        final isSelected = motion == selectedMotion;
                        return GestureDetector(
                          onTap: () {
                            ref.read(currentProjectProvider.notifier).updatePhotoLiveMotion(
                              selectedIndex,
                              motion,
                              applyToAll: false,
                            );
                            // ✅ Обновляем состояние шторки
                            setSheetState(() {});
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected 
                                  ? AppColors.primary.withOpacity(0.1) 
                                  : AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? AppColors.primary : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    LiveMotionPresets.label(motion),
                                    style: GoogleFonts.manrope(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle, color: AppColors.primary, size: 24),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  const Divider(color: AppColors.surfaceLight),
                  const SizedBox(height: 12),

                  //  Слайдер интенсивности 3D-эффекта
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome, size: 18, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(
                            '3D-эффект',
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${(currentIntensity * 100).round()}%',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
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
                      value: currentIntensity,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      onChanged: (value) {
                        ref.read(currentProjectProvider.notifier).updateCinematicIntensity(value);
                        setSheetState(() {});
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Выкл', style: GoogleFonts.manrope(fontSize: 10, color: AppColors.textMuted)),
                        Text('Максимум', style: GoogleFonts.manrope(fontSize: 10, color: AppColors.textMuted)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  
                  // Кнопки действий
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            ref.read(currentProjectProvider.notifier).updatePhotoLiveMotion(
                              selectedIndex,
                              selectedMotion,
                              applyToAll: true,
                            );
                            Navigator.pop(sheetContext);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.surfaceLight,
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'Ко всем фото', 
                            style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'Готово', 
                            style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
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