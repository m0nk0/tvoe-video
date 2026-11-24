// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'keyframe.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class KeyframeAdapter extends TypeAdapter<Keyframe> {
  @override
  final int typeId = 14;

  @override
  Keyframe read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Keyframe(
      tMs: fields[0] as double,
      scale: fields[1] as double,
      offsetX: fields[2] as double,
      offsetY: fields[3] as double,
      opacity: fields[4] as double,
      rotation: fields[5] as double,
    );
  }

  @override
  void write(BinaryWriter writer, Keyframe obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.tMs)
      ..writeByte(1)
      ..write(obj.scale)
      ..writeByte(2)
      ..write(obj.offsetX)
      ..writeByte(3)
      ..write(obj.offsetY)
      ..writeByte(4)
      ..write(obj.opacity)
      ..writeByte(5)
      ..write(obj.rotation);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyframeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
