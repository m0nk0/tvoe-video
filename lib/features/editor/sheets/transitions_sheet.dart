import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/colors.dart';
import '../../../data/models/photo_layer.dart';
import '../../../data/providers/project_provider.dart';

// ==========================================
// Меню переходов (поддерживает мультивыбор)
// ✅ Тип перехода + длительность (0.3–1.5с) с опцией «ко всем»
// ==========================================
void showTransitionsSheet(
    BuildContext context, WidgetRef ref, List<int> targets) {
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
        child: TransitionsSheetContent(targets: targets),
      );
    },
  );
}

class TransitionsSheetContent extends ConsumerStatefulWidget {
  final List<int> targets;
  const TransitionsSheetContent({super.key, required this.targets});

  @override
  ConsumerState<TransitionsSheetContent> createState() =>
      TransitionsSheetContentState();
}

class TransitionsSheetContentState
    extends ConsumerState<TransitionsSheetContent> {
  late TransitionType _selected;
  late double _durationSec; // в секундах (0.3..1.5)
  bool _applyToAll = false;
  bool _applyDurationToAll = false;

  bool get _isMulti => widget.targets.length > 1;

  @override
  void initState() {
    super.initState();
    final firstIdx = widget.targets.first;
    final photo = ref.read(currentProjectProvider).photos[firstIdx];
    _selected = photo.transition;
    _durationSec = (photo.transitionDurationMs / 1000).clamp(0.3, 1.5);
  }

  void _apply() {
    final notifier = ref.read(currentProjectProvider.notifier);
    final typeTargets = _applyToAll ? _allIndices() : widget.targets;
    final durTargets = _applyDurationToAll ? _allIndices() : widget.targets;
    final durationMs = (_durationSec * 1000).round();

    for (final idx in typeTargets) {
      notifier.updatePhotoTransition(idx, _selected);
    }
    for (final idx in durTargets) {
      notifier.updatePhotoTransitionDuration(idx, durationMs);
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

    final titleText = _isMulti
        ? 'Применить к ${widget.targets.length} кадрам'
        : 'Переход от кадра ${firstIdx + 1} к следующему';

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
            'Переходы',
            style: GoogleFonts.unbounded(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            titleText,
            style:
                GoogleFonts.manrope(fontSize: 13, color: AppColors.textMuted),
          ),

          // ---- Тип перехода ----
          const SizedBox(height: 20),
          Text(
            'Тип перехода',
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: TransitionType.values.map((type) {
              final isSelected = _selected == type;
              return ChoiceChip(
                label: Text(TransitionPresets.label(type)),
                selected: isSelected,
                onSelected: (_) => setState(() => _selected = type),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surfaceLight,
                labelStyle: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color:
                      isSelected ? Colors.white : AppColors.textSecondary,
                ),
                side: BorderSide(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.primary.withValues(alpha: 0.3),
                ),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              );
            }).toList(),
          ),

          // ✅ Свитч "тип ко всем" — только для одиночного кадра
          if (!_isMulti) ...[
            const SizedBox(height: 12),
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
                      'Тип ко всем кадрам',
                      style: GoogleFonts.manrope(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
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
                      'Тип применится ко всем ${widget.targets.length} выделенным кадрам',
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

          // ==========================================
          // ⏱ ДЛИТЕЛЬНОСТЬ ПЕРЕХОДА
          // ==========================================
          const SizedBox(height: 20),
          const Divider(color: AppColors.surfaceLight),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.timer_outlined,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Длительность',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Text(
                '${_durationSec.toStringAsFixed(1)} сек',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary),
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
              value: _durationSec,
              min: 0.3,
              max: 1.5,
              divisions: 12, // шаг 0.1с
              onChanged: (v) => setState(() => _durationSec = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0.3с',
                    style: GoogleFonts.manrope(
                        fontSize: 10, color: AppColors.textMuted)),
                Text('Быстрее',
                    style: GoogleFonts.manrope(
                        fontSize: 10,
                        color: AppColors.textMuted,
                        fontStyle: FontStyle.italic)),
                Text('Плавнее',
                    style: GoogleFonts.manrope(
                        fontSize: 10,
                        color: AppColors.textMuted,
                        fontStyle: FontStyle.italic)),
                Text('1.5с',
                    style: GoogleFonts.manrope(
                        fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
          ),

          // Свитч "длительность ко всем" — для одиночного кадра
          if (!_isMulti) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(
                  () => _applyDurationToAll = !_applyDurationToAll),
              child: Row(
                children: [
                  Switch(
                    value: _applyDurationToAll,
                    onChanged: (v) =>
                        setState(() => _applyDurationToAll = v),
                    activeColor: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Длительность ко всем кадрам',
                      style: GoogleFonts.manrope(
                          fontSize: 13, color: AppColors.textSecondary),
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
                      'Длительность применится ко всем ${widget.targets.length} выделенным кадрам',
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

          const SizedBox(height: 20),

          // ---- Кнопки ----
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