import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/colors.dart';
import '../../../data/models/photo_layer.dart';
import '../../../data/providers/project_provider.dart';

// ==========================================
// Меню эффектов (поддерживает мультивыбор)
// ==========================================
void showEffectsSheet(BuildContext context, WidgetRef ref, List<int> targets) {
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
        child: EffectsSheetContent(targets: targets),
      );
    },
  );
}

class EffectsSheetContent extends ConsumerStatefulWidget {
  final List<int> targets;
  const EffectsSheetContent({super.key, required this.targets});

  @override
  ConsumerState<EffectsSheetContent> createState() => EffectsSheetContentState();
}

class EffectsSheetContentState extends ConsumerState<EffectsSheetContent> {
  late FilterType _selectedFilter;
  late EntranceAnimation _selectedEntrance;
  late int _selectedDuration;
  bool _applyToAll = false;

  bool get _isMulti => widget.targets.length > 1;

  @override
  void initState() {
    super.initState();
    // Для превью берём первый кадр из списка выбранных
    final firstIdx = widget.targets.first;
    final photo = ref.read(currentProjectProvider).photos[firstIdx];
    _selectedFilter = photo.filter ?? FilterType.none;
    _selectedEntrance = photo.entranceAnimation;
    _selectedDuration = photo.entranceDurationMs;
  }

  void _apply() {
    final notifier = ref.read(currentProjectProvider.notifier);
    final targets = _applyToAll ? _allIndices() : widget.targets;

    for (final idx in targets) {
      notifier.updatePhotoFilter(idx, _selectedFilter);
      notifier.updatePhotoEntranceAnimation(idx, _selectedEntrance);
      notifier.updatePhotoEntranceDuration(idx, _selectedDuration);
    }
    Navigator.pop(context);
  }

  List<int> _allIndices() {
    final photos = ref.read(currentProjectProvider).photos;
    return List.generate(photos.length, (i) => i);
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(currentProjectProvider).photos;
    final firstIdx = widget.targets.first;
    if (firstIdx >= photos.length) return const SizedBox.shrink();
    final photo = photos[firstIdx];

    final titleText = _isMulti
        ? 'Применить к ${widget.targets.length} кадрам'
        : 'Кадр ${firstIdx + 1}';

    return SingleChildScrollView(
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
            'Эффекты',
            style: GoogleFonts.unbounded(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            titleText,
            style: GoogleFonts.manrope(fontSize: 13, color: AppColors.textMuted),
          ),

          const SizedBox(height: 20),
          Text(
            'Фильтр',
            style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: FilterType.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, filterIndex) {
                final filter = FilterType.values[filterIndex];
                final isSelected = _selectedFilter == filter;

                return GestureDetector(
                  onTap: () => setState(() => _selectedFilter = filter),
                  child: Column(
                    children: [
                      Container(
                        width: 75,
                        height: 75,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: ColorFiltered(
                            colorFilter:
                                ColorFilter.matrix(FilterPresets.matrix(filter)),
                            child: Image.file(
                              File(photo.imagePath),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        FilterPresets.label(filter),
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textMuted,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),
          Text(
            'Появление',
            style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: EntranceAnimation.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, animIndex) {
                final anim = EntranceAnimation.values[animIndex];
                final isSelected = _selectedEntrance == anim;

                return GestureDetector(
                  onTap: () => setState(() => _selectedEntrance = anim),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        EntrancePresets.label(anim),
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Длительность',
                style: GoogleFonts.manrope(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              Text(
                '$_selectedDuration мс',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: AppColors.primary),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7),
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.surfaceLight,
              thumbColor: AppColors.primary,
            ),
            child: Slider(
              value: _selectedDuration.toDouble(),
              min: 200,
              max: 1000,
              divisions: 8,
              onChanged: (value) =>
                  setState(() => _selectedDuration = value.round()),
            ),
          ),

          // Свитч "ко всем" показываем только в обычном режиме
          if (!_isMulti) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _applyToAll = !_applyToAll),
              child: Row(
                children: [
                  Switch(
                    value: _applyToAll,
                    onChanged: (v) => setState(() => _applyToAll = v),
                    activeColor: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Применить ко всем кадрам',
                      style: GoogleFonts.manrope(
                          fontSize: 14, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Применится ко всем ${widget.targets.length} выделенным кадрам',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Отмена',
                    style: GoogleFonts.manrope(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.check, size: 20),
                  label: Text(
                    _applyToAll || _isMulti
                        ? 'Применить ко всем'
                        : 'Применить',
                    style: GoogleFonts.manrope(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}