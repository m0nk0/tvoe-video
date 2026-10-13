import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/theme/colors.dart';
import '../../core/utils/beat_detector.dart';
import '../../core/utils/smart_analyzer.dart';
import '../../core/utils/smart_montage.dart';
import '../../data/models/audio_track.dart';
import '../../data/models/photo_layer.dart';
import '../../data/providers/project_provider.dart';
import '../../data/services/bundled_music_service.dart';
import '../../data/services/media_storage_service.dart';

// ==========================================
// Экран умного монтажа: ИИ собирает клип
// ✅ 8 стилей + ✅ синхронизация кадров по битам музыки
// ==========================================
class SmartMontageScreen extends ConsumerStatefulWidget {
  const SmartMontageScreen({super.key});

  @override
  ConsumerState<SmartMontageScreen> createState() => _SmartMontageScreenState();
}

class _SmartMontageScreenState extends ConsumerState<SmartMontageScreen> {
  bool _analyzing = false;
  double _progress = 0;
  String _progressText = '';

  List<SmartPhotoAnalysis> _analyses = [];
  MontageStyle _style = MontageStyle.auto;
  MontageStyle? _detected;

  // 🎵 Музыка
  File? _selectedMusic;
  AudioPlayer? _previewPlayer;
  String? _playingPath;

  // ⚡ Бит-синк
  bool _beatSync = true;
  BeatAnalysis? _beats;
  bool _beatsLoading = false;

  /// ✅ План клипа: стиль + (опционально) пересчёт длительностей под биты
  List<MontageFramePlan> get _plans {
    final base = SmartMontage.generate(
      analyses: _analyses,
      style: _style,
      canvasAspect: ref.read(currentProjectProvider).format.aspectRatio,
    );
    if (!_beatSync || _beats == null || !_beats!.isValid) return base;
    return [
      for (int i = 0; i < base.length; i++)
        _withBeatDuration(base[i], i, _beats!.beats),
    ];
  }

  /// Каждый кадр = 2 бита музыки
  MontageFramePlan _withBeatDuration(
      MontageFramePlan p, int i, List<double> beats) {
    const k = 2;
    final s = i * k;
    if (s >= beats.length - 1) return p;
    final e = math.min((i + 1) * k, beats.length - 1);
    final sec = (beats[e] - beats[s]).clamp(0.8, 6.0);
    return MontageFramePlan(
      imagePath: p.imagePath,
      durationMs: (sec * 1000).round(),
      transition: p.transition,
      filter: p.filter,
      entrance: p.entrance,
      entranceDurationMs: p.entranceDurationMs,
      fitMode: p.fitMode,
      offsetX: p.offsetX,
      offsetY: p.offsetY,
    );
  }

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  @override
  void dispose() {
    _previewPlayer?.dispose();
    super.dispose();
  }

  // ==========================================
  // Анализ всех фото проекта
  // ==========================================
  Future<void> _analyze() async {
    final paths = ref
        .read(currentProjectProvider)
        .photos
        .map((p) => p.imagePath)
        .toList();
    if (paths.isEmpty) return;

    setState(() {
      _analyzing = true;
      _progress = 0;
    });

    final results = <SmartPhotoAnalysis>[];
    for (int i = 0; i < paths.length; i++) {
      if (!mounted) return;
      setState(() =>
          _progressText = 'Анализирую фото ${i + 1} из ${paths.length}...');
      final a = await SmartAnalyzer.analyzePhoto(paths[i]);
      results.add(a);
      if (!mounted) return;
      setState(() => _progress = (i + 1) / paths.length);
    }

    final detected = SmartMontage.autoDetect(results);

    setState(() {
      _analyses = results;
      _detected = detected;
      _analyzing = false;
    });

    _autoPickMusic(detected);
  }

  // ==========================================
  // 🎵 Авто-подбор музыки по стилю
  // ==========================================
  void _autoPickMusic(MontageStyle style) {
    final bundled = ref.read(bundledMusicProvider);
    final file = bundled.pickForStyle(style.name);
    if (file != null) {
      setState(() => _selectedMusic = file);
      _detectBeats(file);
    }
  }

