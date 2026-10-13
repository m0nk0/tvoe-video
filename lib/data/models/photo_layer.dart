import 'package:hive/hive.dart';

part 'photo_layer.g.dart';

@HiveType(typeId: 2)
enum TransitionType {
  @HiveField(0) none, @HiveField(1) fade, @HiveField(2) slideLeft, @HiveField(3) slideRight,
  @HiveField(4) zoomIn, @HiveField(5) zoomOut, @HiveField(6) blur, @HiveField(7) rotate,
  @HiveField(8) flip, @HiveField(9) dissolve, @HiveField(10) wipe, @HiveField(11) glitch,
  @HiveField(12) whipPan, @HiveField(13) crossZoom, @HiveField(14) flash, @HiveField(15) circleReveal,
  @HiveField(16) spinBlur, @HiveField(17) rgbSplit,
}

@HiveType(typeId: 9)
enum EntranceAnimation {
  @HiveField(0) none, @HiveField(1) fadeIn, @HiveField(2) slideFromLeft, @HiveField(3) slideFromRight,
  @HiveField(4) slideFromTop, @HiveField(5) slideFromBottom, @HiveField(6) zoomIn, @HiveField(7) rotateIn,
}

@HiveType(typeId: 8)
enum FilterType {
  @HiveField(0) none, @HiveField(1) grayscale, @HiveField(2) sepia, @HiveField(3) noir,
  @HiveField(4) vintage, @HiveField(5) cool, @HiveField(6) warm, @HiveField(7) vivid,
  @HiveField(8) fade, @HiveField(9) film,
}

@HiveType(typeId: 10)
enum FitMode { @HiveField(0) cover, @HiveField(1) contain, }

@HiveType(typeId: 11)
enum BackgroundType { @HiveField(0) blur, @HiveField(1) color, }

@HiveType(typeId: 13)
enum LiveMotion {
  @HiveField(0) none, @HiveField(1) zoomIn, @HiveField(2) zoomOut,
  @HiveField(3) panLeft, @HiveField(4) panRight, @HiveField(5) breathe,
}

class FilterPresets {
  static const List<double> none = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
  static const List<double> grayscale = [0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0, 0, 0, 1, 0];
  static const List<double> sepia = [0.393, 0.769, 0.189, 0, 0, 0.349, 0.686, 0.168, 0, 0, 0.272, 0.534, 0.131, 0, 0, 0, 0, 0, 1, 0];
  static const List<double> noir = [0.33, 0.34, 0.33, 0, -25, 0.33, 0.34, 0.33, 0, -25, 0.33, 0.34, 0.33, 0, -25, 0, 0, 0, 1, 0];
  static const List<double> vintage = [0.9, 0.5, 0.1, 0, 30, 0.3, 0.8, 0.1, 0, 20, 0.2, 0.3, 0.5, 0, 10, 0, 0, 0, 1, 0];
  static const List<double> cool = [0.85, 0.05, 0.1, 0, 0, 0.05, 0.9, 0.05, 0, 0, 0.1, 0.05, 1.15, 0, 20, 0, 0, 0, 1, 0];
  static const List<double> warm = [1.15, 0.05, 0, 0, 15, 0.05, 1.0, 0.05, 0, 10, 0, 0.05, 0.85, 0, 0, 0, 0, 0, 1, 0];
  static const List<double> vivid = [1.3, -0.15, -0.15, 0, 0, -0.15, 1.3, -0.15, 0, 0, -0.15, -0.15, 1.3, 0, 0, 0, 0, 0, 1, 0];
  static const List<double> fade = [0.8, 0.1, 0.1, 0, 30, 0.1, 0.8, 0.1, 0, 30, 0.1, 0.1, 0.8, 0, 30, 0, 0, 0, 1, 0];
  static const List<double> film = [1.1, 0.1, 0.05, 0, 10, 0.05, 1.0, 0.1, 0, 5, 0, 0.1, 0.95, 0, 20, 0, 0, 0, 1, 0];

  static List<double> matrix(FilterType? type) {
    switch (type) {
      case FilterType.grayscale: return grayscale;
      case FilterType.sepia: return sepia;
      case FilterType.noir: return noir;
      case FilterType.vintage: return vintage;
      case FilterType.cool: return cool;
      case FilterType.warm: return warm;
      case FilterType.vivid: return vivid;
      case FilterType.fade: return fade;
      case FilterType.film: return film;
      case FilterType.none: default: return none;
    }
  }

  static String label(FilterType? type) {
    switch (type) {
      case FilterType.grayscale: return 'Ч/Б';
      case FilterType.sepia: return 'Сепия';
      case FilterType.noir: return 'Нуар';
      case FilterType.vintage: return 'Винтаж';
      case FilterType.cool: return 'Холод';
      case FilterType.warm: return 'Тепло';
      case FilterType.vivid: return 'Яркий';
      case FilterType.fade: return 'Матовый';
      case FilterType.film: return 'Кино';
      case FilterType.none: default: return 'Оригинал';
    }
  }
}

