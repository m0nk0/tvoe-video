import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/colors.dart';
import '../../data/models/video_project.dart';
import '../../data/providers/project_provider.dart';
import '../../data/providers/projects_provider.dart';
import '../editor/editor_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Твоё Видео',
          style: GoogleFonts.unbounded(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Мои проекты', style: Theme.of(context).textTheme.headlineLarge),
                if (projects.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '${projects.length}',
                      style: GoogleFonts.jetBrainsMono(fontSize: 12, color: AppColors.primary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: projects.isEmpty
                  ? const _EmptyState()
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.8,
                      ),
                      itemCount: projects.length,
                      itemBuilder: (context, index) {
                        return _ProjectCard(project: projects[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ref.read(currentProjectProvider.notifier).clearProject();
          ref.read(selectedPhotoIndexProvider.notifier).state = 0;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const EditorScreen()),
          );
        },
        backgroundColor: AppColors.primary,
        elevation: 4,
        icon: const Icon(Icons.add, size: 24, color: Colors.white),
        label: Text(
          'Создать',
          style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

// ==========================================
// Пустое состояние
// ==========================================
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.movie_creation_outlined, size: 64, color: AppColors.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            'Пока нет проектов',
            style: GoogleFonts.unbounded(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Нажмите "Создать", чтобы собрать своё первое видео',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 14, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// Карточка реального проекта
// ==========================================
class _ProjectCard extends ConsumerWidget {
  final VideoProject project;

  const _ProjectCard({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        ref.read(currentProjectProvider.notifier).loadProject(project);
        ref.read(selectedPhotoIndexProvider.notifier).state = 0;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const EditorScreen()),
        );
      },
      onLongPress: () => _showProjectMenu(context, ref),
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
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: project.photos.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(project.photos.first.imagePath),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: AppColors.textMuted),
                        ),
                      )
                    : const Center(child: Icon(Icons.image, size: 40, color: AppColors.textMuted)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDate(project.createdAt), style: Theme.of(context).textTheme.labelSmall),
                      Text(
                        project.formattedDuration,
                        style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.primary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  void _showProjectMenu(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      // Ручная высота системной панели (useSafeArea на этом устройстве не работает)
      final systemBottomInset = MediaQuery.of(sheetContext).padding.bottom;

      return SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: systemBottomInset),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
                title: Text('Переименовать', style: GoogleFonts.manrope(fontSize: 16, color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showRenameDialog(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: Text('Удалить', style: GoogleFonts.manrope(fontSize: 16, color: AppColors.error)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showDeleteDialog(context, ref);
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: project.name);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Переименовать',
          style: GoogleFonts.unbounded(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Название проекта',
            hintStyle: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.6)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.4))),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Отмена', style: GoogleFonts.manrope(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                ref.read(projectsProvider.notifier).rename(project.id, newName);
              }
              Navigator.pop(dialogContext);
            },
            child: Text('Сохранить', style: GoogleFonts.manrope(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Удалить проект?',
          style: GoogleFonts.unbounded(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        content: Text(
          '"${project.name}" будет удалён безвозвратно.',
          style: GoogleFonts.manrope(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Отмена', style: GoogleFonts.manrope(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              ref.read(projectsProvider.notifier).delete(project.id);
              Navigator.pop(dialogContext);
            },
            child: Text('Удалить', style: GoogleFonts.manrope(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}