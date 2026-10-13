import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/colors.dart';
import '../../../data/models/video_project.dart';
import '../../../data/providers/project_provider.dart';

// ==========================================
// Шторка выбора оверлея + интенсивности
// ✅ Тип применяется сразу, интенсивность — слайдером вживую
// ==========================================
void showOverlaysSheet(BuildContext context, WidgetRef ref) {
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
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
          ),
          child: _OverlaysContent(sheetContext: sheetContext),
        ),
      );
    },
  );
}

class _OverlaysContent extends ConsumerWidget {
  final BuildContext sheetContext;
  const _OverlaysContent({required this.sheetContext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(currentProjectProvider);
    final type = project.overlayType;
    final intensity = project.overlayIntensity;

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
            'Оверлеи',
            style: GoogleFonts.unbounded(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Применяется ко всему видео',
            style:
                GoogleFonts.manrope(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),

          // ---- Список оверлеев ----
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: OverlayType.values
                  .map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _OverlayTile(
                          type: t,
                          isSelected: type == t,
                          onTap: () {
                            ref
                                .read(currentProjectProvider.notifier)
                                .updateOverlay(t);
                          },
                        ),
                      ))
                  .toList(),
            ),
          ),

          // ---- 🎚 Интенсивность ----
          if (type != OverlayType.none) ...[
            const Divider(color: AppColors.surfaceLight, height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune, size: 18, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Интенсивность',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${(intensity * 100).round()}%',
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
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 8),
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: AppColors.surfaceLight,
                thumbColor: AppColors.primary,
                overlayColor: AppColors.primary.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: intensity,
                min: 0.1,
                max: 1.0,
                divisions: 18, // шаг 5%
                onChanged: (v) {
                  ref
                      .read(currentProjectProvider.notifier)
                      .updateOverlayIntensity(v);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('10% • едва заметно',
                      style: GoogleFonts.manrope(
                          fontSize: 10, color: AppColors.textMuted)),
                  Text('100% • максимум',
                      style: GoogleFonts.manrope(
                          fontSize: 10, color: AppColors.textMuted)),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ---- Готово ----
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(sheetContext),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.check, size: 20),
              label: Text(
                'Готово',
                style: GoogleFonts.manrope(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayTile extends StatelessWidget {
  final OverlayType type;
  final bool isSelected;
  final VoidCallback onTap;

  const _OverlayTile({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final data = _overlayData(type);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.12)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.primary.withOpacity(0.15),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(data.emoji, style: const TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.subtitle,
                    style: GoogleFonts.manrope(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle,
                  color: AppColors.primary, size: 22),
          ],
        ),
      ),
    );
  }
}

class _OverlayData {
  final String emoji;
  final String title;
  final String subtitle;
  const _OverlayData(this.emoji, this.title, this.subtitle);
}

_OverlayData _overlayData(OverlayType type) {
  switch (type) {
    case OverlayType.none:
      return const _OverlayData('⬜', 'Без эффекта', 'Оригинальное изображение');
    case OverlayType.film:
      return const _OverlayData('🎞', 'Киноплёнка', 'Зерно, царапины, виньетка');
    case OverlayType.cinema:
      return const _OverlayData('🎬', 'Кино 2.35:1', 'Letterbox-полосы, виньетка');
    case OverlayType.vhs:
      return const _OverlayData('📼', 'VHS', 'Сканлайны, помехи, REC, таймкод');
    case OverlayType.lightleak:
      return const _OverlayData('🌅', 'Засветки', 'Тёплые light-leaks по углам');
    case OverlayType.dreamy:
      return const _OverlayData('☁️', 'Дрим', 'Мягкое свечение, световые пятна');
    case OverlayType.bokeh:
      return const _OverlayData('✨', 'Золотая пыль', 'Боке-частицы плывут вверх');
    case OverlayType.snow:
      return const _OverlayData('❄️', 'Снег', 'Падающие снежинки');
    case OverlayType.cyber:
      return const _OverlayData('⚡', 'Кибер-волна', 'Глитч-полосы cyan/magenta');
  }
}