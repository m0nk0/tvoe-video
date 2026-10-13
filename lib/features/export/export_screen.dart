import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/colors.dart';
import '../../data/models/video_project.dart';
import '../../data/models/video_format.dart';
import '../../data/services/export_service.dart';
import '../../data/services/media_storage_service.dart';

class ExportScreen extends ConsumerStatefulWidget {
  final VideoProject project;
  const ExportScreen({super.key, required this.project});
  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  double _progress = 0.0;
  bool _isExporting = false;
  String? _outputPath;
  String? _savedClipPath;
  bool _hasAudio = false;
  String? _warningMessage;
  String? _errorMessage;
  VideoFormat _selectedFormat = VideoFormat.formats.first;
  late TextEditingController _fileNameController;

  @override
  void initState() {
    super.initState();
    _fileNameController = TextEditingController(text: widget.project.name);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showFormatSelector();
    });
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  void _showSnack(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: color,
      duration: const Duration(seconds: 4),
    ));
  }

  // ==========================================
  // Выбор формата + имя файла
  // ==========================================
  void _showFormatSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              return Padding(
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
                      'Название видео',
                      style: GoogleFonts.unbounded(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _fileNameController,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Введите название...',
                        hintStyle: GoogleFonts.manrope(
                          color: AppColors.textMuted.withOpacity(0.6),
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceLight,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        suffixText: '.mp4',
                        suffixStyle: GoogleFonts.manrope(
                          color: AppColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Выберите формат видео',
                      style: GoogleFonts.unbounded(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...VideoFormat.formats.map((format) {
                      final isSelected = format == _selectedFormat;
                      return GestureDetector(
                        onTap: () => setSheetState(() {
                          _selectedFormat = format;
                        }),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withOpacity(0.1)
                                : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                format.width < format.height
                                    ? Icons.phone_android
                                    : Icons.tv,
                                color: AppColors.primary,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      format.name,
                                      style: GoogleFonts.manrope(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '${format.ratio} • ${format.width}×${format.height}',
                                      style: GoogleFonts.manrope(
                                        fontSize: 12,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle,
                                    color: AppColors.primary, size: 24),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _startExport();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'Начать экспорт',
                          style: GoogleFonts.manrope(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ==========================================
  // ✅ Санитизация имени файла (убрать запрещённые символы)
  // ==========================================
  String _sanitizeFileName(String name) {
    var clean = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) clean = 'Мой клип';
    if (clean.length > 100) clean = clean.substring(0, 100);
    return clean;
  }

  Future<void> _startExport() async {
    final fileName = _sanitizeFileName(_fileNameController.text);
    
    setState(() {
      _isExporting = true;
      _progress = 0.0;
      _errorMessage = null;
      _warningMessage = null;
      _outputPath = null;
      _savedClipPath = null;
      _hasAudio = false;
    });

    try {
      final result = await ExportService.exportVideo(
        project: widget.project,
        format: _selectedFormat,
        outputFileName: fileName, // 🆕 передаём имя
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _progress = progress;
            });
          }
        },
        cancelChecker: () => !_isExporting,
      );

      if (mounted) {
        setState(() {
          _isExporting = false;
          if (result != null) {
            _outputPath = result.videoPath;
            _hasAudio = result.hasAudio;
            _warningMessage = result.warning;
            _saveClipToProject(result.videoPath, fileName);
          } else {
            _errorMessage = 'Экспорт отменён';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _errorMessage = 'Ошибка экспорта: $e';
        });
      }
    }
  }

  Future<void> _saveClipToProject(String exportedPath, String fileName) async {
    try {
      final storage = ref.read(mediaStorageProvider);
      final savedPath = await storage.saveClip(
        exportedPath,
        title: fileName,
      );
      if (mounted) {
        setState(() {
          _savedClipPath = savedPath;
        });
        _showSnack('Клип сохранён в медиатеку', Colors.green);
      }
    } catch (e) {
      print('Не удалось сохранить клип в папку проекта: $e');
    }
  }

  void _cancelExport() {
    setState(() {
      _isExporting = false;
    });
  }

  Future<void> _saveToGallery() async {
    if (_outputPath == null) return;

    if (!File(_outputPath!).existsSync()) {
      _showSnack('Файл не найден: $_outputPath', Colors.red);
      return;
    }

    try {
      await Gal.putVideo(_outputPath!, album: 'Твоё Видео');
      _showSnack('Видео сохранено в галерею (альбом «Твоё Видео»)',
          Colors.green);
    } catch (e) {
      print('❌ ОШИБКА ГАЛЕРЕИ: $e');
      try {
        await Gal.putVideo(_outputPath!);
        _showSnack('Видео сохранено в галерею', Colors.green);
      } catch (e2) {
        print('❌ ОШИБКА ГАЛЕРЕИ (без альбома): $e2');
        _showSnack('Ошибка галереи: $e2 — попробуйте «Поделиться»', Colors.red);
      }
    }
  }

  void _shareVideo() {
    if (_outputPath == null) return;
    Share.shareXFiles(
      [XFile(_outputPath!)],
      text: 'Смотрите моё видео из "Твоё Видео"!',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Экспорт видео'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isExporting) ...[
                  const Icon(
                    Icons.videocam,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Экспорт: ${_selectedFormat.name} (${_selectedFormat.width}×${_selectedFormat.height})',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '📝 ${_fileNameController.text}.mp4',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  if (widget.project.audioTrack != null) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.music_note,
                              color: AppColors.primary, size: 16),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'с музыкой: ${widget.project.audioTrack!.title}',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: AppColors.surfaceLight,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primary),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${(_progress * 100).toInt()}%',
                    style: GoogleFonts.manrope(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton(
                    onPressed: _cancelExport,
                    child: const Text('Отменить'),
                  ),
                ] else if (_errorMessage != null) ...[
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isExporting = true;
                        _progress = 0.0;
                        _errorMessage = null;
                        _warningMessage = null;
                        _outputPath = null;
                        _savedClipPath = null;
                        _hasAudio = false;
                      });
                      _startExport();
                    },
                    child: const Text('Попробовать снова'),
                  ),
                ] else ...[
                  const Icon(
                    Icons.check_circle,
                    size: 64,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Видео готово!',
                    style: GoogleFonts.unbounded(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '📝 ${_fileNameController.text}.mp4',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: AppColors.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildExportResultInfo(),
                  if (_warningMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber,
                              color: Colors.orange, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _warningMessage!,
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_savedClipPath != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.library_books,
                              color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Сохранено в медиатеку',
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _saveToGallery,
                    icon: const Icon(Icons.save),
                    label: const Text('Сохранить в галерею'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _shareVideo,
                    icon: const Icon(Icons.share),
                    label: const Text('Поделиться'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Назад в редактор'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExportResultInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                '${_selectedFormat.name} • ${_selectedFormat.width}×${_selectedFormat.height}',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _hasAudio ? Icons.music_note : Icons.music_off,
                color: _hasAudio ? AppColors.primary : AppColors.textMuted,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _hasAudio
                      ? 'Музыка: ${widget.project.audioTrack?.title ?? 'добавлена'}'
                      : 'Без музыки',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: _hasAudio
                        ? AppColors.textPrimary
                        : AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}