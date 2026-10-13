import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/colors.dart';
import '../../../data/services/media_storage_service.dart';
import 'empty_state.dart';

// ==========================================
// Вкладка "Фото": сетка с двумя режимами
// (выбор для проекта / превью)
// ==========================================
class PhotosTab extends StatelessWidget {
  final List<File> files;
  final ValueChanged<File> onDelete;
  final Set<String> selectedPaths;
  final ValueChanged<String> onToggleSelection;
  final bool selectionMode;
  final bool singleSelectMode;
  final void Function(List<String> photoPaths)? onUsePhoto;

  const PhotosTab({
    required this.files,
    required this.onDelete,
    required this.selectedPaths,
    required this.onToggleSelection,
    required this.selectionMode,
    required this.singleSelectMode,
    this.onUsePhoto,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const EmptyState(
        icon: Icons.photo_outlined,
        title: 'Фото пока нет',
        subtitle: 'Нажмите «📷» в шапке, чтобы загрузить фото',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final name = MediaStorageService.displayName(file);
        final size = MediaStorageService.formatBytes(file);
        final isSelected = selectedPaths.contains(file.path);

        return GestureDetector(
          onTap: selectionMode
              ? () => onToggleSelection(file.path)
              : () => _showPhotoPreview(context, file, name),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.2),
                width: isSelected ? 3 : 1,
              ),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10)),
                        child: Image.file(
                          file,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppColors.surfaceLight,
                            child: const Icon(Icons.broken_image,
                                color: AppColors.error),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  size,
                                  style: GoogleFonts.manrope(
                                    fontSize: 10,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // ✅ КНОПКА ➕ БЕЗ ЗАКРЫТИЯ МЕДИАТЕКИ (режим редактора)
                          if (singleSelectMode && onUsePhoto != null)
                            _AddPhotoButton(
                              onAdd: () => onUsePhoto!([file.path]),
                            ),
                          // ✅ ПЛЮС/ГАЛОЧКА в режиме создания проекта
                          if (!singleSelectMode && selectionMode)
                            _SelectToggleButton(
                              isSelected: isSelected,
                              onToggle: () => onToggleSelection(file.path),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppColors.error, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            onPressed: () => onDelete(file),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Галочка выбора (только в режиме множественного выбора)
                if (!singleSelectMode && selectionMode && isSelected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.check,
                          color: Colors.white, size: 18),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPhotoPreview(BuildContext context, File file, String name) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(file, fit: BoxFit.contain),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton(
                icon: const Icon(Icons.close,
                    color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(ctx),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// ✅ Кнопка выбора фото в режиме создания проекта
// ==========================================
class _SelectToggleButton extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onToggle;

  const _SelectToggleButton({
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        isSelected ? Icons.check_circle : Icons.add_circle_outline,
        color: isSelected ? Colors.green : AppColors.primary,
        size: 20,
      ),
      tooltip: isSelected ? 'Убрать из выбора' : 'Выбрать фото',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onToggle,
    );
  }
}

// ==========================================
// ✅ Кнопка добавления фото (не закрывает медиатеку)
// ==========================================
class _AddPhotoButton extends StatefulWidget {
  final VoidCallback onAdd;

  const _AddPhotoButton({required this.onAdd});

  @override
  State<_AddPhotoButton> createState() => _AddPhotoButtonState();
}

class _AddPhotoButtonState extends State<_AddPhotoButton> {
  bool _added = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    widget.onAdd();
    setState(() => _added = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _added = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _added ? Icons.check_circle : Icons.add_circle_outline,
        color: _added ? Colors.green : AppColors.primary,
        size: 20,
      ),
      tooltip: 'Добавить в проект',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: _handleTap,
    );
  }
}