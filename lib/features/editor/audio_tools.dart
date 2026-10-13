import 'dart:io';
import 'dart:math' as math;

import 'package:android_intent_plus/android_intent.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
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

/// Формат секунд: "0:05" или "1:23"
String _fmtSec(double sec) {
  final total = sec.round();
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Общая длительность видео проекта в миллисекундах
int _totalVideoDurationMs(WidgetRef ref) {
  return ref
      .read(currentProjectProvider)
      .photos
      .fold<int>(0, (sum, p) => sum + p.durationMilliseconds);
}

// ==========================================
// ✅ Проверка: загружен ли в плеер указанный файл
// ==========================================
bool isPlayerLoadedWith(AudioPlayer player, String path) {
  final src = player.audioSource;
  if (src is UriAudioSource) {
    return src.uri == Uri.file(path);
  }
  return false;
}

// ==========================================
// Bottom sheet: управление музыкой
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
                    Navigator.pop(sheetContext);
                    _showDeviceMusicSheet(context, ref);
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

              // ✅ ИЗ МЕДИАТЕКИ (встроенные + импортированные треки)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _showMediaLibraryMusicSheet(context, ref);
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
                        Navigator.pop(sheetContext);
                        final track = await pickAudioFromDevice();
                        if (track != null && context.mounted) {
                          _showAudioPreviewDialog(context, ref, track);
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
                        Navigator.pop(sheetContext);
                        _showUrlInputDialog(context, ref);
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

              // ⚡ СИНХРОНИЗАЦИЯ ПО БИТАМ
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: canSyncBeat
                      ? () {
                          Navigator.pop(sheetContext);
                          _syncToBeat(context, ref);
                        }
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
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
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
                  label: const Text('Открыть «Мои файлы» (скопировать файлы)'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const _CurrentTrackWidget(),
            ],
          ),
        ),
      );
    },
  ).whenComplete(() {
    // ✅ Останавливаем превью-плеер ТОЛЬКО если превью редактора не играет
    if (!ref.read(isPlayingProvider)) {
      ref.read(audioPlayerProvider).stop();
      ref.read(isAudioPlayingProvider.notifier).state = false;
    }
  });
}

