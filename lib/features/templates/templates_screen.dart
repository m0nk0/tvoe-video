import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/default_templates.dart';
import '../../core/theme/colors.dart';
import '../../data/models/template.dart';
import '../../data/providers/project_provider.dart';
import '../../data/providers/projects_provider.dart';
import '../editor/editor_screen.dart';

/// Провайдер выбранной категории
final selectedCategoryProvider = StateProvider<String>((ref) => 'Все');

class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final templates = DefaultTemplates.byCategory(selectedCategory);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Шаблоны',
          style: GoogleFonts.unbounded(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // Горизонтальный скролл категорий
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: DefaultTemplates.categories.length,
              itemBuilder: (context, index) {
                final category = DefaultTemplates.categories[index];
                final isSelected = category == selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => ref.read(selectedCategoryProvider.notifier).state = category,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        category,
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // Grid шаблонов
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.75,
                ),
                itemCount: templates.length,
                itemBuilder: (context, index) {
                  return _TemplateCard(
                    template: templates[index],
                    onTap: () => _showTemplatePreview(context, ref, templates[index]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTemplatePreview(BuildContext context, WidgetRef ref, Template template) {
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ручка
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
                  template.name,
                  style: GoogleFonts.unbounded(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        template.category,
                        style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${DefaultTemplates.categoryEmoji(template.category)} ${(template.photoDurationMilliseconds / 1000).toStringAsFixed(1)}с/кадр',
                      style: GoogleFonts.jetBrainsMono(fontSize: 12, color: AppColors.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _getTemplateDescription(template.id),
                  style: GoogleFonts.manrope(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _useTemplate(context, ref, template);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.add_photo_alternate),
                    label: Text(
                      'Использовать шаблон',
                      style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getTemplateDescription(String templateId) {
    switch (templateId) {
      case 'dynamic':
        return 'Быстрые переходы для энергичных видео. Идеально для путешествий, спорта и динамичных моментов.';
      case 'romantic':
        return 'Мягкие плавные переходы для нежных историй. Свадьбы, романтические поездки, семейные моменты.';
      case 'minimal':
        return 'Чистый стиль без лишних эффектов. Для продуктовой съёмки, портфолио, минималистичных историй.';
      default:
        return 'Универсальный шаблон для любых видео.';
    }
  }

  void _useTemplate(BuildContext context, WidgetRef ref, Template template) {
    // Создаём новый проект с настройками шаблона
    ref.read(currentProjectProvider.notifier).clearProject();
    ref.read(selectedPhotoIndexProvider.notifier).state = 0;

    // Переходим в редактор
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const EditorScreen()),
    );

    // Показываем подсказку
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Шаблон "${template.name}" применён. Добавьте фото!'),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ==========================================
// Карточка шаблона
// ==========================================
class _TemplateCard extends StatelessWidget {
  final Template template;
  final VoidCallback onTap;

  const _TemplateCard({required this.template, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    DefaultTemplates.categoryEmoji(template.category),
                    style: const TextStyle(fontSize: 48),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      template.name,
                      style: GoogleFonts.unbounded(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      template.category,
                      style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}