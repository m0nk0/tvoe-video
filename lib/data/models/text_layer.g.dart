// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'text_layer.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TextLayerAdapter extends TypeAdapter<TextLayer> {
  @override
  final int typeId = 2;

  @override
  TextLayer read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TextLayer(
      text: fields[0] as String,
      fontFamily: fields[1] as String,
      fontSize: fields[2] as double,
      colorValue: fields[3] as int,
      startTimeMilliseconds: fields[4] as int,
      endTimeMilliseconds: fields[5] as int,
      animation: fields[6] as AnimationType,
      positionX: fields[7] as double,
      positionY: fields[8] as double,
    );
  }

  @override
  void write(BinaryWriter writer, TextLayer obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.text)
      ..writeByte(1)
      ..write(obj.fontFamily)
      ..writeByte(2)
      ..write(obj.fontSize)
      ..writeByte(3)
      ..write(obj.colorValue)
      ..writeByte(4)
      ..write(obj.startTimeMilliseconds)
      ..writeByte(5)
      ..write(obj.endTimeMilliseconds)
      ..writeByte(6)
      ..write(obj.animation)
      ..writeByte(7)
      ..write(obj.positionX)
      ..writeByte(8)
      ..write(obj.positionY);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextLayerAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AnimationTypeAdapter extends TypeAdapter<AnimationType> {
  @override
  final int typeId = 11;

  @override
  AnimationType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AnimationType.none;
      case 1:
        return AnimationType.fadeIn;
      case 2:
        return AnimationType.slideUp;
      case 3:
        return AnimationType.slideDown;
      case 4:
        return AnimationType.typewriter;
      default:
        return AnimationType.none;
    }
  }

  @override
  void write(BinaryWriter writer, AnimationType obj) {
    switch (obj) {
      case AnimationType.none:
        writer.writeByte(0);
        break;
      case AnimationType.fadeIn:
        writer.writeByte(1);
        break;
      case AnimationType.slideUp:
        writer.writeByte(2);
        break;
      case AnimationType.slideDown:
        writer.writeByte(3);
        break;
      case AnimationType.typewriter:
        writer.writeByte(4);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnimationTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
