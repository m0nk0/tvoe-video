import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/colors.dart';
import '../../../data/services/media_storage_service.dart';
import '../clip_player_screen.dart';
import 'empty_state.dart';

// ==========================================
// Вкладка "Клипы": список экспортированных видео
// ==========================================
class ClipsTab extends StatelessWidget {
  final List<File> files;
  final ValueChanged<File> onDelete;
  final VoidCallback onRefresh;

  const ClipsTab({
    required this.files,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const EmptyState(
        icon: Icons.movie_outlined,
        title: 'Клипов пока нет',
        subtitle: 'Экспортируйте видео в редакторе — оно появится здесь',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final name = MediaStorageService.displayName(file);
        final size = MediaStorageService.formatBytes(file);
        final date = _formatDate(file.statSync().modified);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClipPlayerScreen(
                        filePath: file.path,
                        title: name,
                      ),
                    ),
                  );
                },
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(14)),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(Icons.videocam,
                            size: 64, color: Colors.white24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color:
                                AppColors.primary.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow,
                              size: 32, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
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
                            '$size • $date',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.share,
                          color: AppColors.primary, size: 22),
                      onPressed: () =>
                          Share.shareXFiles([XFile(file.path)]),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.error, size: 22),
                      onPressed: () => onDelete(file),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Формат даты: "7 окт"
String _formatDate(DateTime date) {
  const months = [
    'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
  ];
  return '${date.day} ${months[date.month - 1]}';
}