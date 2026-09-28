// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'template.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TemplateAdapter extends TypeAdapter<Template> {
  @override
  final int typeId = 3;

  @override
  Template read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Template(
      id: fields[0] as String,
      name: fields[1] as String,
      category: fields[2] as String,
      photoDurationMilliseconds: fields[3] as int,
      defaultTransition: fields[4] as TransitionType,
      musicPath: fields[5] as String?,
      previewImagePath: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Template obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.category)
      ..writeByte(3)
      ..write(obj.photoDurationMilliseconds)
      ..writeByte(4)
      ..write(obj.defaultTransition)
      ..writeByte(5)
      ..write(obj.musicPath)
      ..writeByte(6)
      ..write(obj.previewImagePath);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
