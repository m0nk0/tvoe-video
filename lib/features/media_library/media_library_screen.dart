import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/theme/colors.dart';
import '../../data/models/audio_track.dart';
import '../../data/services/media_storage_service.dart';
import '../editor/audio_tools.dart' show showDeviceMusicBrowser;
import 'widgets/clips_tab.dart';
import 'widgets/import_tile.dart';
import 'widgets/music_tab.dart';
import 'widgets/photos_tab.dart';

// ==========================================
// Медиатека: клипы / музыка / фото
// Точки импорта: 📷 и 🎵 в шапке
// ==========================================
class MediaLibraryScreen extends ConsumerStatefulWidget {
  final void Function(AudioTrack track)? onUseMusic;
  final void Function(List<String> photoPaths)? onUsePhotos;
  final bool singleSelectMode;

  const MediaLibraryScreen({
    super.key,
    this.onUseMusic,
    this.onUsePhotos,
    this.singleSelectMode = false,
  });

  @override
  ConsumerState<MediaLibraryScreen> createState() => _MediaLibraryScreenState();
}

class _MediaLibraryScreenState extends ConsumerState<MediaLibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AudioPlayer? _previewPlayer;
  String? _playingMusicPath;
  bool _isImporting = false;
  Set<String> _selectedPhotoPaths = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _previewPlayer?.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _togglePhotoSelection(String path) {
    setState(() {
      if (_selectedPhotoPaths.contains(path)) {
        _selectedPhotoPaths.remove(path);
      } else {
        _selectedPhotoPaths.add(path);
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedPhotoPaths.clear());
  }

    void _createProjectFromSelected() {
    print('📚 MEDIA_LIBRARY: Создаю проект из ${_selectedPhotoPaths.length} выбранных фото');
    
    if (_selectedPhotoPaths.isEmpty || widget.onUsePhotos == null) {
      print('⚠️ MEDIA_LIBRARY: Прервано (нет выбранных фото или колбэка)');
      return;
    }
    
    final paths = _selectedPhotoPaths.toList();
    
    // 1. Сначала передаем данные наверх (в HomeScreen)
    widget.onUsePhotos!(paths);
    
    // 2. Затем закрываем медиатеку
    Navigator.pop(context);
  }

  // ==========================================
  // 📥 Импорт фото из галереи
  // ==========================================
  Future<void> _importPhotos() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(
      imageQuality: 90,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (images.isEmpty) return;

    setState(() => _isImporting = true);
    final storage = ref.read(mediaStorageProvider);
    int importedCount = 0;

    for (final img in images) {
      try {
        await storage.importPhoto(img.path);
        importedCount++;
        try {
          final cacheFile = File(img.path);
          if (cacheFile.existsSync()) cacheFile.deleteSync();
        } catch (_) {}
      } catch (e) {
        print('❌ Ошибка импорта фото: $e');
      }
    }

    setState(() => _isImporting = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📷 Импортировано фото: $importedCount'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ==========================================
  // 📷 Шторка выбора источника фото
  // ==========================================
  void _showPhotoImportSheet() {
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
                ImportTile(
                  icon: Icons.photo_library,
                  title: 'Галерея',
                  subtitle: 'Выбрать из галереи устройства',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _importPhotos();
                  },
                ),
                const SizedBox(height: 12),
                ImportTile(
                  icon: Icons.folder_outlined,
                  title: 'Загрузки',
                  subtitle: 'Папки Download, DCIM, Pictures',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _showDownloadsPhotoBrowser();
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
  // 📂 Браузер папок для фото
  // ==========================================
  Future<void> _showDownloadsPhotoBrowser() async {
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
              Text('Поиск фото…',
                  style: GoogleFonts.manrope(color: AppColors.textPrimary)),
            ],
          ),
        ),
      ),
    );

    final photos = await _scanPhotosOnDevice();
    if (!mounted) return;
    Navigator.pop(context);

    if (photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Фото не найдены в Download / DCIM / Pictures'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selected = <File>{};
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
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
                          'Фото на устройстве',
                          style: GoogleFonts.unbounded(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Найдено: ${photos.length} • Выбрано: ${selected.length}',
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
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                      ),
                      itemCount: photos.length,
                      itemBuilder: (context, index) {
                        final file = photos[index];
                        final isSelected = selected.contains(file);
                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              if (isSelected) {
                                selected.remove(file);
                              } else {
                                selected.add(file);
                              }
                            });
                          },
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  file,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: AppColors.surfaceLight,
                                    child: const Icon(Icons.broken_image),
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          AppColors.primary.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: AppColors.primary, width: 2),
                                    ),
                                    child: const Icon(Icons.check,
                                        color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border(
                        top: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetCtx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textMuted,
                              side: BorderSide(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.3)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text('Отмена',
                                style: GoogleFonts.manrope(
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: selected.isEmpty
                                ? null
                                : () async {
                                    Navigator.pop(sheetCtx);
                                    await _importSelectedPhotos(
                                        selected.toList());
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.download, size: 18),
                            label: Text(
                              'Импортировать (${selected.length})',
                              style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Сканирование фото на устройстве (Download, DCIM, Pictures)
  Future<List<File>> _scanPhotosOnDevice() async {
    const photoExts = {'jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic'};
    final result = <File>[];

    final dirs = [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/DCIM/Camera',
      '/storage/emulated/0/Pictures',
    ];

    for (final path in dirs) {
      final dir = Directory(path);
      if (!await dir.exists()) continue;
      try {
        final files = await dir
            .list(recursive: false)
            .where((e) => e is File)
            .cast<File>()
            .toList();
        for (final f in files) {
          final ext = f.path.split('.').last.toLowerCase();
          if (photoExts.contains(ext)) result.add(f);
        }
      } catch (e) {
        print('⚠️ Не удалось прочитать $path: $e');
      }
    }

    result.sort((a, b) =>
        b.statSync().modified.compareTo(a.statSync().modified));
    return result;
  }

  /// Импорт выбранных фото из браузера
  Future<void> _importSelectedPhotos(List<File> files) async {
    setState(() => _isImporting = true);
    final storage = ref.read(mediaStorageProvider);
    int count = 0;
    for (final f in files) {
      try {
        await storage.importPhoto(f.path);
        count++;
      } catch (e) {
        print('❌ Ошибка импорта фото: $e');
      }
    }
    setState(() => _isImporting = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📷 Импортировано фото: $count'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ==========================================
  // 🎵 Превью музыки (для вкладки)
  // ==========================================
  Future<void> _playMusic(String path) async {
    if (_playingMusicPath == path &&
        _previewPlayer != null &&
        _previewPlayer!.playing) {
      await _previewPlayer!.pause();
      setState(() => _playingMusicPath = null);
      return;
    }

    _previewPlayer?.dispose();
    _previewPlayer = AudioPlayer();
    try {
      await _previewPlayer!.setFilePath(path);
      await _previewPlayer!.play();
      setState(() => _playingMusicPath = path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка воспроизведения: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _stopMusic() {
    _previewPlayer?.stop();
    setState(() => _playingMusicPath = null);
  }

  // ==========================================
  // 🗑 Удаление
  // ==========================================
  Future<void> _deleteFile(File file, String type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Удалить?',
          style: GoogleFonts.unbounded(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Файл «${MediaStorageService.displayName(file)}» будет удалён навсегда.',
          style: GoogleFonts.manrope(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена',
                style: GoogleFonts.manrope(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Удалить',
                style: GoogleFonts.manrope(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await file.delete();
        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$type удалён'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка удаления: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = ref.watch(mediaStorageProvider);
    final hasSelection = _selectedPhotoPaths.isNotEmpty;
    final canCreateProject =
        !widget.singleSelectMode && widget.onUsePhotos != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          'Медиатека',
          style: GoogleFonts.unbounded(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          // ✅ КНОПКА 📷 ФОТО
          IconButton(
            icon: const Icon(Icons.photo_library_outlined, size: 24),
            tooltip: 'Добавить фото',
            onPressed: _showPhotoImportSheet,
          ),
          // ✅ КНОПКА 🎵 МУЗЫКА
          IconButton(
            icon: const Icon(Icons.library_music_outlined, size: 24),
            tooltip: 'Добавить музыку',
            onPressed: () {
              final importOnly = widget.onUseMusic == null;
              showDeviceMusicBrowser(context, ref, importOnly: importOnly);
            },
          ),
          if (hasSelection && !widget.singleSelectMode)
            TextButton(
              onPressed: _clearSelection,
              child: Text(
                'Сбросить',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          tabs: [
            Tab(
              icon: const Icon(Icons.movie_outlined, size: 22),
              text: 'Клипы (${storage.listClips().length})',
            ),
            Tab(
              icon: const Icon(Icons.music_note_outlined, size: 22),
              text: 'Музыка (${storage.listMusic().length})',
            ),
            Tab(
              icon: const Icon(Icons.photo_outlined, size: 22),
              text: 'Фото (${storage.listPhotos().length})',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ClipsTab(
                  files: storage.listClips(),
                  onDelete: (f) => _deleteFile(f, 'Клип'),
                  onRefresh: _refresh,
                ),
                MusicTab(
                  files: storage.listMusic(),
                  onDelete: (f) => _deleteFile(f, 'Трек'),
                  onPlay: _playMusic,
                  onStop: _stopMusic,
                  playingPath: _playingMusicPath,
                  player: _previewPlayer,
                  onUse: widget.onUseMusic == null
                      ? null
                      : (f) {
                          final track = AudioTrack(
                            filePath: f.path,
                            title: MediaStorageService.displayName(f),
                            isFromInternet: false,
                          );
                          widget.onUseMusic!(track);
                          Navigator.pop(context);
                        },
                ),
                PhotosTab(
                  files: storage.listPhotos(),
                  onDelete: (f) => _deleteFile(f, 'Фото'),
                  selectedPaths: _selectedPhotoPaths,
                  onToggleSelection: _togglePhotoSelection,
                  selectionMode: canCreateProject,
                  singleSelectMode: widget.singleSelectMode,
                  onUsePhoto: widget.onUsePhotos,
                ),
              ],
            ),
          ),
          // Нижняя панель "Создать проект" — только в режиме множественного выбора
          if (hasSelection && canCreateProject)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _showPhotoImportSheet,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceLight,
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.add, size: 20),
                        label: Text(
                          'Добавить',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _createProjectFromSelected,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.add, size: 20),
                        label: Text(
                          'Создать проект',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (!hasSelection && canCreateProject)
            // ✅ ПОДСКАЗКА вместо дублирующей кнопки "Добавить фото"
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.3)),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.touch_app_outlined,
                        size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Отмечай фото тапом или ➕, затем «Создать проект». '
                        'Новые файлы — кнопки в шапке',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}