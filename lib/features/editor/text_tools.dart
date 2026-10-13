import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/colors.dart';
import '../../data/models/photo_layer.dart';
import '../../data/models/text_layer.dart';
import '../../data/models/video_project.dart';
import '../../data/providers/project_provider.dart';

// ==========================================
// Хелперы таймлайна
// ==========================================

int frameStartMs(List<PhotoLayer> photos, int index) {
  int sum = 0;
  for (int i = 0; i < index && i < photos.length; i++) {
    sum += photos[i].durationMilliseconds;
  }
  return sum;
}

int frameIndexForMs(List<PhotoLayer> photos, int ms) {
  int sum = 0;
  for (int i = 0; i < photos.length; i++) {
    sum += photos[i].durationMilliseconds;
    if (ms < sum) return i;
  }
  return photos.isEmpty ? 0 : photos.length - 1;
}

List<int> visibleTextIndices(VideoProject project, int frameIndex) {
  if (project.photos.isEmpty || frameIndex >= project.photos.length) return [];
  final start = frameStartMs(project.photos, frameIndex);
  final end = start + project.photos[frameIndex].durationMilliseconds;
  final result = <int>[];
  for (int i = 0; i < project.texts.length; i++) {
    final t = project.texts[i];
    if (t.startTimeMilliseconds < end && t.endTimeMilliseconds > start) {
      result.add(i);
    }
  }
  return result;
}

/// Список виджет-оверлеев текста для превью
List<Widget> buildTextOverlays(
  VideoProject project,
  int frameIndex, {
  bool isEditing = false,
  Function(int index, double x, double y)? onPositionChanged,
}) {
  return visibleTextIndices(project, frameIndex)
      .map((i) => TextOverlayWidget(
            text: project.texts[i],
            frameIndex: frameIndex,
            isEditing: isEditing,
            onPositionChanged: (x, y) => onPositionChanged?.call(i, x, y),
          ))
      .toList();
}

// ==========================================
// Оверлей текста на превью (с перетаскиванием)
// ==========================================
class TextOverlayWidget extends StatefulWidget {
  final TextLayer text;
  final int frameIndex;
  final bool isEditing;
  final Function(double x, double y)? onPositionChanged;

  const TextOverlayWidget({
    required this.text,
    required this.frameIndex,
    this.isEditing = false,
    this.onPositionChanged,
  });

  @override
  State<TextOverlayWidget> createState() => _TextOverlayWidgetState();
}

class _TextOverlayWidgetState extends State<TextOverlayWidget> {
  late double _currentX;
  late double _currentY;

  @override
  void initState() {
    super.initState();
    _currentX = widget.text.positionX;
    _currentY = widget.text.positionY;
  }