  // ==========================================
  // ⚡ Анализ битов выбранного трека
  // ==========================================
  Future<void> _detectBeats(File file) async {
    setState(() {
      _beatsLoading = true;
      _beats = null;
    });
    final analysis = await BeatDetector.detectBeats(file.path);
    if (!mounted) return;
    setState(() {
      _beats = analysis;
      _beatsLoading = false;
    });
  }

  // ==========================================
  // ▶️ Превью трека
  // ==========================================
  Future<void> _playPreview(String path) async {
    if (_playingPath == path &&
        _previewPlayer != null &&
        _previewPlayer!.playing) {
      await _previewPlayer!.pause();
      setState(() => _playingPath = null);
      return;
    }

    _previewPlayer?.dispose();
    _previewPlayer = AudioPlayer();
    try {
      await _previewPlayer!.setFilePath(path);
      await _previewPlayer!.play();
      setState(() => _playingPath = path);
    } catch (e) {
      print('⚠️ Ошибка превью: $e');
    }
  }

  void _stopPreview() {
    _previewPlayer?.stop();
    setState(() => _playingPath = null);
  }

  // ==========================================
  // 🎵 Выбор музыки (диалог)
  // ==========================================
  Future<void> _openMusicPicker() async {
    _stopPreview();
    final picked = await showMusicPicker(context, ref);
    if (picked != null && mounted) {
      setState(() => _selectedMusic = picked);
      _detectBeats(picked);
    }
  }

  // ==========================================
  // Применение плана к проекту
  // ==========================================
  Future<void> _apply() async {
    final notifier = ref.read(currentProjectProvider.notifier);
    final photos = ref.read(currentProjectProvider).photos;
    final plans = _plans;
    final beatApplied =
        _beatSync && _beats != null && _beats!.isValid && _selectedMusic != null;

    for (final plan in plans) {
      final idx = photos.indexWhere((p) => p.imagePath == plan.imagePath);
      if (idx < 0) continue;

      notifier.updatePhotoFit(
        index: idx,
        fitMode: plan.fitMode,
        scale: 1.0,
        offsetX: plan.offsetX,
        offsetY: plan.offsetY,
        backgroundType: BackgroundType.blur,
        backgroundColor: 0xFF000000,
      );

      notifier.updatePhotoDuration(idx, plan.durationMs);
      notifier.updatePhotoFilter(idx, plan.filter);
      notifier.updatePhotoTransition(idx, plan.transition);
      notifier.updatePhotoEntranceAnimation(idx, plan.entrance);
      notifier.updatePhotoEntranceDuration(idx, plan.entranceDurationMs);
    }

    if (_selectedMusic != null) {
      final name = _musicDisplayName(_selectedMusic!);
      final track = AudioTrack(
        filePath: _selectedMusic!.path,
        title: name,
        artist:
            BundledMusicService.isBundled(_selectedMusic!) ? 'Pixabay' : null,
        isFromInternet: false,
      );
      notifier.setAudioTrack(track);
    }

    if (mounted) {
      final msg = beatApplied
          ? '🤖 Умный монтаж + синхрон по битам (BPM ~${_beats!.bpm.round()})!'
          : (_selectedMusic != null
              ? '🤖 Умный монтаж применён с музыкой!'
              : '🤖 Умный монтаж применён!');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    }
  }

  // ==========================================
  // Вспомогательные
  // ==========================================
  String _musicDisplayName(File f) {
    if (BundledMusicService.isBundled(f)) {
      return BundledMusicService.displayName(f);
    }
    return MediaStorageService.displayName(f);
  }