// ==========================================
// ✅ Музыка из медиатеки (встроенные + импортированные треки)
// ==========================================
Future<void> _showMediaLibraryMusicSheet(
    BuildContext context, WidgetRef ref) async {
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
                    files.isEmpty
                        ? 'Медиатека пуста — загрузи треки кнопкой 🎵'
                        : 'Треков: ${files.length}',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: files.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.music_off,
                                size: 48, color: AppColors.textMuted),
                            const SizedBox(height: 12),
                            Text(
                              'Сначала загрузи музыку в медиатеку',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: files.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 68),
                      itemBuilder: (context, index) {
                        final file = files[index];
                        final name = MediaStorageService.displayName(file);
                        final isBundled = BundledMusicService.isBundled(file);
                        return ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isBundled
                                  ? Icons.auto_awesome
                                  : Icons.music_note,
                              color: AppColors.primary,
                            ),
                          ),
                          title: Text(
                            name,
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            isBundled
                                ? '✨ Встроенный'
                                : MediaStorageService.formatBytes(file),
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right,
                              color: AppColors.textMuted),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            final track = AudioTrack(
                              filePath: file.path,
                              title: name,
                              isFromInternet: false,
                            );
                            _showAudioPreviewDialog(context, ref, track);
                          },
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
// ⚡ Синхронизация длительностей кадров по битам музыки
// Каждый кадр = 2 бита
// ==========================================
Future<void> _syncToBeat(BuildContext context, WidgetRef ref) async {
  final project = ref.read(currentProjectProvider);
  final track = project.audioTrack;
  if (track == null || project.photos.isEmpty) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => Center(
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
            Text('Анализирую биты…',
                style: GoogleFonts.manrope(color: AppColors.textPrimary)),
          ],
        ),
      ),
    ),
  );

  final analysis = await BeatDetector.detectBeats(track.filePath);

  if (!context.mounted) return;
  Navigator.pop(context);

  if (!analysis.isValid) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Не удалось определить биты в этом треке'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
    return;
  }

  final notifier = ref.read(currentProjectProvider.notifier);
  const beatsPerPhoto = 2;
  final beats = analysis.beats;
  int synced = 0;

  for (int i = 0; i < project.photos.length; i++) {
    final startIdx = i * beatsPerPhoto;
    if (startIdx >= beats.length - 1) break;
    final endIdx = math.min((i + 1) * beatsPerPhoto, beats.length - 1);
    double sec = beats[endIdx] - beats[startIdx];
    sec = sec.clamp(0.8, 6.0);
    notifier.updatePhotoDuration(i, (sec * 1000).round());
    synced++;
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '⚡ Синхронизировано кадров: $synced • BPM ~${analysis.bpm.round()}'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

// ==========================================
// ✅ Встроенный список музыки устройства
// ==========================================
Future<void> _showDeviceMusicSheet(BuildContext context, WidgetRef ref) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (loadingContext) => Center(
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
            Text('Поиск музыки…',
                style: GoogleFonts.manrope(color: AppColors.textPrimary)),
          ],
        ),
      ),
    ),
  );

  final granted = await requestAudioPermission();
  final tracks = granted ? await scanDeviceMusic() : <AudioTrack>[];

  if (!context.mounted) return;
  Navigator.pop(context); // закрыть индикатор

  if (!granted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Нет разрешения на чтение музыки. '
            'Разрешите доступ в настройках приложения.'),
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
                    tracks.isEmpty
                        ? 'Ничего не найдено в папках Music и Download'
                        : 'Найдено треков: ${tracks.length}',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: tracks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.music_off,
                                size: 48, color: AppColors.textMuted),
                            const SizedBox(height: 12),
                            Text(
                              'Скопируйте музыку в папку Music или Download, '
                              'затем нажмите «Обновить»',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                _showDeviceMusicSheet(context, ref);
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Обновить'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: tracks.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 68),
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        final folder = _folderOf(track.filePath);
                        return ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.music_note,
                                color: AppColors.primary),
                          ),
                          title: Text(
                            track.title,
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            folder,
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right,
                              color: AppColors.textMuted),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _showAudioPreviewDialog(context, ref, track);
                          },
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

/// Короткое имя папки для подписи
String _folderOf(String path) {
  final parts = path.split('/');
  if (parts.length < 2) return path;
  return parts[parts.length - 2];
}

// ==========================================
// Открытие системного файлового менеджера
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

  try {
    final intent2 = AndroidIntent(
      action: 'android.intent.action.VIEW',
      data: 'file:///storage/emulated/0',
      type: 'resource/folder',
    );
    await intent2.launch();
    return;
  } catch (e) {
    print('file:// URI не сработал: $e');
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Не удалось открыть проводник.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 4),
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

  final storedPath =
      await storage.importMusic(track.filePath, title: track.title);

  if (track.isFromInternet) {
    try {
      final original = File(track.filePath);
      if (original.existsSync()) original.deleteSync();
    } catch (_) {}
  }

  return track.copyWith(filePath: storedPath);
}

