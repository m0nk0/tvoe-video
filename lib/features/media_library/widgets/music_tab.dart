import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/theme/colors.dart';
import '../../../data/services/media_storage_service.dart';

class MusicTab extends StatelessWidget {
  final List<File> files;
  final void Function(File) onDelete;
  final void Function(String) onPlay;
  final void Function() onStop;
  final String? playingPath;
  final AudioPlayer? player;
  
  // ✅ НОВЫЕ ПАРАМЕТРЫ
  final String? selectedPath;
  final void Function(File) onSelect;

  const MusicTab({
    super.key,
    required this.files,
    required this.onDelete,
    required this.onPlay,
    required this.onStop,
    required this.playingPath,
    required this.player,
    this.selectedPath,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_off, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'Музыка пока не добавлена',
              style: GoogleFonts.manrope(fontSize: 16, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            Text(
              'Нажми 🎵 в правом верхнем углу',
              style: GoogleFonts.manrope(fontSize: 14, color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: files.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, index) {
        final file = files[index];
        final name = MediaStorageService.displayName(file);
        final isSelected = selectedPath == file.path;
        final isPlaying = playingPath == file.path;

        return InkWell(
          onTap: () {
            // ✅ При тапе просто выбираем и играем, НЕ применяем к проекту
            onSelect(file);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isSelected 
                  ? Border.all(color: AppColors.primary, width: 1.5) 
                  : null,
            ),
            child: Row(
              children: [
                // Иконка: Нота или Эквалайзер (если играет)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isPlaying ? Icons.equalizer : Icons.music_note,
                    color: isSelected ? Colors.white : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? AppColors.primary : AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        MediaStorageService.formatBytes(file),
                        style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                // Кнопка удаления
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 22),
                  onPressed: () => onDelete(file),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}