class TransitionPresets {
  static String label(TransitionType type) {
    switch (type) {
      case TransitionType.none: return 'Нет';
      case TransitionType.fade: return 'Фейд';
      case TransitionType.slideLeft: return 'Слайд ←';
      case TransitionType.slideRight: return 'Слайд →';
      case TransitionType.zoomIn: return 'Зум +';
      case TransitionType.zoomOut: return 'Зум −';
      case TransitionType.blur: return 'Блюр';
      case TransitionType.rotate: return 'Поворот';
      case TransitionType.flip: return 'Переворот';
      case TransitionType.dissolve: return 'Растворение';
      case TransitionType.wipe: return 'Стирание';
      case TransitionType.glitch: return 'Глитч';
      case TransitionType.whipPan: return '⚡ Хлыст';
      case TransitionType.crossZoom: return '🔍 Пролёт';
      case TransitionType.flash: return '✨ Вспышка';
      case TransitionType.circleReveal: return '⭕ Круг';
      case TransitionType.spinBlur: return '🌀 Спин';
      case TransitionType.rgbSplit: return '🌈 RGB';
    }
  }
}

class EntrancePresets {
  static String label(EntranceAnimation type) {
    switch (type) {
      case EntranceAnimation.none: return 'Нет';
      case EntranceAnimation.fadeIn: return 'Появление';
      case EntranceAnimation.slideFromLeft: return 'Слева';
      case EntranceAnimation.slideFromRight: return 'Справа';
      case EntranceAnimation.slideFromTop: return 'Сверху';
      case EntranceAnimation.slideFromBottom: return 'Снизу';
      case EntranceAnimation.zoomIn: return 'Зум';
      case EntranceAnimation.rotateIn: return 'Поворот';
    }
  }
}

class LiveMotionPresets {
  static String label(LiveMotion type) {
    switch (type) {
      case LiveMotion.none: return '⬜ Статично';
      case LiveMotion.zoomIn: return '🎯 Наезд';
      case LiveMotion.zoomOut: return '🔭 Отъезд';
      case LiveMotion.panLeft: return '⬅️ Панорама влево';
      case LiveMotion.panRight: return '➡️ Панорама вправо';
      case LiveMotion.breathe: return '💨 Дыхание';
    }
  }
}

@HiveType(typeId: 3)
class PhotoLayer {
  @HiveField(0) final String imagePath;
  @HiveField(1) final int durationMilliseconds;
  @HiveField(2) final TransitionType transition;
  @HiveField(3) final FilterType? filter;
  @HiveField(4, defaultValue: EntranceAnimation.none) final EntranceAnimation entranceAnimation;
  @HiveField(5, defaultValue: 500) final int entranceDurationMs;
  @HiveField(6, defaultValue: FitMode.cover) final FitMode fitMode;
  @HiveField(7, defaultValue: 1.0) final double scale;
  @HiveField(8, defaultValue: 0.0) final double offsetX;
  @HiveField(9, defaultValue: 0.0) final double offsetY;
  @HiveField(10, defaultValue: BackgroundType.blur) final BackgroundType backgroundType;
  @HiveField(11, defaultValue: 0xFF000000) final int backgroundColor;
  @HiveField(12, defaultValue: 600) final int transitionDurationMs;
  @HiveField(13, defaultValue: LiveMotion.breathe) final LiveMotion liveMotion;
  
  // 🎨 НОВОЕ: Матрица авто-гармонизации цвета (20 значений double)
  @HiveField(14, defaultValue: null) final List<double>? harmonizationMatrix;

  PhotoLayer({
    required this.imagePath,
    required this.durationMilliseconds,
    required this.transition,
    this.filter,
    this.entranceAnimation = EntranceAnimation.none,
    this.entranceDurationMs = 500,
    this.fitMode = FitMode.cover,
    this.scale = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.backgroundType = BackgroundType.blur,
    this.backgroundColor = 0xFF000000,
    this.transitionDurationMs = 600,
    this.liveMotion = LiveMotion.breathe,
    this.harmonizationMatrix,
  });

  PhotoLayer copyWith({
    String? imagePath,
    int? durationMilliseconds,
    TransitionType? transition,
    FilterType? filter,
    EntranceAnimation? entranceAnimation,
    int? entranceDurationMs,
    FitMode? fitMode,
    double? scale,
    double? offsetX,
    double? offsetY,
    BackgroundType? backgroundType,
    int? backgroundColor,
    int? transitionDurationMs,
    LiveMotion? liveMotion,
    List<double>? harmonizationMatrix,
  }) {
    return PhotoLayer(
      imagePath: imagePath ?? this.imagePath,
      durationMilliseconds: durationMilliseconds ?? this.durationMilliseconds,
      transition: transition ?? this.transition,
      filter: filter ?? this.filter,
      entranceAnimation: entranceAnimation ?? this.entranceAnimation,
      entranceDurationMs: entranceDurationMs ?? this.entranceDurationMs,
      fitMode: fitMode ?? this.fitMode,
      scale: scale ?? this.scale,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      backgroundType: backgroundType ?? this.backgroundType,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      transitionDurationMs: transitionDurationMs ?? this.transitionDurationMs,
      liveMotion: liveMotion ?? this.liveMotion,
      harmonizationMatrix: harmonizationMatrix ?? this.harmonizationMatrix,
    );
  }
}