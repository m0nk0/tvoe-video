import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/photo_layer.dart';
import '../../data/providers/project_provider.dart';

// ==========================================
// Вспомогательные функции для таймлайна
// ==========================================

/// Время начала кадра в миллисекундах
int frameStartMs(List<PhotoLayer> photos, int index) {
  int ms = 0;
  for (int i = 0; i < index && i < photos.length; i++) {
    final rawDuration = photos[i].durationMilliseconds;
    // Defensive coding: приводим к int
    ms += rawDuration is int ? rawDuration : (rawDuration as num).toInt();
  }
  return ms;
}

/// Индекс кадра по времени в миллисекундах
int frameIndexForMs(List<PhotoLayer> photos, int ms) {
  int accumulated = 0;
  for (int i = 0; i < photos.length; i++) {
    final rawDuration = photos[i].durationMilliseconds;
    // Defensive coding: приводим к int
    accumulated += rawDuration is int ? rawDuration : (rawDuration as num).toInt();
    if (ms < accumulated) return i;
  }
  return photos.isEmpty ? 0 : photos.length - 1;
}

// ==========================================
// Общее управление воспроизведением
// ==========================================

/// Переключить воспроизведение
void togglePlayback(WidgetRef ref) {
  final photos = ref.read(currentProjectProvider).photos;
  if (photos.isEmpty) return;
  final total = photos.fold<int>(0, (s, p) {
    final rawDuration = p.durationMilliseconds;
    return s + (rawDuration is int ? rawDuration : (rawDuration as num).toInt());
  }).toDouble();
  
  final playing = ref.read(isPlayingProvider);
  if (!playing && ref.read(playheadMsProvider) >= total) {
    ref.read(playheadMsProvider.notifier).state = 0;
  }
  ref.read(isPlayingProvider.notifier).state = !playing;
}

/// Шаг на соседний кадр
void stepPlayback(WidgetRef ref, int delta) {
  final photos = ref.read(currentProjectProvider).photos;
  if (photos.isEmpty) return;
  final cur = ref.read(selectedPhotoIndexProvider);
  final next = (cur + delta).clamp(0, photos.length - 1);
  ref.read(selectedPhotoIndexProvider.notifier).state = next;
  ref.read(playheadMsProvider.notifier).state = frameStartMs(photos, next).toDouble();
}