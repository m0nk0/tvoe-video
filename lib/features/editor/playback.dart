import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/photo_layer.dart';
import '../../data/providers/project_provider.dart';

// ==========================================
// Вспомогательные функции для таймлайна
// ==========================================
int frameStartMs(List<PhotoLayer> photos, int index) {
  int ms = 0;
  for (int i = 0; i < index && i < photos.length; i++) {
    ms += photos[i].durationMilliseconds;
  }
  return ms;
}

int frameIndexForMs(List<PhotoLayer> photos, int ms) {
  int accumulated = 0;
  for (int i = 0; i < photos.length; i++) {
    accumulated += photos[i].durationMilliseconds;
    if (ms < accumulated) return i;
  }
  return photos.length - 1;
}

// ==========================================
// Общее управление воспроизведением
// ==========================================
void togglePlayback(WidgetRef ref) {
  final photos = ref.read(currentProjectProvider).photos;
  if (photos.isEmpty) return;
  final total =
      photos.fold<int>(0, (s, p) => s + p.durationMilliseconds).toDouble();
  final playing = ref.read(isPlayingProvider);
  if (!playing && ref.read(playheadMsProvider) >= total) {
    ref.read(playheadMsProvider.notifier).state = 0;
  }
  ref.read(isPlayingProvider.notifier).state = !playing;
}

void stepPlayback(WidgetRef ref, int delta) {
  final photos = ref.read(currentProjectProvider).photos;
  if (photos.isEmpty) return;
  final cur = ref.read(selectedPhotoIndexProvider);
  final next = (cur + delta).clamp(0, photos.length - 1);
  ref.read(selectedPhotoIndexProvider.notifier).state = next;
  ref.read(playheadMsProvider.notifier).state =
      frameStartMs(photos, next).toDouble();
}