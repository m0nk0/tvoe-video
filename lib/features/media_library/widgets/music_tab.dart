import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/theme/colors.dart';
import '../../../data/services/media_storage_service.dart';
import 'empty_state.dart';

// ==========================================
// Вкладка "Музыка": список треков медиатеки
// с превью-воспроизведением
// ==========================================
class MusicTab extends StatelessWidget {
  final List<File> files;
  final ValueChanged<File> onDelete;
  final ValueChanged<String> onPlay;
  final VoidCallback onStop;
  final String? playingPath;
  final AudioPlayer? player;
  final ValueChanged<File>? onUse;

  const MusicTab({
    required this.files,
    required this.onDelete,
    required this.onPlay,
    required this.onStop,
    required this.playingPath,
    required this.player,
    this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const EmptyState(
        icon: Icons.music_note_outlined,
        title: 'Музыки пока нет',
        subtitle: 'Нажмите «🎵» в шапке, чтобы загрузить треки',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: files.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final file = files[index];
        final name = MediaStorageService.displayName(file);
        final size = MediaStorageService.formatBytes(file);
        final isPlaying = playingPath == file.path &&
            player != null &&
            player!.playing;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isPlaying
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: 0.1),
              width: isPlaying ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => onPlay(file.path),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: AppColors.primary,
                    size: 28,
                  ),
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
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      size,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (onUse != null)
                IconButton(
                  icon: const Icon(Icons.add_circle_outline,
                      color: AppColors.primary, size: 22),
                  tooltip: 'Добавить в проект',
                  onPressed: () => onUse!(file),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.error, size: 22),
                onPressed: () => onDelete(file),
              ),
            ],
          ),
        );
      },
    );
  }
}