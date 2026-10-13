// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_project.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VideoProjectAdapter extends TypeAdapter<VideoProject> {
  @override
  final int typeId = 1;

  @override
  VideoProject read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VideoProject(
      id: fields[0] as String,
      name: fields[1] as String,
      photos: (fields[2] as List).cast<PhotoLayer>(),
      texts: (fields[3] as List).cast<TextLayer>(),
      audioTrack: fields[6] as AudioTrack?,
      createdAt: fields[4] as DateTime?,
      updatedAt: fields[5] as DateTime?,
      formatId: fields[7] == null ? 0 : fields[7] as int,
      overlayType:
          fields[8] == null ? OverlayType.none : fields[8] as OverlayType,
      overlayIntensity: fields[9] == null ? 0.6 : fields[9] as double,
      cinematicIntensity: fields[10] == null ? 0.5 : fields[10] as double,
    );
  }

  @override
  void write(BinaryWriter writer, VideoProject obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.photos)
      ..writeByte(3)
      ..write(obj.texts)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.updatedAt)
      ..writeByte(6)
      ..write(obj.audioTrack)
      ..writeByte(7)
      ..write(obj.formatId)
      ..writeByte(8)
      ..write(obj.overlayType)
      ..writeByte(9)
      ..write(obj.overlayIntensity)
      ..writeByte(10)
      ..write(obj.cinematicIntensity);
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

class OverlayTypeAdapter extends TypeAdapter<OverlayType> {
  @override
  final int typeId = 12;

  @override
  OverlayType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return OverlayType.none;
      case 1:
        return OverlayType.film;
      case 2:
        return OverlayType.cinema;
      case 3:
        return OverlayType.vhs;
      case 4:
        return OverlayType.lightleak;
      case 5:
        return OverlayType.dreamy;
      case 6:
        return OverlayType.bokeh;
      case 7:
        return OverlayType.snow;
      case 8:
        return OverlayType.cyber;
      default:
        return OverlayType.none;
    }
  }

  @override
  void write(BinaryWriter writer, OverlayType obj) {
    switch (obj) {
      case OverlayType.none:
        writer.writeByte(0);
        break;
      case OverlayType.film:
        writer.writeByte(1);
        break;
      case OverlayType.cinema:
        writer.writeByte(2);
        break;
      case OverlayType.vhs:
        writer.writeByte(3);
        break;
      case OverlayType.lightleak:
        writer.writeByte(4);
        break;
      case OverlayType.dreamy:
        writer.writeByte(5);
        break;
      case OverlayType.bokeh:
        writer.writeByte(6);
        break;
      case OverlayType.snow:
        writer.writeByte(7);
        break;
      case OverlayType.cyber:
        writer.writeByte(8);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlayTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