  @override
  void didUpdateWidget(covariant TextOverlayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Сбрасываем позицию только если текст изменился (не при смене режима редактирования)
    if (oldWidget.text != widget.text) {
      _currentX = widget.text.positionX;
      _currentY = widget.text.positionY;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: widget.isEditing
            ? (details) {
                final size = context.size;
                if (size == null) return;
                setState(() {
                  _currentX = (_currentX + details.delta.dx / size.width).clamp(0.0, 1.0);
                  _currentY = (_currentY + details.delta.dy / size.height).clamp(0.0, 1.0);
                });
                widget.onPositionChanged?.call(_currentX, _currentY);
              }
            : null,
        child: IgnorePointer(
          ignoring: widget.isEditing, // В режиме редактирования GestureDetector ловит тапы
          child: Align(
            alignment: Alignment(_currentX * 2 - 1, _currentY * 2 - 1),
            child: TweenAnimationBuilder<double>(
              key: ValueKey('${widget.text.text}_${widget.text.startTimeMilliseconds}_${widget.frameIndex}'),
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              builder: (context, t, _) {
                Widget content = _buildContent(t);
                if (widget.isEditing) {
                  content = Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.yellow, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: content,
                  );
                }
                switch (widget.text.animation) {
                  case AnimationType.none:
                    return content;
                  case AnimationType.fadeIn:
                    return Opacity(opacity: t.clamp(0.0, 1.0), child: content);
                  case AnimationType.slideUp:
                    return Transform.translate(
                      offset: Offset(0, (1 - t) * 40),
                      child: Opacity(opacity: t.clamp(0.0, 1.0), child: content),
                    );
                  case AnimationType.slideDown:
                    return Transform.translate(
                      offset: Offset(0, -(1 - t) * 40),
                      child: Opacity(opacity: t.clamp(0.0, 1.0), child: content),
                    );
                  case AnimationType.typewriter:
                    return content;
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(double t) {
    final color = Color(widget.text.colorValue);
    final isTitle = widget.text.fontFamily == 'Unbounded';

    final shownText = widget.text.animation == AnimationType.typewriter
        ? widget.text.text.substring(0, (widget.text.text.length * t.clamp(0.0, 1.0)).round())
        : widget.text.text;

    final textStyle = isTitle
        ? GoogleFonts.unbounded(
            fontSize: widget.text.fontSize,
            fontWeight: FontWeight.w800,
            color: color,
            shadows: [
              Shadow(color: Colors.black.withOpacity(0.7), blurRadius: 8),
            ],
          )
        : GoogleFonts.manrope(
            fontSize: widget.text.fontSize,
            fontWeight: FontWeight.w600,
            color: color,
          );

    if (isTitle) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(shownText, textAlign: TextAlign.center, style: textStyle),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(shownText, textAlign: TextAlign.center, style: textStyle),
    );
  }
}

// ==========================================
// Менеджер текстов (bottom sheet)
// ==========================================
void showTextManagerSheet(BuildContext context, WidgetRef ref) {
  final project = ref.read(currentProjectProvider);

  if (project.photos.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Сначала добавьте фото'),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

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
            final texts = ref.read(currentProjectProvider).texts;
            final photos = ref.read(currentProjectProvider).photos;

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
                    'Текст на видео',
                    style: GoogleFonts.unbounded(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 16),

                  if (texts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Пока нет текста. Добавьте заголовок или субтитры.',
                        style: GoogleFonts.manrope(
                            fontSize: 14, color: AppColors.textMuted),
                      ),
                    )
                  else
                    ...List.generate(texts.length, (index) {
                      final t = texts[index];
                      final frame =
                          frameIndexForMs(photos, t.startTimeMilliseconds);
                      final isTitle = t.fontFamily == 'Unbounded';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isTitle ? Icons.title : Icons.subtitles_outlined,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.text,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.manrope(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary),
                                  ),
                                  Text(
                                    '${isTitle ? 'Заголовок' : 'Субтитры'} • кадр ${frame + 1}',
                                    style: GoogleFonts.manrope(
                                        fontSize: 11,
                                        color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: AppColors.textSecondary, size: 20),
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                showTextEditorDialog(context, ref, index);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: AppColors.error, size: 20),
                              onPressed: () {
                                ref
                                    .read(currentProjectProvider.notifier)
                                    .removeText(index);
                                setSheetState(() {});
                              },
                            ),
                          ],
                        ),
                      );
                    }),

                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        showTextEditorDialog(context, ref, null);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.add),
                      label: Text(
                        'Добавить текст',
                        style: GoogleFonts.manrope(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
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
// Диалог создания / редактирования текста
// ==========================================
void showTextEditorDialog(
    BuildContext context, WidgetRef ref, int? editIndex) {
  final project = ref.read(currentProjectProvider);
  final existing = editIndex != null && editIndex < project.texts.length
      ? project.texts[editIndex]
      : null;

  final controller = TextEditingController(text: existing?.text ?? '');
  String style = existing?.fontFamily ?? 'Unbounded';
  AnimationType animation = existing?.animation ?? AnimationType.fadeIn;
  int colorValue = existing?.colorValue ?? 0xFFFFFFFF;
  double fontSize = existing?.fontSize ?? (style == 'Unbounded' ? 28.0 : 16.0);
  double positionX = existing?.positionX ?? 0.5;

  const swatches = <int>[
    0xFFFFFFFF, 0xFF000000, 0xFFD946EF, 0xFFF59E0B,
    0xFFEF4444, 0xFF10B981, 0xFF3B82F6, 0xFFEC4899,
    0xFF8B5CF6, 0xFF14B8A6,
  ];

  showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          editIndex == null ? 'Новый текст' : 'Редактировать текст',
          style: GoogleFonts.unbounded(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                maxLines: 3,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Введите текст…',
                  hintStyle: TextStyle(
                      color: AppColors.textMuted.withOpacity(0.6)),
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Стиль',
                  style: GoogleFonts.manrope(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Заголовок'),
                    selected: style == 'Unbounded',
                    onSelected: (_) => setDialogState(() {
                      style = 'Unbounded';
                      fontSize = 28.0;
                    }),
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceLight,
                    labelStyle: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: style == 'Unbounded'
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                    side: BorderSide(
                        color: style == 'Unbounded'
                            ? AppColors.primary
                            : AppColors.primary.withOpacity(0.3)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  ChoiceChip(
                    label: const Text('Субтитры'),
                    selected: style == 'Manrope',
                    onSelected: (_) => setDialogState(() {
                      style = 'Manrope';
                      fontSize = 16.0;
                    }),
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceLight,
                    labelStyle: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: style == 'Manrope'
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                    side: BorderSide(
                        color: style == 'Manrope'
                            ? AppColors.primary
                            : AppColors.primary.withOpacity(0.3)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Анимация',
                  style: GoogleFonts.manrope(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AnimationType.values.map((type) {
                  return ChoiceChip(
                    label: Text(_animationLabel(type)),
                    selected: animation == type,
                    onSelected: (_) =>
                        setDialogState(() => animation = type),
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceLight,
                    labelStyle: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: animation == type
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                    side: BorderSide(
                        color: animation == type
                            ? AppColors.primary
                            : AppColors.primary.withOpacity(0.3)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text('Цвет',
                  style: GoogleFonts.manrope(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: swatches.map((value) {
                  final isSelected = colorValue == value;
                  return GestureDetector(
                    onTap: () =>
                        setDialogState(() => colorValue = value),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(value),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : Colors.white24,
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text('Размер шрифта',
                  style: GoogleFonts.manrope(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 8),
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: AppColors.surfaceLight,
                        thumbColor: AppColors.primary,
                      ),
                      child: Slider(
                        value: fontSize,
                        min: 12,
                        max: 72,
                        divisions: 60,
                        onChanged: (value) {
                          setDialogState(() => fontSize = value);
                        },
                      ),
                    ),
                  ),
                  Text(
                    '${fontSize.toInt()}',
                    style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Выравнивание',
                  style: GoogleFonts.manrope(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Лево'),
                      selected: positionX == 0.25,
                      onSelected: (_) =>
                          setDialogState(() => positionX = 0.25),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surfaceLight,
                      labelStyle: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: positionX == 0.25
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                      side: BorderSide(
                          color: positionX == 0.25
                              ? AppColors.primary
                              : AppColors.primary.withOpacity(0.3)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Центр'),
                      selected: positionX == 0.5,
                      onSelected: (_) =>
                          setDialogState(() => positionX = 0.5),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surfaceLight,
                      labelStyle: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: positionX == 0.5
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                      side: BorderSide(
                          color: positionX == 0.5
                              ? AppColors.primary
                              : AppColors.primary.withOpacity(0.3)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Право'),
                      selected: positionX == 0.75,
                      onSelected: (_) =>
                          setDialogState(() => positionX = 0.75),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surfaceLight,
                      labelStyle: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: positionX == 0.75
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                      side: BorderSide(
                          color: positionX == 0.75
                              ? AppColors.primary
                              : AppColors.primary.withOpacity(0.3)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Отмена',
                style: GoogleFonts.manrope(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) return;

              final photos = ref.read(currentProjectProvider).photos;
              final frameIndex = ref
                  .read(selectedPhotoIndexProvider)
                  .clamp(0, photos.length - 1);

              int start;
              int end;
              if (existing != null) {
                start = existing.startTimeMilliseconds;
                end = existing.endTimeMilliseconds;
              } else {
                start = frameStartMs(photos, frameIndex);
                end = start + photos[frameIndex].durationMilliseconds;
              }

              final layer = TextLayer(
                text: trimmed,
                fontFamily: style,
                fontSize: fontSize,
                colorValue: colorValue,
                startTimeMilliseconds: start,
                endTimeMilliseconds: end,
                animation: animation,
                positionX: positionX,
                positionY: style == 'Unbounded' ? 0.15 : 0.85,
              );

              if (editIndex != null) {
                ref
                    .read(currentProjectProvider.notifier)
                    .updateText(editIndex, layer);
              } else {
                ref.read(currentProjectProvider.notifier).addText(layer);
              }
              Navigator.pop(dialogContext);
            },
            child: Text('Сохранить',
                style: GoogleFonts.manrope(color: AppColors.primary)),
          ),
        ],
      ),
    ),
  );
}

String _animationLabel(AnimationType type) {
  switch (type) {
    case AnimationType.none:
      return 'Нет';
    case AnimationType.fadeIn:
      return 'Фейд';
    case AnimationType.slideUp:
      return 'Снизу';
    case AnimationType.slideDown:
      return 'Сверху';
    case AnimationType.typewriter:
      return 'Печать';
  }
}