// ==========================================
// Предпросмотр трека перед добавлением
// ==========================================
Future<void> _showAudioPreviewDialog(
    BuildContext context, WidgetRef ref, AudioTrack track) async {
  final player = ref.read(audioPlayerProvider);
  final totalVideoMs = _totalVideoDurationMs(ref);
  bool added = false;

  try {
    await player.setFilePath(track.filePath);
  } catch (e) {
    print('❌ Ошибка загрузки превью: $e');
  }

  await showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Предпросмотр',
        style: GoogleFonts.unbounded(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.music_note, size: 64, color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            track.title,
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
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
                  );
                },
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 18, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    totalVideoMs > 0
                        ? 'Длительность видео: ${_fmtSec(totalVideoMs / 1000)}. '
                            'Трек будет обрезан автоматически.'
                        : 'В видео пока нет кадров — трек ляжет с начала.',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(dialogContext);
          },
          child: Text('Отмена',
              style: GoogleFonts.manrope(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          onPressed: () async {
            added = true;
            await player.stop();
            ref.read(isAudioPlayingProvider.notifier).state = false;
            final stored = await _storeTrack(ref, track);
            ref.read(currentProjectProvider.notifier).setAudioTrack(stored);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: Text('Добавить',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

  await player.stop();
  ref.read(isAudioPlayingProvider.notifier).state = false;

  if (added && context.mounted) {
    showAudioManagerSheet(context, ref);
  }
}

// ==========================================
// Ввод URL для скачивания
// ==========================================
void _showUrlInputDialog(BuildContext context, WidgetRef ref) {
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
          child: Text('Отмена',
              style: GoogleFonts.manrope(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          onPressed: () async {
            final url = controller.text.trim();
            if (url.isEmpty) return;
            Navigator.pop(dialogContext);

            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (loadingContext) => Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                          color: AppColors.primary),
                      const SizedBox(height: 16),
                      Text('Скачивание…',
                          style:
                              GoogleFonts.manrope(color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ),
            );

            final track = await downloadAudioFromUrl(url);

            if (context.mounted) {
              Navigator.pop(context);
              if (track != null) {
                _showAudioPreviewDialog(context, ref, track);
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
          child: Text('Скачать',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

// ==========================================
// ✅ Текущий трек проекта на ГЛОБАЛЬНОМ плеере:
// живой прогресс-бар + play/pause + громкость + задержка
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

    // ✅ Максимальная задержка = длительность видео (или 30 сек, если кадров нет)
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
          // ---- Заголовок + play/pause + корзина ----
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
              // ✅ КРУПНАЯ КНОПКА PLAY/PAUSE (глобальный плеер)
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
                  ref
                      .read(currentProjectProvider.notifier)
                      .removeAudioTrack();
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ✅ ЖИВОЙ ПРОГРЕСС-БАР глобального плеера
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

          // ---- 🔊 Громкость ----
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
                    ref
                        .read(currentProjectProvider.notifier)
                        .updateAudioVolume(value);
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
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),

          // ---- ⏱ Задержка старта ----
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.schedule,
                      color: AppColors.textMuted, size: 18),
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
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
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
              ref
                  .read(currentProjectProvider.notifier)
                  .updateAudioStartTime(value);
            },
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 🎵 Публичная обёртка: браузер музыки устройства
// ==========================================
Future<void> showDeviceMusicBrowser(
  BuildContext context,
  WidgetRef ref, {
  bool importOnly = false,
}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (loadingContext) => Center(
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
            Text('Поиск музыки…',
                style: GoogleFonts.manrope(color: AppColors.textPrimary)),
          ],
        ),
      ),
    ),
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
                    tracks.isEmpty
                        ? 'Ничего не найдено'
                        : 'Найдено треков: ${tracks.length}',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: tracks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.music_off,
                                size: 48, color: AppColors.textMuted),
                            const SizedBox(height: 12),
                            Text(
                              'Скопируйте музыку в папку Music или Download',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: tracks.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 68),
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        final folder = _folderOf(track.filePath);
                        return ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.music_note,
                                color: AppColors.primary),
                          ),
                          title: Text(
                            track.title,
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            folder,
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right,
                              color: AppColors.textMuted),
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            await _pickTrack(
                                context, ref, track, importOnly);
                          },
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

/// Универсальный выбор трека: импорт в медиатеку или добавление в проект
Future<void> _pickTrack(BuildContext context, WidgetRef ref,
    AudioTrack track, bool importOnly) async {
  final player = ref.read(audioPlayerProvider);

  try {
    await player.setFilePath(track.filePath);
  } catch (e) {
    print('❌ Ошибка загрузки превью: $e');
  }

  bool added = false;

  await showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Предпросмотр',
        style: GoogleFonts.unbounded(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.music_note, size: 64, color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            track.title,
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
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
                  );
                },
              );
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text('Отмена',
              style: GoogleFonts.manrope(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          onPressed: () async {
            added = true;
            await player.stop();
            ref.read(isAudioPlayingProvider.notifier).state = false;
            final stored = await _storeTrack(ref, track);

            if (importOnly) {
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🎵 «${stored.title}» добавлен в медиатеку'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } else {
              ref.read(currentProjectProvider.notifier).setAudioTrack(stored);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: Text(importOnly ? 'В медиатеку' : 'Добавить',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

  await player.stop();
  ref.read(isAudioPlayingProvider.notifier).state = false;

  if (!importOnly && added && context.mounted) {
    showAudioManagerSheet(context, ref);
  }
}