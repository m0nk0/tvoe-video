import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/colors.dart';

class EditorToolbar extends StatelessWidget {
  final VoidCallback onAddPhoto;
  final VoidCallback onAddText;
  final VoidCallback onAddAudio;
  final VoidCallback onOpenEffects;
  final VoidCallback onOpenTransitions;
  final VoidCallback onCrop;
  final VoidCallback onOpenOverlays;
  final VoidCallback onOpenLiveMotion;
  final VoidCallback onOpenHarmonize; // 🆕 НОВОЕ

  const EditorToolbar({
    super.key,
    required this.onAddPhoto,
    required this.onAddText,
    required this.onAddAudio,
    required this.onOpenEffects,
    required this.onOpenTransitions,
    required this.onCrop,
    required this.onOpenOverlays,
    required this.onOpenLiveMotion,
    required this.onOpenHarmonize, // 🆕 НОВОЕ
  });

  @override
  Widget build(BuildContext context) {
    final tools = [
      {'icon': Icons.add_photo_alternate, 'label': 'Фото', 'action': onAddPhoto},
      {'icon': Icons.content_cut, 'label': 'Обрезать', 'action': onCrop},
      {'icon': Icons.music_note, 'label': 'Музыка', 'action': onAddAudio},
      {'icon': Icons.auto_fix_high, 'label': 'Эффекты', 'action': onOpenEffects},
      {'icon': Icons.auto_awesome, 'label': 'AI', 'action': onOpenHarmonize}, // 🆕 НОВОЕ
      {'icon': Icons.text_fields, 'label': 'Текст', 'action': onAddText},
      {'icon': Icons.compare_arrows, 'label': 'Переходы', 'action': onOpenTransitions},
      {'icon': Icons.layers_outlined, 'label': 'Оверлеи', 'action': onOpenOverlays},
      {'icon': Icons.motion_photos_on, 'label': 'Движение', 'action': onOpenLiveMotion},
    ];

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: tools.length,
      itemBuilder: (context, index) {
        final tool = tools[index];
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: tool['action'] as VoidCallback,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Icon(tool['icon'] as IconData, color: AppColors.primary, size: 24),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tool['label'] as String,
                style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }
}