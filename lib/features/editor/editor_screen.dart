import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/project_harmonizer.dart';
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
import 'widgets/radial_tool_menu.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> with WidgetsBindingObserver {
  double timelineZoom = 1.0;
  Timer? _tick;
  bool _mediaLibraryOpen = false;
  int? _pendingFormatId;
  double _lastPlayheadMs = 0;

  static const double _timelineHeight = 170;
  static const double _dividerHeight = 1;
  static const double _menuZoneHeight = 120;
  static const double _menuSize = 300;
  static const double _menuLift = 4;

  static const double _menuBottom =
      _timelineHeight + _dividerHeight + _menuZoneHeight / 2 - _menuSize / 2 + _menuLift;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      print('🔄 АВТОСОХРАНЕНИЕ при сворачивании/закрытии приложения');
      _saveProject(showSnackBar: false);
    }
  }

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final photos = ref.read(currentProjectProvider).photos;
      final total = photos.fold<int>(0, (s, p) => s + p.durationMilliseconds).toDouble();
      if (total <= 0) return;
      double ms = ref.read(playheadMsProvider) + 33;
      if (ms >= total) {
        ms = total;
        ref.read(isPlayingProvider.notifier).state = false;
      }
      ref.read(playheadMsProvider.notifier).state = ms;
    });
  }

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
        print('⚠️ Не удалось загрузить трек: $e');
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
      await player.seek(Duration(milliseconds: (playheadMs - audioStartMs).round()));
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

  Future<void> _saveProject({bool showSnackBar = false}) async {
    final project = ref.read(currentProjectProvider);
    final hasContent = project.photos.isNotEmpty || project.texts.isNotEmpty || project.audioTrack != null;

    if (!hasContent) return;

    try {
      await ref.read(projectRepositoryProvider).saveProject(project);
      ref.read(projectsProvider.notifier).refresh();

      if (showSnackBar && mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Проект сохранён'), backgroundColor: Colors.green, duration: Duration(seconds: 1)),
        );
      }
    } catch (e, st) {
      print('❌ ОШИБКА СОХРАНЕНИЯ: $e\n$st');
      if (showSnackBar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 2)),
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

  // ✅ НОВОЕ: Диалог подтверждения выхода
  void _confirmBack() {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Выйти из проекта?',
          style: GoogleFonts.unbounded(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        content: Text(
          'Проект будет автоматически сохранён',
          style: GoogleFonts.manrope(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Отмена', style: GoogleFonts.manrope(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _saveAndPop();
            },
            child: Text('Выйти', style: GoogleFonts.manrope(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ✅ НОВОЕ: Диалог переименования проекта
  void _showRenameDialog() {
    final currentName = ref.read(currentProjectProvider).name;
    final controller = TextEditingController(text: currentName);
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Переименовать проект',
          style: GoogleFonts.unbounded(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Введите название',
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
                ref.read(currentProjectProvider.notifier).setName(newName);
                ref.read(projectRepositoryProvider).saveProject(ref.read(currentProjectProvider));
                ref.read(projectsProvider.notifier).refresh();
              }
              Navigator.pop(dialogContext);
            },
            child: Text('Сохранить', style: GoogleFonts.manrope(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  String _cleanProjectName(String name) {
    return name.replaceAll(RegExp(r'[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]', unicode: true), '').trim();
  }

  void _showPhotoSourceSheet() {
    HapticFeedback.lightImpact();
    _pauseAudio();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(2)))),
                Text('Добавить фото', style: GoogleFonts.unbounded(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 20),
                _SourceTile(
                  icon: Icons.photo_library,
                  title: 'Галерея',
                  subtitle: 'Выбрать из галереи устройства',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    ref.read(currentProjectProvider.notifier).addPhotosFromGallery();
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

  void _openMediaLibraryForPhotos() {
    HapticFeedback.lightImpact();
    _pauseAudio();
    _mediaLibraryOpen = true;
    final currentPaths = ref.read(currentProjectProvider).photos.map((p) => p.imagePath).toSet();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaLibraryScreen(
          initialSelectedPaths: currentPaths,
          isEditingProject: true,
          singleSelectMode: false,
          onUsePhotos: (paths) {
            final notifier = ref.read(currentProjectProvider.notifier);
            for (final path in paths) notifier.addPhotoByPath(path);
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

  void _openMediaLibrary() {
    HapticFeedback.lightImpact();
    _pauseAudio();
    _mediaLibraryOpen = true;
    final currentPaths = ref.read(currentProjectProvider).photos.map((p) => p.imagePath).toSet();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaLibraryScreen(
          initialSelectedPaths: currentPaths,
          isEditingProject: true,
          singleSelectMode: false,
          onUseMusic: (track) {
            ref.read(currentProjectProvider.notifier).setAudioTrack(track);
          },
          onUsePhotos: (paths) {
            final notifier = ref.read(currentProjectProvider.notifier);
            for (final path in paths) notifier.addPhotoByPath(path);
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

  void _openCropEditor() {
    HapticFeedback.lightImpact();
    final selectedIndex = ref.read(selectedPhotoIndexProvider);
    final photos = ref.read(currentProjectProvider).photos;
    if (photos.isNotEmpty && selectedIndex < photos.length) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => CropEditorScreen(photoIndex: selectedIndex)));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сначала добавьте фото на таймлайн'), backgroundColor: Colors.orange, duration: Duration(seconds: 2)));
    }
  }

  void _openEffects() {
    HapticFeedback.lightImpact();
    final selectedIndex = ref.read(selectedPhotoIndexProvider);
    final photos = ref.read(currentProjectProvider).photos;
    if (photos.isNotEmpty && selectedIndex < photos.length) {
      showEffectsSheet(context, ref, SelectionController(ref).targetIndices(selectedIndex));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сначала добавьте фото на таймлайн'), backgroundColor: Colors.orange, duration: Duration(seconds: 2)));
    }
  }

  void _openTransitions() {
    HapticFeedback.lightImpact();
    final selectedIndex = ref.read(selectedPhotoIndexProvider);
    final photos = ref.read(currentProjectProvider).photos;
    if (photos.isNotEmpty && selectedIndex < photos.length) {
      showTransitionsSheet(context, ref, SelectionController(ref).targetIndices(selectedIndex));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сначала добавьте фото на таймлайн'), backgroundColor: Colors.orange, duration: Duration(seconds: 2)));
    }
  }

  void _openOverlays() {
    HapticFeedback.lightImpact();
    showOverlaysSheet(context, ref);
  }

  void _openLiveMotion() {
    HapticFeedback.lightImpact();
    showLiveMotionSheet(context, ref);
  }

  void _openHarmonize() {
    HapticFeedback.lightImpact();
    final photos = ref.read(currentProjectProvider).photos;
    if (photos.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сначала добавьте фото на таймлайн'), backgroundColor: Colors.orange, duration: Duration(seconds: 2)));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Row(children: [Icon(Icons.auto_awesome, color: Colors.yellowAccent), SizedBox(width: 8), Text('✨ AI Улучшение')]),
        content: Text('Приложение автоматически выровняет цвета, яркость и контраст всех кадров под лучший.', style: GoogleFonts.manrope(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
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
                        child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Анализируем...')]),
                      ),
                    ),
                  ),
                );
              }
              try {
                final matrices = await ProjectHarmonizer.harmonizeProject(photos, (progress) {});
                if (mounted) {
                  Navigator.pop(context);
                  ref.read(currentProjectProvider.notifier).applyHarmonizationMatrices(matrices);
                  HapticFeedback.heavyImpact();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Фото гармонизированы!'), backgroundColor: Colors.green));
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Улучшить', style: TextStyle(color: Colors.yellowAccent)),
          ),
        ],
      ),
    );
  }

  void _openSmartMontage() {
    HapticFeedback.lightImpact();
    final photos = ref.read(currentProjectProvider).photos;
    if (photos.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сначала добавьте фото на таймлайн'), backgroundColor: Colors.orange, duration: Duration(seconds: 2)));
      return;
    }
    _pauseAudio();
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SmartMontageScreen()));
  }

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
      final rec = VideoFormat.recommendedForImage(width: size.width, height: size.height);
      return rec;
    } catch (e) {
      return 0;
    }
  }

  Future<ui.Size> _decodeImageSize(Uint8List bytes) {
    final completer = Completer<ui.Size>();
    ui.decodeImageFromList(bytes, (image) {
      if (!completer.isCompleted) completer.complete(ui.Size(image.width.toDouble(), image.height.toDouble()));
    });
    return completer.future.timeout(const Duration(seconds: 3), onTimeout: () => const ui.Size(1, 1));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isPlayingProvider, (prev, playing) {
      if (playing) {
        _startTick();
        _startAudio();
      } else {
        _tick?.cancel();
        _pauseAudio();
      }
    });

    ref.listen<double>(playheadMsProvider, (prev, ms) {
      final isPlaying = ref.read(isPlayingProvider);
      final track = ref.read(currentProjectProvider).audioTrack;
      if (track != null) {
        if (!isPlaying) {
          if ((ms - _lastPlayheadMs).abs() > 100) _seekToPlayhead();
        } else {
          if (_lastPlayheadMs < track.startTime * 1000 && ms >= track.startTime * 1000) _startAudio();
        }
      }
      _lastPlayheadMs = ms;
    });

    ref.listen(currentProjectProvider.select((p) => p.audioTrack), (prev, next) {
      if (prev?.filePath != next?.filePath) {
        if (!ref.read(isPlayingProvider)) _pauseAudio();
      } else if (prev?.volume != next?.volume) {
        ref.read(audioPlayerProvider).setVolume(next?.volume ?? 0.5);
      }
    });

    ref.listen(currentProjectProvider, (prev, next) {
      if ((prev?.photos.isEmpty ?? false) && next.photos.isNotEmpty) {
        _onFirstPhotoAdded();
      }
    });

    final project = ref.watch(currentProjectProvider);
    final notifier = ref.read(currentProjectProvider.notifier);
    final canUndo = notifier.canUndo;
    final canRedo = notifier.canRedo;
    final cleanName = _cleanProjectName(project.name);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _saveAndPop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
  backgroundColor: AppColors.background,
  elevation: 0,
  // ✅ УВЕЛИЧЕНА ширина для трёх кнопок
  leadingWidth: 160,
  leading: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        icon: const Icon(Icons.arrow_back, size: 20),
        color: AppColors.textPrimary,
        tooltip: 'Назад',
        onPressed: _confirmBack,
      ),
      IconButton(
        icon: const Icon(Icons.undo, size: 18),
        color: canUndo ? AppColors.textPrimary : AppColors.textMuted.withValues(alpha: 0.3),
        tooltip: 'Отменить',
        onPressed: canUndo
            ? () {
                HapticFeedback.lightImpact();
                ref.read(currentProjectProvider.notifier).undo();
              }
            : null,
      ),
      IconButton(
        icon: const Icon(Icons.redo, size: 18),
        color: canRedo ? AppColors.textPrimary : AppColors.textMuted.withValues(alpha: 0.3),
        tooltip: 'Вернуть',
        onPressed: canRedo
            ? () {
                HapticFeedback.lightImpact();
                ref.read(currentProjectProvider.notifier).redo();
              }
            : null,
      ),
    ],
  ),
  actions: [
    PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 24),
      color: AppColors.surface,
      onSelected: (value) {
        HapticFeedback.lightImpact();
        switch (value) {
          case 'smart':
            _openSmartMontage();
            break;
          case 'format':
            showFormatSheet(context, ref);
            break;
          case 'media':
            _openMediaLibrary();
            break;
          case 'export':
            _pauseAudio();
            ref.read(isPlayingProvider.notifier).state = false;
            Navigator.push(context, MaterialPageRoute(builder: (context) => ExportScreen(project: project)));
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'smart',
          child: Row(
            children: [
              Icon(Icons.auto_awesome, color: AppColors.aiAccent, size: 20),
              const SizedBox(width: 12),
              Text('Умный монтаж', style: GoogleFonts.manrope(fontSize: 14, color: AppColors.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'format',
          child: Row(
            children: [
              Icon(project.format.icon, color: AppColors.textPrimary, size: 20),
              const SizedBox(width: 12),
              Text('Формат: ${project.format.name}', style: GoogleFonts.manrope(fontSize: 14, color: AppColors.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'media',
          child: Row(
            children: [
              const Icon(Icons.video_library_outlined, color: AppColors.textPrimary, size: 20),
              const SizedBox(width: 12),
              Text('Медиатека', style: GoogleFonts.manrope(fontSize: 14, color: AppColors.textPrimary)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              const Icon(Icons.download, color: AppColors.primary, size: 20),
              const SizedBox(width: 12),
              Text('Экспорт', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
            ],
          ),
        ),
      ],
    ),
  ],
),
        body: Stack(
          children: [
            Column(
              children: [
                // Название проекта над превью
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: GestureDetector(
                    onTap: _showRenameDialog,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            cleanName.isEmpty ? 'Новый проект' : cleanName,
                            style: GoogleFonts.unbounded(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.edit_outlined, size: 18, color: AppColors.textMuted),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: const EditorPreviewArea(),
                  ),
                ),
                const SizedBox(height: _menuZoneHeight),
                Container(height: _dividerHeight, color: AppColors.divider),
                SizedBox(
                  height: _timelineHeight,
                  child: EditorTimeline(
                    zoom: timelineZoom,
                    onZoomChanged: (value) => setState(() => timelineZoom = value),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: _menuBottom,
              child: Center(
                child: RadialToolMenu(
                  radius: 120.0,
                  items: [
                    RadialMenuItem(icon: Icons.image_outlined, label: 'Фото', color: AppColors.textPrimary, bgColor: AppColors.surfaceLight, onTap: _showPhotoSourceSheet),
                    RadialMenuItem(icon: Icons.crop, label: 'Обрезать', color: AppColors.textPrimary, bgColor: AppColors.surfaceLight, onTap: _openCropEditor),
                    RadialMenuItem(icon: Icons.music_note, label: 'Музыка', color: AppColors.textPrimary, bgColor: AppColors.surfaceLight, onTap: _openMediaLibrary),
                    RadialMenuItem(icon: Icons.auto_fix_high, label: 'Эффекты', color: AppColors.textPrimary, bgColor: AppColors.surfaceLight, onTap: _openEffects),
                    RadialMenuItem(icon: Icons.text_fields, label: 'Текст', color: AppColors.textPrimary, bgColor: AppColors.surfaceLight, onTap: () => showTextManagerSheet(context, ref)),
                    RadialMenuItem(icon: Icons.change_circle_outlined, label: 'Переходы', color: AppColors.textPrimary, bgColor: AppColors.surfaceLight, onTap: _openTransitions),
                    RadialMenuItem(icon: Icons.layers_outlined, label: 'Оверлеи', color: AppColors.textPrimary, bgColor: AppColors.surfaceLight, onTap: _openOverlays),
                    RadialMenuItem(icon: Icons.motion_photos_on_outlined, label: 'Движение', color: AppColors.textPrimary, bgColor: AppColors.surfaceLight, onTap: _openLiveMotion),
                    RadialMenuItem(icon: Icons.auto_awesome, label: 'AI Цвет', color: AppColors.aiAccent, bgColor: AppColors.background, isAi: true, onTap: _openHarmonize),
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

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

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
                  Text(title, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textMuted)),
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