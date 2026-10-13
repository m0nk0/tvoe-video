import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/project_harmonizer.dart'; // 🆕 AI Гармонизация
import '../../data/models/video_format.dart';
import '../../data/providers/audio_provider.dart';
import '../../data/providers/project_provider.dart';
import '../../data/providers/projects_provider.dart';
import '../../data/providers/selection_provider.dart';
import '../export/export_screen.dart';
import '../media_library/media_library_screen.dart';
import '../smart/smart_montage_screen.dart';
import 'audio_tools.dart';
import 'crop/crop_editor_screen.dart';
import 'sheets/effects_sheet.dart';
import 'sheets/format_sheet.dart';
import 'sheets/live_motion_sheet.dart';
import 'sheets/overlays_sheet.dart';
import 'sheets/transitions_sheet.dart';
import 'text_tools.dart';
import 'widgets/preview_area.dart';
import 'widgets/timeline.dart';
import 'widgets/toolbar.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  double timelineZoom = 1.0;
  Timer? _tick;
  bool _mediaLibraryOpen = false;
  int? _pendingFormatId;
  double _lastPlayheadMs = 0;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final photos = ref.read(currentProjectProvider).photos;
      final total =
          photos.fold<int>(0, (s, p) => s + p.durationMilliseconds).toDouble();
      if (total <= 0) return;
      double ms = ref.read(playheadMsProvider) + 33;
      if (ms >= total) {
        ms = total;
        ref.read(isPlayingProvider.notifier).state = false;
      }
      ref.read(playheadMsProvider.notifier).state = ms;
    });
  }

  // ==========================================
  // 🔊 Аудио: единый глобальный плеер
  // ==========================================
  Future<void> _ensureTrackLoaded() async {
    final track = ref.read(currentProjectProvider).audioTrack;
    final player = ref.read(audioPlayerProvider);

    if (track == null) {
      await player.stop();
      return;
    }

    if (!isPlayerLoadedWith(player, track.filePath)) {
      try {
        await player.setFilePath(track.filePath);
        await player.setVolume(track.volume);
      } catch (e) {
        print('⚠️ Не удалось загрузить трек для превью: $e');
      }
    }
  }

  Future<void> _seekToPlayhead() async {
    final track = ref.read(currentProjectProvider).audioTrack;
    if (track == null) return;
    final player = ref.read(audioPlayerProvider);
    if (!isPlayerLoadedWith(player, track.filePath)) return;

    final playheadMs = ref.read(playheadMsProvider);
    final posMs = playheadMs - track.startTime * 1000;

    try {
      if (posMs < 0) {
        await player.pause();
        await player.seek(Duration.zero);
      } else {
        await player.seek(Duration(milliseconds: posMs.round()));
      }
    } catch (_) {}
  }

  Future<void> _startAudio() async {
    final track = ref.read(currentProjectProvider).audioTrack;
    if (track == null) return;

    await _ensureTrackLoaded();
    final player = ref.read(audioPlayerProvider);
    if (!isPlayerLoadedWith(player, track.filePath)) return;

    final playheadMs = ref.read(playheadMsProvider);
    final audioStartMs = track.startTime * 1000;
    if (playheadMs < audioStartMs) return;

    try {
      await player.setVolume(track.volume);
      await player.seek(
          Duration(milliseconds: (playheadMs - audioStartMs).round()));
      await player.play();
      ref.read(isAudioPlayingProvider.notifier).state = true;
    } catch (e) {
      print('⚠️ Ошибка запуска аудио: $e');
    }
  }

  Future<void> _pauseAudio() async {
    try {
      await ref.read(audioPlayerProvider).pause();
      ref.read(isAudioPlayingProvider.notifier).state = false;
    } catch (_) {}
  }

  // ==========================================
  //  Сохранение проекта
  // ==========================================
  Future<void> _saveProject({bool showSnackBar = false}) async {
    final project = ref.read(currentProjectProvider);
    final hasContent = project.photos.isNotEmpty ||
        project.texts.isNotEmpty ||
        project.audioTrack != null;

    if (!hasContent) {
      if (showSnackBar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нечего сохранять: добавьте фото, текст или музыку'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    try {
      await ref.read(projectRepositoryProvider).saveProject(project);
      ref.read(projectsProvider.notifier).refresh();
      print(
          '✅ ПРОЕКТ СОХРАНЁН: ${project.name} | фото: ${project.photos.length}');

      if (showSnackBar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('Проект сохранён')),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e, st) {
      print('❌ ОШИБКА СОХРАНЕНИЯ: $e');
      print(st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _saveAndPop() async {
    ref.read(isPlayingProvider.notifier).state = false;
    await _pauseAudio();
    await _saveProject();
    if (mounted) Navigator.of(context).pop();
  }

  // ==========================================
  //  📷 Шторка выбора источника фото (Галерея / Медиатека)
  // ==========================================
  void _showPhotoSourceSheet() {
    _pauseAudio();
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
                  'Добавить фото',
                  style: GoogleFonts.unbounded(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                _SourceTile(
                  icon: Icons.photo_library,
                  title: 'Галерея',
                  subtitle: 'Выбрать из галереи устройства',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    ref
                        .read(currentProjectProvider.notifier)
                        .addPhotosFromGallery();
                  },
                ),
                const SizedBox(height: 12),
                _SourceTile(
                  icon: Icons.photo_album_outlined,
                  title: 'Из медиатеки',
                  subtitle: 'Загруженные ранее фото',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _openMediaLibraryForPhotos();
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
  // 📷 Открытие медиатеки для выбора фото (мульти-режим)
  // ==========================================
  void _openMediaLibraryForPhotos() {
    _pauseAudio();
    _mediaLibraryOpen = true;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaLibraryScreen(
          singleSelectMode: false,
          onUsePhotos: (paths) {
            print('🎬 EDITOR: Добавляю ${paths.length} фото из медиатеки');
            final notifier = ref.read(currentProjectProvider.notifier);
            for (final path in paths) {
              notifier.addPhotoByPath(path);
            }
          },
        ),
      ),
    ).then((_) {
      _mediaLibraryOpen = false;
      if (_pendingFormatId != null && mounted) {
        final id = _pendingFormatId!;
        _pendingFormatId = null;
        showFormatSheet(context, ref, recommendedId: id);
      }
    });
  }

  // ==========================================
  // 🎬 Открытие медиатеки (для добавления музыки)
  // ==========================================
  void _openMediaLibrary() {
    _pauseAudio();
    _mediaLibraryOpen = true;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaLibraryScreen(
          singleSelectMode: true,
          onUseMusic: (track) {
            print('🎬 EDITOR: Добавляю музыку в проект');
            ref.read(currentProjectProvider.notifier).setAudioTrack(track);
          },
          onUsePhotos: (paths) {
            print('🎬 EDITOR: Добавляю ${paths.length} фото в проект');
            final notifier = ref.read(currentProjectProvider.notifier);
            for (final path in paths) {
              notifier.addPhotoByPath(path);
            }
          },
        ),
      ),
    ).then((_) {
      _mediaLibraryOpen = false;
      if (_pendingFormatId != null && mounted) {
        final id = _pendingFormatId!;
        _pendingFormatId = null;
        showFormatSheet(context, ref, recommendedId: id);
      }
    });
  }

  // ==========================================
  // ✂️ Кроп-редактор
  // ==========================================
  void _openCropEditor() {
    final selectedIndex = ref.read(selectedPhotoIndexProvider);
    final photos = ref.read(currentProjectProvider).photos;
    if (photos.isNotEmpty && selectedIndex < photos.length) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CropEditorScreen(photoIndex: selectedIndex),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала добавьте фото на таймлайн'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ==========================================
  // 🎨 Эффекты (мультивыбор)
  // ==========================================
  void _openEffects() {
    final selectedIndex = ref.read(selectedPhotoIndexProvider);
    final photos = ref.read(currentProjectProvider).photos;
    if (photos.isNotEmpty && selectedIndex < photos.length) {
      final targets = SelectionController(ref).targetIndices(selectedIndex);
      showEffectsSheet(context, ref, targets);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала добавьте фото на таймлайн'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ==========================================
  // 🔄 Переходы (мультивыбор)
  // ==========================================
  void _openTransitions() {
    final selectedIndex = ref.read(selectedPhotoIndexProvider);
    final photos = ref.read(currentProjectProvider).photos;
    if (photos.isNotEmpty && selectedIndex < photos.length) {
      final targets = SelectionController(ref).targetIndices(selectedIndex);
      showTransitionsSheet(context, ref, targets);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала добавьте фото на таймлайн'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ==========================================
  //  Оверлеи (стиль плёнки)
  // ==========================================
  void _openOverlays() {
    showOverlaysSheet(context, ref);
  }

  // ==========================================
  //  Живые фото (Ken Burns)
  // ==========================================
  void _openLiveMotion() {
    showLiveMotionSheet(context, ref);
  }

  // ==========================================
  //  AI Гармонизация всего проекта
  // ==========================================
  void _openHarmonize() {
    final photos = ref.read(currentProjectProvider).photos;
    if (photos.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сначала добавьте фото на таймлайн'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.yellowAccent),
            SizedBox(width: 8),
            Text('✨ AI Улучшение'),
          ],
        ),
        content: Text(
          'Приложение автоматически проанализирует все фото, выберет лучшее как эталон и выровняет цвета, яркость и контраст остальных кадров под него.\n\nЭто сделает ваш ролик профессиональным и цельным.',
          style: GoogleFonts.manrope(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              
              if (mounted) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => const Center(
                    child: Card(
                      color: AppColors.surface,
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Анализируем и улучшаем фото...'),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }

              try {
                final matrices = await ProjectHarmonizer.harmonizeProject(
                  photos,
                  (progress) {},
                );
                
                if (mounted) {
                  Navigator.pop(context); // Закрываем индикатор загрузки
                  
                  // ✅ Применяем матрицы через ProjectNotifier
                  ref.read(currentProjectProvider.notifier)
                      .applyHarmonizationMatrices(matrices);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.white),
                          SizedBox(width: 8),
                          Expanded(child: Text('✅ Все фото успешно гармонизированы!')),
                        ],
                      ),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ошибка при гармонизации: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Улучшить', style: TextStyle(color: Colors.yellowAccent)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 🤖 Умный монтаж
  // ==========================================
  void _openSmartMontage() {
    final photos = ref.read(currentProjectProvider).photos;
    if (photos.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сначала добавьте фото на таймлайн'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    _pauseAudio();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SmartMontageScreen()),
    );
  }

  // ==========================================
  // 📐 Авто-предложение формата при первом фото
  // ==========================================
  void _onFirstPhotoAdded() {
    final photos = ref.read(currentProjectProvider).photos;
    if (photos.isEmpty) return;

    _recommendedFormatFor(photos.first.imagePath).then((recommended) {
      if (!mounted) return;
      if (_mediaLibraryOpen) {
        _pendingFormatId = recommended;
      } else {
        showFormatSheet(context, ref, recommendedId: recommended);
      }
    });
  }

  Future<int> _recommendedFormatFor(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final size = await _decodeImageSize(bytes);
      final rec = VideoFormat.recommendedForImage(
        width: size.width,
        height: size.height,
      );
      print('📐 РЕКОМЕНДАЦИЯ ФОРМАТА: ${VideoFormat.byId(rec).name} '
          'для ${size.width.round()}×${size.height.round()}');
      return rec;
    } catch (e) {
      print('⚠️ Не удалось определить ориентацию фото: $e');
      return 0;
    }
  }

  Future<ui.Size> _decodeImageSize(Uint8List bytes) {
    final completer = Completer<ui.Size>();
    ui.decodeImageFromList(bytes, (image) {
      if (!completer.isCompleted) {
        completer.complete(
          ui.Size(image.width.toDouble(), image.height.toDouble()),
        );
      }
    });
    return completer.future.timeout(const Duration(seconds: 3),
        onTimeout: () => const ui.Size(1, 1));
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Play/Pause превью → звук
    ref.listen<bool>(isPlayingProvider, (prev, playing) {
      if (playing) {
        _startTick();
        _startAudio();
      } else {
        _tick?.cancel();
        _pauseAudio();
      }
    });

    // ✅ Плейхед: скраб → seek плеера; пересечение задержки старта → play
    ref.listen<double>(playheadMsProvider, (prev, ms) {
      final isPlaying = ref.read(isPlayingProvider);
      final track = ref.read(currentProjectProvider).audioTrack;

      if (track != null) {
        if (!isPlaying) {
          final delta = (ms - _lastPlayheadMs).abs();
          if (delta > 100) {
            _seekToPlayhead();
          }
        } else {
          final audioStartMs = track.startTime * 1000;
          if (_lastPlayheadMs < audioStartMs && ms >= audioStartMs) {
            _startAudio();
          }
        }
      }

      _lastPlayheadMs = ms;
    });

    // ✅ Смена трека/громкости
    ref.listen(currentProjectProvider.select((p) => p.audioTrack),
        (prev, next) {
      if (prev?.filePath != next?.filePath) {
        if (!ref.read(isPlayingProvider)) {
          _pauseAudio();
        }
      } else if (prev?.volume != next?.volume) {
        ref.read(audioPlayerProvider).setVolume(next?.volume ?? 0.5);
      }
    });

    // ✅ Первое фото → подсказка формата
    ref.listen(currentProjectProvider, (prev, next) {
      if ((prev?.photos.isEmpty ?? false) && next.photos.isNotEmpty) {
        _onFirstPhotoAdded();
      }
    });

    final project = ref.watch(currentProjectProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _saveAndPop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.chevron_left, size: 28),
            color: AppColors.textPrimary,
            onPressed: _saveAndPop,
          ),
          title: Text(
            project.name,
            style: GoogleFonts.unbounded(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.auto_awesome, size: 22),
              color: AppColors.primary,
              tooltip: 'Умный монтаж',
              onPressed: _openSmartMontage,
            ),
            IconButton(
              icon: Icon(
                project.format.icon,
                size: 22,
                color: AppColors.textPrimary,
              ),
              tooltip:
                  'Формат: ${project.format.name} (${project.format.ratio})',
              onPressed: () => showFormatSheet(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.video_library_outlined, size: 24),
              color: AppColors.textPrimary,
              tooltip: 'Медиатека',
              onPressed: _openMediaLibrary,
            ),
            IconButton(
              icon: const Icon(Icons.save_outlined, size: 24),
              color: AppColors.textPrimary,
              tooltip: 'Сохранить проект',
              onPressed: () => _saveProject(showSnackBar: true),
            ),
            TextButton(
              onPressed: () {
                _pauseAudio();
                ref.read(isPlayingProvider.notifier).state = false;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ExportScreen(project: project),
                  ),
                );
              },
              child: Text(
                'Экспорт',
                style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              const Expanded(child: EditorPreviewArea()),
              Container(height: 1, color: AppColors.surfaceLight),
              SizedBox(
                height: 92,
                child: EditorToolbar(
                  onAddPhoto: _showPhotoSourceSheet,
                  onAddText: () => showTextManagerSheet(context, ref),
                  onAddAudio: () => showAudioManagerSheet(context, ref),
                  onCrop: _openCropEditor,
                  onOpenEffects: _openEffects,
                  onOpenTransitions: _openTransitions,
                  onOpenOverlays: _openOverlays,
                  onOpenLiveMotion: _openLiveMotion,
                  onOpenHarmonize: _openHarmonize, // 🆕 AI Гармонизация
                ),
              ),
              Container(height: 1, color: AppColors.surfaceLight),
              SizedBox(
                height: 170,
                child: EditorTimeline(
                  zoom: timelineZoom,
                  onZoomChanged: (value) =>
                      setState(() => timelineZoom = value),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// Плитка выбора источника (в шторке фото)
// ==========================================
class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
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
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
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
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textMuted, size: 22),
          ],
        ),
      ),
    );
  }
}