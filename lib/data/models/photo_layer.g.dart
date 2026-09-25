// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_layer.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PhotoLayerAdapter extends TypeAdapter<PhotoLayer> {
  @override
  final int typeId = 1;

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
      scale: fields[3] as double,
      positionX: fields[4] as double,
      positionY: fields[5] as double,
    );
  }

  @override
  void write(BinaryWriter writer, PhotoLayer obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.imagePath)
      ..writeByte(1)
      ..write(obj.durationMilliseconds)
      ..writeByte(2)
      ..write(obj.transition)
      ..writeByte(3)
      ..write(obj.scale)
      ..writeByte(4)
      ..write(obj.positionX)
      ..writeByte(5)
      ..write(obj.positionY);
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
  final int typeId = 10;

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
