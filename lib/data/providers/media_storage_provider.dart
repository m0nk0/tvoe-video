import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/media_storage_service.dart';

/// Riverpod-провайдер для синглтона MediaStorageService.
/// Используется везде, где нужен доступ к папкам photos/music/clips/exports.
final mediaStorageProvider = Provider<MediaStorageService>((ref) {
  return MediaStorageService();
});