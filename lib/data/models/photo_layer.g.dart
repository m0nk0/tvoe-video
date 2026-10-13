// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_layer.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PhotoLayerAdapter extends TypeAdapter<PhotoLayer> {
  @override
  final int typeId = 3;

  @override
  PhotoLayer read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PhotoLayer(
      imagePath: fields[0] as String,
      durationMilliseconds: fields[1] as int,
      transition: fields[2] as TransitionType,
      filter: fields[3] as FilterType?,
      entranceAnimation: fields[4] == null
          ? EntranceAnimation.none
          : fields[4] as EntranceAnimation,
      entranceDurationMs: fields[5] == null ? 500 : fields[5] as int,
      fitMode: fields[6] == null ? FitMode.cover : fields[6] as FitMode,
      scale: fields[7] == null ? 1.0 : fields[7] as double,
      offsetX: fields[8] == null ? 0.0 : fields[8] as double,
      offsetY: fields[9] == null ? 0.0 : fields[9] as double,
      backgroundType: fields[10] == null
          ? BackgroundType.blur
          : fields[10] as BackgroundType,
      backgroundColor: fields[11] == null ? 4278190080 : fields[11] as int,
      transitionDurationMs: fields[12] == null ? 600 : fields[12] as int,
      liveMotion:
          fields[13] == null ? LiveMotion.breathe : fields[13] as LiveMotion,
      harmonizationMatrix: (fields[14] as List?)?.cast<double>(),
    );
  }

  @override
  void write(BinaryWriter writer, PhotoLayer obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.imagePath)
      ..writeByte(1)
      ..write(obj.durationMilliseconds)
      ..writeByte(2)
      ..write(obj.transition)
      ..writeByte(3)
      ..write(obj.filter)
      ..writeByte(4)
      ..write(obj.entranceAnimation)
      ..writeByte(5)
      ..write(obj.entranceDurationMs)
      ..writeByte(6)
      ..write(obj.fitMode)
      ..writeByte(7)
      ..write(obj.scale)
      ..writeByte(8)
      ..write(obj.offsetX)
      ..writeByte(9)
      ..write(obj.offsetY)
      ..writeByte(10)
      ..write(obj.backgroundType)
      ..writeByte(11)
      ..write(obj.backgroundColor)
      ..writeByte(12)
      ..write(obj.transitionDurationMs)
      ..writeByte(13)
      ..write(obj.liveMotion)
      ..writeByte(14)
      ..write(obj.harmonizationMatrix);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoLayerAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TransitionTypeAdapter extends TypeAdapter<TransitionType> {
  @override
  final int typeId = 2;

  @override
  TransitionType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TransitionType.none;
      case 1:
        return TransitionType.fade;
      case 2:
        return TransitionType.slideLeft;
      case 3:
        return TransitionType.slideRight;
      case 4:
        return TransitionType.zoomIn;
      case 5:
        return TransitionType.zoomOut;
      case 6:
        return TransitionType.blur;
      case 7:
        return TransitionType.rotate;
      case 8:
        return TransitionType.flip;
      case 9:
        return TransitionType.dissolve;
      case 10:
        return TransitionType.wipe;
      case 11:
        return TransitionType.glitch;
      case 12:
        return TransitionType.whipPan;
      case 13:
        return TransitionType.crossZoom;
      case 14:
        return TransitionType.flash;
      case 15:
        return TransitionType.circleReveal;
      case 16:
        return TransitionType.spinBlur;
      case 17:
        return TransitionType.rgbSplit;
      default:
        return TransitionType.none;
    }
  }

  @override
  void write(BinaryWriter writer, TransitionType obj) {
    switch (obj) {
      case TransitionType.none:
        writer.writeByte(0);
        break;
      case TransitionType.fade:
        writer.writeByte(1);
        break;
      case TransitionType.slideLeft:
        writer.writeByte(2);
        break;
      case TransitionType.slideRight:
        writer.writeByte(3);
        break;
      case TransitionType.zoomIn:
        writer.writeByte(4);
        break;
      case TransitionType.zoomOut:
        writer.writeByte(5);
        break;
      case TransitionType.blur:
        writer.writeByte(6);
        break;
      case TransitionType.rotate:
        writer.writeByte(7);
        break;
      case TransitionType.flip:
        writer.writeByte(8);
        break;
      case TransitionType.dissolve:
        writer.writeByte(9);
        break;
      case TransitionType.wipe:
        writer.writeByte(10);
        break;
      case TransitionType.glitch:
        writer.writeByte(11);
        break;
      case TransitionType.whipPan:
        writer.writeByte(12);
        break;
      case TransitionType.crossZoom:
        writer.writeByte(13);
        break;
      case TransitionType.flash:
        writer.writeByte(14);
        break;
      case TransitionType.circleReveal:
        writer.writeByte(15);
        break;
      case TransitionType.spinBlur:
        writer.writeByte(16);
        break;
      case TransitionType.rgbSplit:
        writer.writeByte(17);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransitionTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class EntranceAnimationAdapter extends TypeAdapter<EntranceAnimation> {
  @override
  final int typeId = 9;

  @override
  EntranceAnimation read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return EntranceAnimation.none;
      case 1:
        return EntranceAnimation.fadeIn;
      case 2:
        return EntranceAnimation.slideFromLeft;
      case 3:
        return EntranceAnimation.slideFromRight;
      case 4:
        return EntranceAnimation.slideFromTop;
      case 5:
        return EntranceAnimation.slideFromBottom;
      case 6:
        return EntranceAnimation.zoomIn;
      case 7:
        return EntranceAnimation.rotateIn;
      default:
        return EntranceAnimation.none;
    }
  }

  @override
  void write(BinaryWriter writer, EntranceAnimation obj) {
    switch (obj) {
      case EntranceAnimation.none:
        writer.writeByte(0);
        break;
      case EntranceAnimation.fadeIn:
        writer.writeByte(1);
        break;
      case EntranceAnimation.slideFromLeft:
        writer.writeByte(2);
        break;
      case EntranceAnimation.slideFromRight:
        writer.writeByte(3);
        break;
      case EntranceAnimation.slideFromTop:
        writer.writeByte(4);
        break;
      case EntranceAnimation.slideFromBottom:
        writer.writeByte(5);
        break;
      case EntranceAnimation.zoomIn:
        writer.writeByte(6);
        break;
      case EntranceAnimation.rotateIn:
        writer.writeByte(7);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EntranceAnimationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class FilterTypeAdapter extends TypeAdapter<FilterType> {
  @override
  final int typeId = 8;

  @override
  FilterType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return FilterType.none;
      case 1:
        return FilterType.grayscale;
      case 2:
        return FilterType.sepia;
      case 3:
        return FilterType.noir;
      case 4:
        return FilterType.vintage;
      case 5:
        return FilterType.cool;
      case 6:
        return FilterType.warm;
      case 7:
        return FilterType.vivid;
      case 8:
        return FilterType.fade;
      case 9:
        return FilterType.film;
      default:
        return FilterType.none;
    }
  }

  @override
  void write(BinaryWriter writer, FilterType obj) {
    switch (obj) {
      case FilterType.none:
        writer.writeByte(0);
        break;
      case FilterType.grayscale:
        writer.writeByte(1);
        break;
      case FilterType.sepia:
        writer.writeByte(2);
        break;
      case FilterType.noir:
        writer.writeByte(3);
        break;
      case FilterType.vintage:
        writer.writeByte(4);
        break;
      case FilterType.cool:
        writer.writeByte(5);
        break;
      case FilterType.warm:
        writer.writeByte(6);
        break;
      case FilterType.vivid:
        writer.writeByte(7);
        break;
      case FilterType.fade:
        writer.writeByte(8);
        break;
      case FilterType.film:
        writer.writeByte(9);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilterTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class FitModeAdapter extends TypeAdapter<FitMode> {
  @override
  final int typeId = 10;

  @override
  FitMode read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return FitMode.cover;
      case 1:
        return FitMode.contain;
      default:
        return FitMode.cover;
    }
  }

  @override
  void write(BinaryWriter writer, FitMode obj) {
    switch (obj) {
      case FitMode.cover:
        writer.writeByte(0);
        break;
      case FitMode.contain:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FitModeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class BackgroundTypeAdapter extends TypeAdapter<BackgroundType> {
  @override
  final int typeId = 11;

  @override
  BackgroundType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return BackgroundType.blur;
      case 1:
        return BackgroundType.color;
      default:
        return BackgroundType.blur;
    }
  }

  @override
  void write(BinaryWriter writer, BackgroundType obj) {
    switch (obj) {
      case BackgroundType.blur:
        writer.writeByte(0);
        break;
      case BackgroundType.color:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackgroundTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class LiveMotionAdapter extends TypeAdapter<LiveMotion> {
  @override
  final int typeId = 13;

  @override
  LiveMotion read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return LiveMotion.none;
      case 1:
        return LiveMotion.zoomIn;
      case 2:
        return LiveMotion.zoomOut;
      case 3:
        return LiveMotion.panLeft;
      case 4:
        return LiveMotion.panRight;
      case 5:
        return LiveMotion.breathe;
      default:
        return LiveMotion.none;
    }
  }

  @override
  void write(BinaryWriter writer, LiveMotion obj) {
    switch (obj) {
      case LiveMotion.none:
        writer.writeByte(0);
        break;
      case LiveMotion.zoomIn:
        writer.writeByte(1);
        break;
      case LiveMotion.zoomOut:
        writer.writeByte(2);
        break;
      case LiveMotion.panLeft:
        writer.writeByte(3);
        break;
      case LiveMotion.panRight:
        writer.writeByte(4);
        break;
      case LiveMotion.breathe:
        writer.writeByte(5);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveMotionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
