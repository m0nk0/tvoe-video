import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/colors.dart';
import '../../data/models/photo_layer.dart';
import '../../data/providers/project_provider.dart';
import '../../data/providers/projects_provider.dart';
import 'text_tools.dart';

// ==========================================
// Общее управление воспроизведением
// ==========================================
void togglePlayback(WidgetRef ref) {
  final photos = ref.read(currentProjectProvider).photos;
  if (photos.isEmpty) return;
  final total = photos.fold<int>(0, (s, p) => s + p.durationMilliseconds).toDouble();
  final playing = ref.read(isPlayingProvider);
  // Если стоим в конце — начинаем заново
  if (!playing && ref.read(playheadMsProvider) >= total) {
    ref.read(playheadMsProvider.notifier).state = 0;
  }
  ref.read(isPlayingProvider.notifier).state = !playing;
}

void _step(WidgetRef ref, int delta) {
  final photos = ref.read(currentProjectProvider).photos;
  if (photos.isEmpty) return;
  final cur = ref.read(selectedPhotoIndexProvider);
  final next = (cur + delta).clamp(0, photos.length - 1);
  ref.read(selectedPhotoIndexProvider.notifier).state = next;
  ref.read(playheadMsProvider.notifier).state = frameStartMs(photos, next).toDouble();
}

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  double timelineZoom = 1.0;
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Тик воспроизведения: плейхед едет по шкале времени
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

  /// Сохраняем проект в Hive и выходим
  Future<void> _saveAndPop() async {
    ref.read(isPlayingProvider.notifier).state = false;
    final project = ref.read(currentProjectProvider);
    if (project.photos.isNotEmpty) {
      await ref.read(projectRepositoryProvider).saveProject(project);
      ref.read(projectsProvider.notifier).refresh();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Синхронизируем тикер с состоянием воспроизведения
    ref.listen<bool>(isPlayingProvider, (prev, playing) {
      if (playing) {
        _startTick();
      } else {
        _tick?.cancel();
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
            style: GoogleFonts.unbounded(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // TODO: Переход на экран экспорта
              },
              child: Text(
                'Экспорт',
                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.primary),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // A. Превью — максимум места
              const Expanded(child: _PreviewArea()),
              Container(height: 1, color: AppColors.surfaceLight),

              // B. Панель инструментов
              SizedBox(
                height: 92,
                child: _Toolbar(
                  onAddPhoto: () => ref.read(currentProjectProvider.notifier).addPhotosFromGallery(),
                  onAddText: () => showTextManagerSheet(context, ref),
                ),
              ),
              Container(height: 1, color: AppColors.surfaceLight),

              // C. Таймлайн с непрерывным плейхедом
              SizedBox(
                height: 170,
                child: _Timeline(
                  zoom: timelineZoom,
                  onZoomChanged: (value) => setState(() => timelineZoom = value),
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
// A. Превью: слайд-шоу с переходами + текст
// ==========================================
class _PreviewArea extends ConsumerWidget {
  const _PreviewArea();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(currentProjectProvider);
    final selectedIndex = ref.watch(selectedPhotoIndexProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final hasPhotos = project.photos.isNotEmpty;
    final safeIndex = hasPhotos ? selectedIndex.clamp(0, project.photos.length - 1) : 0;
    final currentTransition = hasPhotos ? project.photos[safeIndex].transition : TransitionType.none;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 2),
            ),
            child: !hasPhotos
                ? const Center(child: Icon(Icons.crop_portrait, size: 64, color: AppColors.textMuted))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Кадр с анимированным переходом
                        Positioned.fill(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 450),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) =>
                                _buildTransition(child, animation, currentTransition),
                            child: SizedBox.expand(
                              key: ValueKey('${project.photos[safeIndex].imagePath}_$safeIndex'),
                              child: Image.file(
                                File(project.photos[safeIndex].imagePath),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.broken_image, color: AppColors.error),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Текстовые оверлеи (заголовок / субтитры)
                        ...buildTextOverlays(project, safeIndex),

                        // Панель управления воспроизведением
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(40),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.skip_previous, color: Colors.white, size: 28),
                                  disabledColor: AppColors.textMuted.withValues(alpha: 0.3),
                                  onPressed: safeIndex > 0 ? () => _step(ref, -1) : null,
                                ),
                                IconButton(
                                  icon: Icon(
                                    isPlaying ? Icons.pause : Icons.play_arrow,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                  onPressed: () => togglePlayback(ref),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.skip_next, color: Colors.white, size: 28),
                                  disabledColor: AppColors.textMuted.withValues(alpha: 0.3),
                                  onPressed: safeIndex < project.photos.length - 1 ? () => _step(ref, 1) : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// Построение перехода по типу
// ==========================================
Widget _buildTransition(Widget child, Animation<double> animation, TransitionType type) {
  switch (type) {
    case TransitionType.none:
      return child;
    case TransitionType.fade:
      return FadeTransition(opacity: animation, child: child);
    case TransitionType.slideLeft:
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(animation),
        child: child,
      );
    case TransitionType.slideRight:
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero).animate(animation),
        child: child,
      );
    case TransitionType.zoomIn:
      return ScaleTransition(
        scale: Tween<double>(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: FadeTransition(opacity: animation, child: child),
      );
    case TransitionType.zoomOut:
      return ScaleTransition(
        scale: Tween<double>(begin: 1.4, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: FadeTransition(opacity: animation, child: child),
      );
    case TransitionType.blur:
      return _BlurTransition(animation: animation, child: child);
  }
}

// ==========================================
// Блюр-переход
// ==========================================
class _BlurTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _BlurTransition({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, c) {
        final t = animation.value.clamp(0.0, 1.0);
        final sigma = (1.0 - t) * 12.0;
        return Opacity(
          opacity: t,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: c,
          ),
        );
      },
      child: child,
    );
  }
}

// ==========================================
// B. Панель инструментов
// ==========================================
class _Toolbar extends StatelessWidget {
  final VoidCallback onAddPhoto;
  final VoidCallback onAddText;

  const _Toolbar({required this.onAddPhoto, required this.onAddText});

  @override
  Widget build(BuildContext context) {
    final tools = [
      {'icon': Icons.add_photo_alternate, 'label': 'Фото', 'action': onAddPhoto},
      {'icon': Icons.content_cut, 'label': 'Обрезать', 'action': () {}},
      {'icon': Icons.music_note, 'label': 'Музыка', 'action': () {}},
      {'icon': Icons.auto_fix_high, 'label': 'Эффекты', 'action': () {}},
      {'icon': Icons.text_fields, 'label': 'Текст', 'action': onAddText},
      {'icon': Icons.tune, 'label': 'Фильтры', 'action': () {}},
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

// ==========================================
// C. Таймлайн: непрерывный плейхед (в мс)
// ==========================================
class _Timeline extends ConsumerStatefulWidget {
  final double zoom;
  final ValueChanged<double> onZoomChanged;

  const _Timeline({required this.zoom, required this.onZoomChanged});

  @override
  ConsumerState<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends ConsumerState<_Timeline> {
  final ScrollController _controller = ScrollController();
  bool _scrubbing = false;

  static const double _padLeft = 40.0;

  /// Пикселей на миллисекунду (зум влияет на масштаб)
  double get _pxPerMs => (80 / 3000) * widget.zoom;

  @override
  void initState() {
    super.initState();
    // Перерисовка позиции плейхеда при скролле ленты
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _widthOf(PhotoLayer p) => (p.durationMilliseconds * _pxPerMs).clamp(48.0, 400.0);

  /// X-координата момента времени ms в контенте ленты
  double _xForMs(List<PhotoLayer> photos, double ms) {
    double x = _padLeft;
    for (int i = 0; i < photos.length; i++) {
      final w = _widthOf(photos[i]);
      final d = photos[i].durationMilliseconds.toDouble();
      if (ms <= d) {
        return x + (d > 0 ? (ms / d) * w : 0);
      }
      x += w;
      ms -= d;
    }
    return x;
  }

  /// Мс на пиксель в текущем кадре (для скраббинга)
  double _msPerPxAt(List<PhotoLayer> photos, double ms) {
    if (photos.isEmpty) return 0;
    final idx = frameIndexForMs(photos, ms.round());
    final p = photos[idx];
    final w = _widthOf(p);
    if (w <= 0) return 0;
    return p.durationMilliseconds / w;
  }

  /// Лента догоняет плейхед у краёв экрана
  void _followPlayhead(double xContent, bool active) {
    if (!active || !_controller.hasClients) return;
    final vp = _controller.position.viewportDimension;
    final max = _controller.position.maxScrollExtent;
    final xs = xContent - _controller.offset;
    if (xs > vp - 24) {
      _controller.jumpTo((_controller.offset + (xs - (vp - 24))).clamp(0.0, max));
    } else if (xs < 24 && _controller.offset > 0) {
      _controller.jumpTo((_controller.offset + (xs - 24)).clamp(0.0, max));
    }
  }

  void _goStart() {
    ref.read(isPlayingProvider.notifier).state = false;
    ref.read(playheadMsProvider.notifier).state = 0;
    if (_controller.hasClients) _controller.jumpTo(0);
    setState(() {});
  }

  void _goEnd() {
    ref.read(isPlayingProvider.notifier).state = false;
    final photos = ref.read(currentProjectProvider).photos;
    final total = photos.fold<int>(0, (s, p) => s + p.durationMilliseconds).toDouble();
    ref.read(playheadMsProvider.notifier).state = total;
    if (_controller.hasClients) _controller.jumpTo(_controller.position.maxScrollExtent);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Движение плейхеда: синхронизация индекса кадра + автодогон ленты
    ref.listen<double>(playheadMsProvider, (prev, ms) {
      final photos = ref.read(currentProjectProvider).photos;
      if (photos.isEmpty) return;
      final idx = frameIndexForMs(photos, ms.round());
      if (idx != ref.read(selectedPhotoIndexProvider)) {
        ref.read(selectedPhotoIndexProvider.notifier).state = idx;
      }
      _followPlayhead(_xForMs(photos, ms), ref.read(isPlayingProvider) || _scrubbing);
      setState(() {});
    });

    final project = ref.watch(currentProjectProvider);
    final selectedIndex = ref.watch(selectedPhotoIndexProvider);
    final playheadMs = ref.watch(playheadMsProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final totalMs = project.photos.fold<int>(0, (sum, p) => sum + p.durationMilliseconds);
    final offset = _controller.hasClients ? _controller.offset : 0.0;
    final xScreen = _xForMs(project.photos, playheadMs) - offset;

    return Column(
      children: [
        // Строка управления: начало / Play + таймкод / зум / конец
        SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _EdgeButton(icon: Icons.first_page, onTap: _goStart),
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => togglePlayback(ref),
                          child: Container(
                            width: 34,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${_fmtMs(playheadMs.round())} / ${_fmtMs(totalMs)}',
                          style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                _ZoomControl(zoom: widget.zoom, onZoomChanged: widget.onZoomChanged),
                const SizedBox(width: 8),
                _EdgeButton(icon: Icons.last_page, onTap: _goEnd),
              ],
            ),
          ),
        ),

        // Полоса с кадрами + плейхед (ничего не перекрывает)
        Expanded(
          child: Stack(
            children: [
              if (project.photos.isEmpty)
                Center(
                  child: Text(
                    'Нажмите "Фото", чтобы добавить изображения',
                    style: GoogleFonts.manrope(color: AppColors.textMuted, fontSize: 14),
                  ),
                )
              else
                ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  scrollController: _controller,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  itemCount: project.photos.length,
                  onReorder: (oldIndex, newIndex) =>
                      ref.read(currentProjectProvider.notifier).reorderPhotos(oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final photo = project.photos[index];
                    return _TimelineItem(
                      key: ValueKey('${photo.imagePath}_$index'),
                      photo: photo,
                      isSelected: index == selectedIndex,
                      width: _widthOf(photo),
                      onTap: () {
                        ref.read(selectedPhotoIndexProvider.notifier).state = index;
                        ref.read(playheadMsProvider.notifier).state =
                            frameStartMs(project.photos, index).toDouble();
                        showPhotoSettingsSheet(context, ref, index);
                      },
                    );
                  },
                ),

              // Плейхед: ездит по ленте, цепляем и тянем
              if (project.photos.isNotEmpty)
                Positioned(
                  left: xScreen - 12,
                  width: 24,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onHorizontalDragStart: (_) => _scrubbing = true,
                    onHorizontalDragUpdate: (details) {
                      final photos = ref.read(currentProjectProvider).photos;
                      if (photos.isEmpty) return;
                      final ms = ref.read(playheadMsProvider);
                      final deltaMs = details.delta.dx * _msPerPxAt(photos, ms);
                      ref.read(playheadMsProvider.notifier).state =
                          (ms + deltaMs).clamp(0.0, totalMs.toDouble());
                    },
                    onHorizontalDragEnd: (_) => _scrubbing = false,
                    child: Container(
                      color: Colors.transparent,
                      child: Column(
                        children: [
                          CustomPaint(
                            size: const Size(16, 12),
                            painter: _TrianglePainter(color: AppColors.primary),
                          ),
                          Expanded(
                            child: Container(width: 2, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ==========================================
// Кнопка начало/конец
// ==========================================
class _EdgeButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _EdgeButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, size: 18, color: AppColors.primary),
      ),
    );
  }
}

// ==========================================
// Компактный зум-контрол (в строке управления)
// ==========================================
class _ZoomControl extends StatelessWidget {
  final double zoom;
  final ValueChanged<double> onZoomChanged;

  const _ZoomControl({required this.zoom, required this.onZoomChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.remove, color: AppColors.textMuted, size: 14),
          SizedBox(
            width: 56,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: AppColors.surfaceLight,
                thumbColor: AppColors.primary,
                overlayColor: AppColors.primary.withValues(alpha: 0.2),
              ),
              child: Slider(value: zoom, min: 0.8, max: 1.3, onChanged: onZoomChanged),
            ),
          ),
          const Icon(Icons.add, color: AppColors.textMuted, size: 14),
        ],
      ),
    );
  }
}

// ==========================================
// Формат времени м:сс
// ==========================================
String _fmtMs(int ms) {
  final d = Duration(milliseconds: ms);
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

// ==========================================
// Миниатюра кадра (ширина = длительность)
// ==========================================
class _TimelineItem extends StatelessWidget {
  final PhotoLayer photo;
  final bool isSelected;
  final double width;
  final VoidCallback onTap;

  const _TimelineItem({
    super.key,
    required this.photo,
    required this.isSelected,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: width,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(photo.imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: AppColors.error),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(photo.durationMilliseconds / 1000).toStringAsFixed(1)}s',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: isSelected ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// Bottom sheet: длительность + переход + удаление
// ==========================================
void showPhotoSettingsSheet(BuildContext context, WidgetRef ref, int index) {
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
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final current = ref.read(currentProjectProvider);
            if (index >= current.photos.length) return const SizedBox.shrink();
            final photo = current.photos[index];
            final ms = photo.durationMilliseconds;

            return SingleChildScrollView(
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
                    'Настройки кадра ${index + 1}',
                    style: GoogleFonts.unbounded(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Длительность', style: GoogleFonts.manrope(fontSize: 14, color: AppColors.textSecondary)),
                      Text(
                        '${(ms / 1000).toStringAsFixed(1)} сек',
                        style: GoogleFonts.jetBrainsMono(fontSize: 14, color: AppColors.primary),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: AppColors.surfaceLight,
                      thumbColor: AppColors.primary,
                      overlayColor: AppColors.primary.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: (ms / 1000).clamp(1.0, 5.0),
                      min: 1.0,
                      max: 5.0,
                      divisions: 8,
                      onChanged: (value) {
                        ref.read(currentProjectProvider.notifier).updatePhotoDuration(index, (value * 1000).round());
                        setSheetState(() {});
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Переход', style: GoogleFonts.manrope(fontSize: 14, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: TransitionType.values.map((type) {
                      final isSelected = photo.transition == type;
                      return ChoiceChip(
                        label: Text(_transitionLabel(type)),
                        selected: isSelected,
                        onSelected: (_) {
                          ref.read(currentProjectProvider.notifier).updatePhotoTransition(index, type);
                          setSheetState(() {});
                        },
                        selectedColor: AppColors.primary,
                        backgroundColor: AppColors.surfaceLight,
                        labelStyle: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                        ),
                        side: BorderSide(
                          color: isSelected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ref.read(currentProjectProvider.notifier).removePhoto(index);
                        final remaining = ref.read(currentProjectProvider).photos.length;
                        final selected = ref.read(selectedPhotoIndexProvider);
                        if (remaining == 0) {
                          ref.read(selectedPhotoIndexProvider.notifier).state = 0;
                          ref.read(playheadMsProvider.notifier).state = 0;
                        } else if (selected >= remaining) {
                          ref.read(selectedPhotoIndexProvider.notifier).state = remaining - 1;
                        }
                        Navigator.pop(sheetContext);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: Text('Удалить кадр', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600)),
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

/// Подписи переходов на русском
String _transitionLabel(TransitionType type) {
  switch (type) {
    case TransitionType.none:
      return 'Нет';
    case TransitionType.fade:
      return 'Фейд';
    case TransitionType.slideLeft:
      return 'Слайд ←';
    case TransitionType.slideRight:
      return 'Слайд →';
    case TransitionType.zoomIn:
      return 'Зум +';
    case TransitionType.zoomOut:
      return 'Зум −';
    case TransitionType.blur:
      return 'Блюр';
  }
}

// ==========================================
// Треугольник плейхеда
// ==========================================
class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}