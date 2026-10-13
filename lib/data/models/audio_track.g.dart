// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audio_track.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AudioTrackAdapter extends TypeAdapter<AudioTrack> {
  @override
  final int typeId = 7;

  @override
  AudioTrack read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AudioTrack(
      filePath: fields[0] as String,
      title: fields[1] as String,
      artist: fields[2] as String?,
      volume: fields[3] as double,
      startTime: fields[4] as double,
      isFromInternet: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, AudioTrack obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.filePath)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.artist)
      ..writeByte(3)
      ..write(obj.volume)
      ..writeByte(4)
      ..write(obj.startTime)
      ..writeByte(5)
      ..write(obj.isFromInternet);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioTrackAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
