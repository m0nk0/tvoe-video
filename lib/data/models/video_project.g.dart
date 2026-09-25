// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_project.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VideoProjectAdapter extends TypeAdapter<VideoProject> {
  @override
  final int typeId = 0;

  @override
  VideoProject read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VideoProject(
      id: fields[0] as String,
      name: fields[1] as String,
      createdAtMilliseconds: fields[2] as int,
      photos: (fields[3] as List?)?.cast<PhotoLayer>(),
      texts: (fields[4] as List?)?.cast<TextLayer>(),
      template: fields[5] as Template?,
    );
  }

  @override
  void write(BinaryWriter writer, VideoProject obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.createdAtMilliseconds)
      ..writeByte(3)
      ..write(obj.photos)
      ..writeByte(4)
      ..write(obj.texts)
      ..writeByte(5)
      ..write(obj.template);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoProjectAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
