import 'dart:io';
import 'dart:math' as math;

import 'package:android_intent_plus/android_intent.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/beat_detector.dart';
import '../../data/models/audio_track.dart';
import '../../data/providers/audio_provider.dart';
import '../../data/providers/project_provider.dart';
import '../../data/services/bundled_music_service.dart';
import '../../data/services/media_storage_service.dart';

String _fmtSec(double sec) {
  final total = sec.round();
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

int _totalVideoDurationMs(WidgetRef ref) {
  return ref
      .read(currentProjectProvider)
      .photos
      .fold<int>(0, (sum, p) => sum + p.durationMilliseconds);
}

bool isPlayerLoadedWith(AudioPlayer player, String path) {
  final src = player.audioSource;
  if (src is UriAudioSource) {
    return src.uri == Uri.file(path);
  }
  return false;
}

// ==========================================
// ✅ Единая точка входа: умный выбор музыки
// ==========================================
void showMusicSourcePicker(BuildContext context, WidgetRef ref) {
  final track = ref.read(currentProjectProvider).audioTrack;
  if (track != null) {
    showAudioManagerSheet(context, ref);
    return;
  }
  _showMusicSourceSheet(context, ref);
}

// ==========================================
// ✅ Применение трека
// ==========================================
Future<void> _applyTrack(
  BuildContext context,
  WidgetRef ref,
  AudioTrack track, {
  required bool openEditor,
}) async {
  final player = ref.read(audioPlayerProvider);
  try {
    try {
      await player.stop();
    } catch (_) {}
    ref.read(isAudioPlayingProvider.notifier).state = false;

    final stored = await _storeTrack(ref, track);
    ref.read(currentProjectProvider.notifier).setAudioTrack(stored);

    if (context.mounted) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Музыка «${stored.title}» добавлена в проект'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      if (openEditor) {
        showAudioManagerSheet(context, ref);
      }
    }
  } catch (e) {
    print('❌ Ошибка применения трека: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Ошибка добавления музыки: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// ==========================================
// ✅ Loading-диалог: Material + явный стиль
// ==========================================
Widget _loadingDialog(String text) {
  return Material(
    type: MaterialType.transparency,
    child: Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              text,
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: AppColors.textPrimary,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ==========================================
// Лист выбора источника музыки (когда трека ещё нет)
// ==========================================
void _showMusicSourceSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return SafeArea(
        child: Padding(
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
                'Добавить музыку',
                style: GoogleFonts.unbounded(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Выберите, откуда взять трек',
                style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              _SourceTile(
                icon: Icons.library_music,
                iconColor: Colors.green,
                title: 'Музыка на устройстве',
                subtitle: 'Папки Music, Download и другие',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showDeviceMusicSheet(context, ref, openEditorAfter: true);
                },
              ),
              const SizedBox(height: 12),
              _SourceTile(
                icon: Icons.album_outlined,
                iconColor: Colors.blue,
                title: 'Из медиатеки',
                subtitle: 'Загруженные ранее и встроенные треки',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showMediaLibraryMusicSheet(context, ref, openEditorAfter: true);
                },
              ),
              const SizedBox(height: 12),
              _SourceTile(
                icon: Icons.folder_open,
                iconColor: Colors.orange,
                title: 'Другая папка',
                subtitle: 'Выбрать файл вручную',
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final track = await pickAudioFromDevice();
                  if (track != null && context.mounted) {
                    await _applyTrack(context, ref, track, openEditor: true);
                  }
                },
              ),
              const SizedBox(height: 12),
              _SourceTile(
                icon: Icons.cloud_download,
                iconColor: Colors.purple,
                title: 'Из интернета',
                subtitle: 'Скачать по URL',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showUrlInputDialog(context, ref, openEditorAfter: true);
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

// ==========================================
// ✅ ПАНЕЛЬ «МУЗЫКА» (редактор)
// Источники открываются ПОВЕРХ панели (без pop → без мёртвых контекстов)
// ==========================================
void showAudioManagerSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      final systemBottomInset = MediaQuery.of(sheetContext).padding.bottom;
      final project = ref.read(currentProjectProvider);
      final canSyncBeat =
          project.audioTrack != null && project.photos.isNotEmpty;

      return SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: systemBottomInset),
        child: SingleChildScrollView(
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
                'Музыка',
                style: GoogleFonts.unbounded(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    // ✅ НЕ закрываем панель: список ляжет поверх
                    _showDeviceMusicSheet(sheetContext, ref, openEditorAfter: false);
                  },
                  icon: const Icon(Icons.library_music),
                  label: const Text('Музыка на устройстве'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    // ✅ НЕ закрываем панель: список ляжет поверх
                    _showMediaLibraryMusicSheet(sheetContext, ref, openEditorAfter: false);
                  },
                  icon: const Icon(Icons.album_outlined),
                  label: const Text('Из медиатеки'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceLight,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final track = await pickAudioFromDevice();
                        if (track != null && sheetContext.mounted) {
                          await _applyTrack(sheetContext, ref, track, openEditor: false);
                        }
                      },
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Другая папка'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _showUrlInputDialog(sheetContext, ref, openEditorAfter: false);
                      },
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('Из интернета'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: canSyncBeat
                      ? () => _syncToBeat(sheetContext, ref)
                      : null,
                  icon: const Icon(Icons.graphic_eq),
                  label: const Text('Синхронизировать по битам'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceLight,
                    foregroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.surfaceLight,
                    disabledForegroundColor: AppColors.textMuted,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (!canSyncBeat)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Нужны фото на таймлайне и музыка в проекте',
                    style: GoogleFonts.manrope(fontSize: 11, color: AppColors.textMuted),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await _openSystemFileManager(context);
                  },
                  icon: const Icon(Icons.folder_special_outlined, size: 20),
                  label: const Text('Открыть «Мои файлы»'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const _CurrentTrackWidget(),
              const SizedBox(height: 16),
              Consumer(
                builder: (context, ref2, _) {
                  final hasTrack =
                      ref2.watch(currentProjectProvider).audioTrack != null;
                  if (!hasTrack) return const SizedBox.shrink();
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Музыка применена'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      icon: const Icon(Icons.check, size: 22),
                      label: Text(
                        'Применить',
                        style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  ).whenComplete(() {
    if (!ref.read(isPlayingProvider)) {
      ref.read(audioPlayerProvider).stop();
      ref.read(isAudioPlayingProvider.notifier).state = false;
    }
  });
}

// ==========================================
// Список треков медиатеки
// ==========================================
Future<void> _showMediaLibraryMusicSheet(
  BuildContext context,
  WidgetRef ref, {
  required bool openEditorAfter,
}) async {
  final storage = ref.read(mediaStorageProvider);
  final files = storage.listMusic();

  await showModalBottomSheet(
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Column(
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
                    'Из медиатеки',
                    style: GoogleFonts.unbounded(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    files.isEmpty ? 'Медиатека пуста' : 'Треков: ${files.length}',
                    style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: files.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.music_off, size: 48, color: AppColors.textMuted),
                          SizedBox(height: 12),
                          Text('Сначала загрузи треки',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted)),
                        ]),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: files.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
                      itemBuilder: (context, index) {
                        final file = files[index];
                        final name = MediaStorageService.displayName(file);
                        final isBundled = BundledMusicService.isBundled(file);
                        return InkWell(
                          onTap: () {
                            Navigator.pop(sheetContext);
                            final track = AudioTrack(
                              filePath: file.path,
                              title: name,
                              isFromInternet: false,
                            );
                            _applyTrack(context, ref, track, openEditor: openEditorAfter);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isBundled ? Icons.auto_awesome : Icons.music_note,
                                    color: AppColors.primary,
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
                                      const SizedBox(height: 2),
                                      Text(
                                        isBundled
                                            ? '✨ Встроенный'
                                            : MediaStorageService.formatBytes(file),
                                        style: GoogleFonts.manrope(
                                            fontSize: 11, color: AppColors.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right, color: AppColors.textMuted),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}

// ==========================================
// Список треков с устройства
// ==========================================
Future<void> _showDeviceMusicSheet(
  BuildContext context,
  WidgetRef ref, {
  required bool openEditorAfter,
}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _loadingDialog('Поиск музыки…'),
  );

  final granted = await requestAudioPermission();
  final tracks = granted ? await scanDeviceMusic() : <AudioTrack>[];

  if (!context.mounted) return;
  Navigator.pop(context);

  if (!granted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Нет разрешения на чтение музыки'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 5),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Column(
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
                    'Музыка на устройстве',
                    style: GoogleFonts.unbounded(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tracks.isEmpty ? 'Ничего не найдено' : 'Найдено треков: ${tracks.length}',
                    style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: tracks.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.music_off, size: 48, color: AppColors.textMuted),
                          SizedBox(height: 12),
                          Text('Скопируйте музыку в папку Music или Download',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted)),
                        ]),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: tracks.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        final folder = _folderOf(track.filePath);
                        return InkWell(
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _applyTrack(context, ref, track, openEditor: openEditorAfter);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.music_note, color: AppColors.primary),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        track.title,
                                        style: GoogleFonts.manrope(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        folder,
                                        style: GoogleFonts.manrope(
                                            fontSize: 11, color: AppColors.textMuted),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right, color: AppColors.textMuted),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}

// ==========================================
// ✅ СИНХРОНИЗАЦИЯ ПО БИТАМ (регулярная сетка от BPM)
// nLong/nShort вычисляются из period, чтобы длинный кадр ≤ 4 с
// и короткий ≠ длинному (без схлопывания в однородность).
// ==========================================
Future<void> _syncToBeat(BuildContext context, WidgetRef ref) async {
  final project = ref.read(currentProjectProvider);
  final track = project.audioTrack;
  if (track == null || project.photos.isEmpty) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _loadingDialog('Анализирую биты…'),
  );

  final analysis = await BeatDetector.detectBeats(track.filePath);

  if (!context.mounted) return;
  Navigator.pop(context);

  if (!analysis.isValid) {
    if (kBeatDebug) {
      print('⚠️ sync: отклонено — битов ${analysis.beats.length}, bpm ${analysis.bpm}');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Не удалось определить биты в этом треке'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
    return;
  }

  final beats = analysis.beats;

  // Регулярная сетка из нормализованного BPM
  double period = analysis.bpm > 0 ? 60.0 / analysis.bpm : 1.0;
  period = period.clamp(0.35, 2.0);
  final double phase = beats.isNotEmpty ? (beats.first % period) : 0.0;

  const double maxDur = 4.0;
  const double minDur = 0.8;

  // ✅ Counts из period: длинный влезает в потолок, короткий = 60% длинного
  final int nLong = math.max(2, (maxDur / period).floor());
  final int nShort = math.max(1, (nLong * 0.6).round());
  final List<int> pattern = [nShort, nLong, nShort, nLong];

  if (kBeatDebug) {
    print('🎬 sync: трек=${track.title}, BPM=${analysis.bpm.toStringAsFixed(1)}, '
        'period=${period.toStringAsFixed(2)}с, phase=${phase.toStringAsFixed(2)}с, '
        'nShort=$nShort, nLong=$nLong, maxDur=$maxDur (grid-режим)');
  }

  final notifier = ref.read(currentProjectProvider.notifier);
  notifier.beginBatch();
  try {
    int synced = 0;
    double currentTime = 0;

    for (int i = 0; i < project.photos.length; i++) {
      final int n = pattern[i % pattern.length];
      double dur = n * period + (i == 0 ? phase : 0.0);
      dur = dur.clamp(minDur, maxDur);

      notifier.updatePhotoDuration(i, (dur * 1000).round());
      currentTime += dur;
      synced++;

      if (kBeatDebug) {
        print('🎬 sync: кадр $i → $n×period = ${dur.toStringAsFixed(2)}с '
            '(граница ${currentTime.toStringAsFixed(2)}с)');
      }
    }

    if (context.mounted) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '⚡ Синхронизировано кадров: $synced • BPM ~${analysis.bpm.round()}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  } finally {
    notifier.endBatch();
  }
}

String _folderOf(String path) {
  final parts = path.split('/');
  if (parts.length < 2) return path;
  return parts[parts.length - 2];
}

// ==========================================
// Системный файловый менеджер
// ==========================================
Future<void> _openSystemFileManager(BuildContext context) async {
  final intent = AndroidIntent(
    action: 'android.intent.action.VIEW',
    data: 'content://com.android.externalstorage.documents/root/primary',
  );
  try {
    await intent.launch();
    return;
  } catch (e) {
    print('DocumentsUI не запустился: $e');
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Не удалось открыть проводник.'),
        backgroundColor: Colors.orange,
      ),
    );
  }
}

// ==========================================
// Копирование трека в папку проекта music/
// ==========================================
Future<AudioTrack> _storeTrack(WidgetRef ref, AudioTrack track) async {
  final storage = ref.read(mediaStorageProvider);
  final musicDirPath = storage.musicDir.path;

  if (track.filePath.startsWith(musicDirPath)) return track;

  final storedPath = await storage.importMusic(track.filePath, title: track.title);

  if (storedPath == null || storedPath.isEmpty) {
    throw Exception('importMusic вернул пустой путь');
  }

  if (track.isFromInternet) {
    try {
      final original = File(track.filePath);
      if (original.existsSync()) original.deleteSync();
    } catch (_) {}
  }

  return track.copyWith(filePath: storedPath);
}

// ==========================================
// Ввод URL для скачивания
// ==========================================
void _showUrlInputDialog(
  BuildContext context,
  WidgetRef ref, {
  required bool openEditorAfter,
}) {
  final controller = TextEditingController();

  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Скачать из интернета',
        style: GoogleFonts.unbounded(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      content: TextField(
        controller: controller,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Вставьте URL аудиофайла…',
          hintStyle: TextStyle(color: AppColors.textMuted.withOpacity(0.6)),
          filled: true,
          fillColor: AppColors.surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('Отмена', style: GoogleFonts.manrope(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          onPressed: () async {
            final url = controller.text.trim();
            if (url.isEmpty) return;
            Navigator.pop(dialogContext);

            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => _loadingDialog('Скачивание…'),
            );

            final track = await downloadAudioFromUrl(url);

            if (context.mounted) {
              Navigator.pop(context);
              if (track != null) {
                await _applyTrack(context, ref, track, openEditor: openEditorAfter);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ошибка скачивания'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: Text('Скачать', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

// ==========================================
// Текущий трек проекта + регулировки
// ==========================================
class _CurrentTrackWidget extends ConsumerWidget {
  const _CurrentTrackWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(currentProjectProvider);
    final track = project.audioTrack;
    final player = ref.read(audioPlayerProvider);
    final isPlaying = ref.watch(isAudioPlayingProvider);

    if (track == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Музыка не добавлена',
            style: GoogleFonts.manrope(color: AppColors.textMuted),
          ),
        ),
      );
    }

    final totalSec = project.totalDurationMs / 1000.0;
    final maxStart = totalSec > 0 ? totalSec : 30.0;
    final clampedStart = track.startTime.clamp(0.0, maxStart);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.music_note, color: AppColors.primary, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  track.title,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () async {
                  if (isPlaying) {
                    await player.pause();
                    ref.read(isAudioPlayingProvider.notifier).state = false;
                  } else {
                    if (!isPlayerLoadedWith(player, track.filePath)) {
                      try {
                        await player.setFilePath(track.filePath);
                      } catch (e) {
                        print('❌ Ошибка загрузки трека: $e');
                        return;
                      }
                    }
                    await player.setVolume(track.volume);
                    await player.play();
                    ref.read(isAudioPlayingProvider.notifier).state = true;
                  }
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: () async {
                  await player.stop();
                  ref.read(isAudioPlayingProvider.notifier).state = false;
                  ref.read(currentProjectProvider.notifier).removeAudioTrack();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          StreamBuilder<Duration>(
            stream: player.positionStream,
            builder: (context, posSnap) {
              return StreamBuilder<Duration?>(
                stream: player.durationStream,
                builder: (context, durSnap) {
                  return ProgressBar(
                    progress: posSnap.data ?? Duration.zero,
                    total: durSnap.data ?? Duration.zero,
                    onSeek: (d) => player.seek(d),
                    progressBarColor: AppColors.primary,
                    baseBarColor: AppColors.surfaceLight,
                    thumbColor: AppColors.primary,
                    timeLabelTextStyle: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.volume_down, color: AppColors.textMuted, size: 20),
              Expanded(
                child: Slider(
                  value: track.volume,
                  min: 0.0,
                  max: 1.0,
                  activeColor: AppColors.primary,
                  inactiveColor: AppColors.surfaceLight,
                  onChanged: (value) {
                    ref.read(currentProjectProvider.notifier).updateAudioVolume(value);
                    player.setVolume(value);
                  },
                ),
              ),
              const Icon(Icons.volume_up, color: AppColors.textMuted, size: 20),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                child: Text(
                  '${(track.volume * 100).round()}%',
                  style: GoogleFonts.jetBrainsMono(fontSize: 12, color: AppColors.primary),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.schedule, color: AppColors.textMuted, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Задержка старта',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Text(
                '${_fmtSec(clampedStart)} / ${_fmtSec(maxStart)}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Через сколько секунд видео начнёт играть трек',
              style: GoogleFonts.manrope(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
          Slider(
            value: clampedStart,
            min: 0.0,
            max: maxStart > 0 ? maxStart : 1.0,
            divisions: maxStart > 0 ? (maxStart * 2).round() : 1,
            activeColor: AppColors.primary,
            inactiveColor: AppColors.surfaceLight,
            onChanged: (value) {
              ref.read(currentProjectProvider.notifier).updateAudioStartTime(value);
            },
          ),
        ],
      ),
    );
  }
}

// ==========================================
// Публичная обёртка: браузер музыки устройства (для медиатеки)
// ==========================================
Future<void> showDeviceMusicBrowser(
  BuildContext context,
  WidgetRef ref, {
  bool importOnly = false,
}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _loadingDialog('Поиск музыки…'),
  );

  final granted = await requestAudioPermission();
  final tracks = granted ? await scanDeviceMusic() : <AudioTrack>[];

  if (!context.mounted) return;
  Navigator.pop(context);

  if (!granted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Нет разрешения на чтение музыки'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 4),
      ),
    );
    return;
  }

  await showModalBottomSheet(
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Column(
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
                    'Музыка на устройстве',
                    style: GoogleFonts.unbounded(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tracks.isEmpty ? 'Ничего не найдено' : 'Найдено треков: ${tracks.length}',
                    style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: tracks.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.music_off, size: 48, color: AppColors.textMuted),
                          SizedBox(height: 12),
                          Text('Скопируйте музыку в папку Music или Download',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted)),
                        ]),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: tracks.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        final folder = _folderOf(track.filePath);
                        return InkWell(
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            if (importOnly) {
                              try {
                                final stored = await _storeTrack(ref, track);
                                if (context.mounted) {
                                  HapticFeedback.mediumImpact();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('🎵 «${stored.title}» добавлен в медиатеку'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('❌ Ошибка импорта: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            } else {
                              await _applyTrack(context, ref, track, openEditor: false);
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.music_note, color: AppColors.primary),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        track.title,
                                        style: GoogleFonts.manrope(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        folder,
                                        style: GoogleFonts.manrope(
                                            fontSize: 11, color: AppColors.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right, color: AppColors.textMuted),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}

// ==========================================
// Плитка источника
// ==========================================
class _SourceTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 22),
          ],
        ),
      ),
    );
  }
}