  /// ✅ Подпись чипа стиля (с эмодзи для 4 тематических)
  String _styleLabel(MontageStyle s) {
    switch (s) {
      case MontageStyle.auto:
        return 'Авто';
      case MontageStyle.family:
        return 'Семья';
      case MontageStyle.travel:
        return 'Путешествие';
      case MontageStyle.party:
        return 'Вечеринка';
      case MontageStyle.romance:
        return 'Романтика';
      case MontageStyle.birthday:
        return '🎂 День рождения';
      case MontageStyle.wedding:
        return '💍 Свадьба';
      case MontageStyle.newyear:
        return '🎄 Новый год';
      case MontageStyle.nostalgia:
        return '📼 Ностальгия';
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          'Умный монтаж',
          style: GoogleFonts.unbounded(
              fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: _analyzing
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                        color: AppColors.primary),
                    const SizedBox(height: 24),
                    Text(
                      _progressText,
                      style: GoogleFonts.manrope(
                          fontSize: 14, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _progress,
                      color: AppColors.primary,
                      backgroundColor: AppColors.surfaceLight,
                    ),
                  ],
                ),
              ),
            )
          : _buildContent(plans),
    );
  }

  Widget _buildContent(List<MontageFramePlan> plans) {
    final totalFaces = _analyses.fold<int>(0, (s, a) => s + a.faceCount);
    final smiles = _analyses.where((a) => a.hasSmile).length;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ---- Выбор стиля ----
              Text(
                'Стиль монтажа',
                style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                'Авто-детект определяет 4 базовых стиля. Тематические — выбирайте вручную.',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: MontageStyle.values.map((s) {
                  final isSelected = _style == s;
                  return ChoiceChip(
                    label: Text(
                        s == MontageStyle.auto && _detected != null
                            ? 'Авто (${_styleLabel(_detected!)})'
                            : _styleLabel(s)),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() => _style = s);
                      final effective = s == MontageStyle.auto
                          ? (_detected ?? MontageStyle.family)
                          : s;
                      _autoPickMusic(effective);
                    },
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceLight,
                    labelStyle: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.primary.withValues(alpha: 0.3),
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // ---- Сводка анализа ----
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Stat(icon: Icons.face, label: 'Лиц: $totalFaces'),
                    _Stat(icon: Icons.mood, label: 'Улыбок: $smiles'),
                    _Stat(icon: Icons.timer, label: 'Кадров: ${plans.length}'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 🎵 ---- Блок музыки ----
              _MusicBlock(
                selectedMusic: _selectedMusic,
                playingPath: _playingPath,
                onPlay: _playPreview,
                onStop: _stopPreview,
                onChange: _openMusicPicker,
                displayName: _selectedMusic != null
                    ? _musicDisplayName(_selectedMusic!)
                    : null,
                isBundled: _selectedMusic != null
                    ? BundledMusicService.isBundled(_selectedMusic!)
                    : false,
              ),

              // ⚡ ---- Тумблер бит-синка ----
              if (_selectedMusic != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _beatSync,
                    activeColor: AppColors.primary,
                    onChanged: (v) {
                      setState(() => _beatSync = v);
                      if (v && _selectedMusic != null && _beats == null) {
                        _detectBeats(_selectedMusic!);
                      }
                    },
                    title: Text(
                      '⚡ Синхронизировать по битам',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      _beatsLoading
                          ? 'Анализирую биты…'
                          : (_beats != null && _beats!.isValid
                              ? 'Кадр = 2 бита • BPM ~${_beats!.bpm.round()}'
                              : 'Биты не найдены — темп по стилю'),
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        color: _beats != null && _beats!.isValid
                            ? AppColors.primary
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // ---- План клипа ----
              Text(
                'План клипа',
                style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              ...plans.asMap().entries.map((e) {
                final i = e.key;
                final plan = e.value;
                return _PlanCard(index: i, plan: plan);
              }),
            ],
          ),
        ),

        // ---- Кнопка применения ----
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _apply,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.auto_awesome, size: 20),
              label: Text(
                'Применить умный монтаж',
                style: GoogleFonts.manrope(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// 🎵 Блок музыки в умном монтаже
// ==========================================
class _MusicBlock extends StatelessWidget {
  final File? selectedMusic;
  final String? playingPath;
  final ValueChanged<String> onPlay;
  final VoidCallback onStop;
  final VoidCallback onChange;
  final String? displayName;
  final bool isBundled;

  const _MusicBlock({
    required this.selectedMusic,
    required this.playingPath,
    required this.onPlay,
    required this.onStop,
    required this.onChange,
    required this.displayName,
    required this.isBundled,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaying =
        selectedMusic != null && playingPath == selectedMusic!.path;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '🎵 Музыка',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onChange,
                child: Text(
                  selectedMusic != null ? 'Сменить' : 'Выбрать',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (selectedMusic == null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.music_off,
                      size: 20, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    'Без музыки',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () =>
                        isPlaying ? onStop() : onPlay(selectedMusic!.path),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 20,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName ?? '',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isBundled ? '✨ Встроенный трек' : 'Ваш трек',
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isBundled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'AI',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// Сводка-статистика
// ==========================================
class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Stat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
              fontSize: 12, color: AppColors.textPrimary),
        ),
      ],
    );
  }
}

// ==========================================
// Карточка кадра в плане
// ==========================================
class _PlanCard extends StatelessWidget {
  final int index;
  final MontageFramePlan plan;

  const _PlanCard({required this.index, required this.plan});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: ColorFiltered(
                colorFilter:
                    ColorFilter.matrix(FilterPresets.matrix(plan.filter)),
                child: Image.file(
                  File(plan.imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image, size: 20),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Кадр ${index + 1} • ${(plan.durationMs / 1000).toStringAsFixed(1)}s',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '${TransitionPresets.label(plan.transition)} • ${FilterPresets.label(plan.filter)}',
                  style: GoogleFonts.manrope(
                      fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.movie_filter,
            size: 18,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 🎵 Диалог выбора музыки (с превью)
// ==========================================
Future<File?> showMusicPicker(BuildContext context, WidgetRef ref) async {
  return showDialog<File>(
    context: context,
    builder: (ctx) => _MusicPickerDialog(ref: ref),
  );
}

class _MusicPickerDialog extends StatefulWidget {
  final WidgetRef ref;
  const _MusicPickerDialog({required this.ref});

  @override
  State<_MusicPickerDialog> createState() => _MusicPickerDialogState();
}

class _MusicPickerDialogState extends State<_MusicPickerDialog> {
  AudioPlayer? _player;
  String? _playingPath;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _play(String path) async {
    if (_playingPath == path && _player != null && _player!.playing) {
      await _player!.pause();
      setState(() => _playingPath = null);
      return;
    }
    _player?.dispose();
    _player = AudioPlayer();
    try {
      await _player!.setFilePath(path);
      await _player!.play();
      setState(() => _playingPath = path);
    } catch (e) {
      print('⚠️ Ошибка воспроизведения: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = widget.ref.watch(mediaStorageProvider);
    final allMusic = storage.listMusic();

    final bundled =
        allMusic.where((f) => BundledMusicService.isBundled(f)).toList();
    final user =
        allMusic.where((f) => !BundledMusicService.isBundled(f)).toList();

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
          maxWidth: 480,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.music_note, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Выберите музыку',
                    style: GoogleFonts.unbounded(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: AppColors.textMuted, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    if (bundled.isNotEmpty) ...[
                      Text(
                        '✨ Встроенные треки',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...bundled.map((f) => _MusicTile(
                            file: f,
                            isPlaying: _playingPath == f.path,
                            onPlay: () => _play(f.path),
                            onSelect: () => Navigator.pop(context, f),
                            displayName: BundledMusicService.displayName(f),
                            badge: '✨',
                          )),
                      const SizedBox(height: 16),
                    ],
                    if (user.isNotEmpty) ...[
                      Text(
                        '📁 Ваша музыка',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...user.map((f) => _MusicTile(
                            file: f,
                            isPlaying: _playingPath == f.path,
                            onPlay: () => _play(f.path),
                            onSelect: () => Navigator.pop(context, f),
                            displayName: MediaStorageService.displayName(f),
                          )),
                    ] else if (bundled.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              const Icon(Icons.music_off,
                                  size: 48, color: AppColors.textMuted),
                              const SizedBox(height: 8),
                              Text(
                                'Музыки пока нет',
                                style: GoogleFonts.manrope(
                                    color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, null),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'Без музыки',
                    style: GoogleFonts.manrope(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MusicTile extends StatelessWidget {
  final File file;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onSelect;
  final String displayName;
  final String? badge;

  const _MusicTile({
    required this.file,
    required this.isPlaying,
    required this.onPlay,
    required this.onSelect,
    required this.displayName,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPlaying
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onPlay,
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: AppColors.primary,
                size: 22,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      displayName,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (badge != null)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badge!,
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 10, color: AppColors.primary),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline,
                color: AppColors.primary, size: 22),
            onPressed: onSelect,
          ),
        ],
      ),
    );
  }
}