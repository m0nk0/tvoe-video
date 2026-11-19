import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/colors.dart';
import '../../data/models/video_format.dart';
import '../../data/models/video_project.dart';
import '../../data/services/export_service.dart';

class ExportScreen extends StatefulWidget {
  final VideoProject project;

  const ExportScreen({super.key, required this.project});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  double _progress = 0.0;
  bool _isExporting = false;
  String? _outputPath;
  String? _savedClipPath;
  String? _errorMessage;
  String? _warningMessage;
  bool _hasAudio = false;
  bool _gifActive = false;
  VideoFormat _selectedFormat = VideoFormat.formats[0];
  final TextEditingController _fileNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedFormat = widget.project.format;
    _fileNameController.text = _sanitizeFileName(widget.project.name);
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  String _sanitizeFileName(String name) {
    var clean = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) clean = 'Мой клип';
    if (clean.length > 100) clean = clean.substring(0, 100);
    clean = clean.replaceAll(RegExp(r'\.+$'), '');
    return clean.isEmpty ? 'Мой клип' : clean;
  }

  Future<void> _startExport() async {
    final fileName = _sanitizeFileName(_fileNameController.text);
    setState(() {
      _gifActive = false;
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
        outputFileName: fileName,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        cancelChecker: () => !_isExporting,
      );

      if (!mounted) return;

      final ok = result != null &&
          File(result.videoPath).existsSync() &&
          File(result.videoPath).lengthSync() > 1024;

      setState(() {
        _isExporting = false;
        if (ok) {
          _outputPath = result.videoPath;
          _hasAudio = result.hasAudio;
          _warningMessage = result.warning;
        } else {
          _outputPath = null;
          _errorMessage = ExportService.lastError ?? 'Видео не создано';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _outputPath = null;
          _errorMessage = 'Ошибка экспорта: $e';
        });
      }
    }
  }

  // ==========================================
  // ✅ GIF-экспорт: весь клип сжимается в ≤10 с (ускорение), все кадры входят
  // ==========================================
  Future<void> _startGifExport() async {
    final fileName = _sanitizeFileName(_fileNameController.text);
    setState(() {
      _gifActive = true;
      _isExporting = true;
      _progress = 0.0;
      _errorMessage = null;
      _warningMessage = null;
      _outputPath = null;
      _savedClipPath = null;
      _hasAudio = false;
    });
    try {
      final path = await ExportService.exportGif(
        project: widget.project,
        format: _selectedFormat,
        outputFileName: fileName,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        cancelChecker: () => !_isExporting,
      );

      if (!mounted) return;

      final ok = path != null &&
          File(path).existsSync() &&
          File(path).lengthSync() > 100;

      setState(() {
        _isExporting = false;
        if (ok) {
          _outputPath = path;
          _hasAudio = false;
          final secs = widget.project.totalDurationMs / 1000;
          final speed = secs > 10 ? secs / 10 : 1.0;
          _warningMessage = 'GIF: без звука, 480 px, 10 fps'
              '${speed > 1 ? ', ускорено ×${speed.toStringAsFixed(1)}' : ''}'
              ', ≤10 с';
        } else {
          _outputPath = null;
          _errorMessage = ExportService.lastError ?? 'GIF не создан';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _outputPath = null;
          _errorMessage = 'Ошибка GIF: $e';
        });
      }
    }
  }

  Future<void> _saveToGallery() async {
    if (_outputPath == null) return;
    setState(() => _isExporting = true);
    try {
      if (_outputPath!.endsWith('.gif')) {
        await Gal.putImage(_outputPath!, album: 'Твоё Видео');
      } else {
        await Gal.putVideo(_outputPath!, album: 'Твоё Видео');
      }
      setState(() {
        _savedClipPath = _outputPath;
        _isExporting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ Сохранено в галерею (альбом «Твоё Видео»)'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _isExporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveToMediaLibrary() async {
    if (_outputPath == null) return;
    setState(() => _isExporting = true);
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final clipsDir = Directory('${appDir.path}/clips');
      if (!clipsDir.existsSync()) clipsDir.createSync(recursive: true);
      final ext = _outputPath!.endsWith('.gif') ? 'gif' : 'mp4';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final dst = '${clipsDir.path}/clip_$ts.$ext';
      File(_outputPath!).copySync(dst);
      setState(() {
        _savedClipPath = dst;
        _isExporting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('💾 Сохранено в медиатеку (вкладка «Клипы»)'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _isExporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _shareVideo() async {
    if (_outputPath == null) return;
    try {
      await Share.shareXFiles([
        XFile(
          _outputPath!,
          mimeType: _outputPath!.endsWith('.gif') ? 'image/gif' : 'video/mp4',
        ),
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка шаринга: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showFormatSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
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
                      'Выберите формат видео',
                      style: GoogleFonts.unbounded(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ...VideoFormat.formats.map(
                      (format) => GestureDetector(
                        onTap: () {
                          setSheetState(() => _selectedFormat = format);
                          Navigator.pop(sheetContext);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _selectedFormat.id == format.id
                                ? AppColors.primary.withOpacity(0.15)
                                : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _selectedFormat.id == format.id
                                  ? AppColors.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(format.icon,
                                  color: _selectedFormat.id == format.id
                                      ? AppColors.primary
                                      : AppColors.textMuted,
                                  size: 28),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      format.name,
                                      style: GoogleFonts.manrope(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${format.width}×${format.height}',
                                      style: GoogleFonts.manrope(
                                        fontSize: 12,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_selectedFormat.id == format.id)
                                const Icon(Icons.check_circle,
                                    color: AppColors.primary, size: 22),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          'Экспорт видео',
          style: GoogleFonts.unbounded(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      // ✅ Три взаимоисключающих состояния: экспорт / результат / форма
      body: SafeArea(
        child: _isExporting
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: Center(child: _buildExportingIndicator()),
              )
            : _outputPath != null
                ? _buildSuccessState()
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: SingleChildScrollView(child: _buildIdleState()),
                  ),
      ),
    );
  }

  Widget _buildIdleState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Icon(Icons.movie_outlined, size: 72, color: AppColors.primary),
        const SizedBox(height: 20),
        Text(
          'Готовы создать видео?',
          style: GoogleFonts.unbounded(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Кадров: ${widget.project.photos.length}\n'
          'Длительность: ${(widget.project.totalDurationMs / 1000).toStringAsFixed(1)} сек\n'
          'Формат: ${_selectedFormat.name}',
          style: GoogleFonts.manrope(fontSize: 14, color: AppColors.textSecondary, height: 1.6),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _fileNameController,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Название файла',
            hintStyle: TextStyle(color: AppColors.textMuted.withOpacity(0.6)),
            prefixIcon: const Icon(Icons.edit_outlined, color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.surfaceLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _showFormatSelector,
            icon: Icon(_selectedFormat.icon, size: 20),
            label: Text('${_selectedFormat.name} • ${_selectedFormat.width}×${_selectedFormat.height}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
            ),
          ),
        ),
        const SizedBox(height: 20),
        // ✅ Во всю ширину, шрифт 15 — текст не вылезает
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _startExport,
            icon: const Icon(Icons.download, size: 22),
            label: Text(
              'Выбрать формат и начать',
              style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _startGifExport,
            icon: const Icon(Icons.gif_box_outlined, size: 22),
            label: Text(
              'Экспорт в GIF (без звука)',
              style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'GIF: 480 px, 10 fps, до 10 секунд, без звука — для Telegram, стикеров и превью.',
          style: GoogleFonts.manrope(fontSize: 11, color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.error.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.manrope(fontSize: 12, color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ✅ Отдельный экран результата: ничего не накладывается
  Widget _buildSuccessState() {
    final isGif = _outputPath!.endsWith('.gif');
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Icon(
            isGif ? Icons.gif_box_outlined : Icons.check_circle,
            size: 80,
            color: AppColors.primary,
          ),
          const SizedBox(height: 16),
          Text(
            isGif ? 'GIF готов!' : 'Видео готово!',
            style: GoogleFonts.unbounded(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '${(File(_outputPath!).lengthSync() / 1024 / 1024).toStringAsFixed(1)} МБ',
            style: GoogleFonts.jetBrainsMono(fontSize: 16, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (_hasAudio) ...[
            const SizedBox(height: 6),
            Text(
              '🎵 Музыка: ${widget.project.audioTrack?.title ?? ''}',
              style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
          if (_warningMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              '⚠️ ${_warningMessage!}',
              style: GoogleFonts.manrope(fontSize: 11, color: Colors.orange),
              textAlign: TextAlign.center,
            ),
          ],
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _saveToGallery,
            icon: const Icon(Icons.photo_library_outlined, size: 20),
            label: const Text('В галерею'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _saveToMediaLibrary,
            icon: const Icon(Icons.video_library_outlined, size: 20),
            label: const Text('В медиатеку'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surfaceLight,
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _shareVideo,
            icon: const Icon(Icons.share, size: 20),
            label: const Text('Поделиться'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {
              _outputPath = null;
              _progress = 0.0;
              _warningMessage = null;
              _errorMessage = null;
            }),
            child: Text(
              'Создать ещё',
              style: GoogleFonts.manrope(fontSize: 14, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportingIndicator() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.videocam, size: 80, color: AppColors.primary),
        const SizedBox(height: 32),
        Text(
          _gifActive
              ? 'Экспорт: GIF (480 px, 10 fps, без звука)'
              : 'Экспорт: ${_selectedFormat.name} (${_selectedFormat.width}×${_selectedFormat.height})',
          style: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '📝 ${_sanitizeFileName(_fileNameController.text)}.${_gifActive ? 'gif' : 'mp4'}',
          style: GoogleFonts.manrope(fontSize: 13, color: AppColors.textMuted),
        ),
        if (!_gifActive && widget.project.audioTrack != null) ...[
          const SizedBox(height: 4),
          Text(
            '🎵 с музыкой: ${widget.project.audioTrack!.title}',
            style: GoogleFonts.manrope(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
        const SizedBox(height: 24),
        LinearProgressIndicator(
          value: _progress,
          backgroundColor: AppColors.surfaceLight,
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          minHeight: 8,
        ),
        const SizedBox(height: 12),
        Text(
          '${(_progress * 100).toStringAsFixed(0)}%',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () {
            setState(() => _isExporting = false);
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: BorderSide(color: AppColors.primary),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          ),
          child: const Text('Отменить'),
        ),
      ],
    );
  }
}