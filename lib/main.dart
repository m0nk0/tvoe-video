import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/theme/app_theme.dart';
import 'data/models/audio_track.dart';
import 'data/models/photo_layer.dart';
import 'data/models/template.dart';
import 'data/models/text_layer.dart';
import 'data/models/video_project.dart';
import 'data/providers/projects_provider.dart';
import 'data/repositories/project_repository.dart';
import 'features/home/home_screen.dart';
import 'data/services/media_storage_service.dart';
import 'data/services/bundled_music_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация Hive
  await Hive.initFlutter();

  // Регистрация адаптеров моделей (строго по typeId из твоих файлов)
  Hive.registerAdapter(VideoProjectAdapter());       // typeId: 1
  Hive.registerAdapter(TransitionTypeAdapter());     // typeId: 2
  Hive.registerAdapter(PhotoLayerAdapter());         // typeId: 3
  Hive.registerAdapter(TextLayerAdapter());          // typeId: 4
  Hive.registerAdapter(AnimationTypeAdapter());      // typeId: 5
  Hive.registerAdapter(TemplateAdapter());           // typeId: 6
  Hive.registerAdapter(AudioTrackAdapter());         // typeId: 7
  Hive.registerAdapter(FilterTypeAdapter());         // typeId: 8
  Hive.registerAdapter(EntranceAnimationAdapter());  // typeId: 9
  Hive.registerAdapter(FitModeAdapter());            // typeId: 10
  Hive.registerAdapter(BackgroundTypeAdapter());     // typeId: 11
  Hive.registerAdapter(OverlayTypeAdapter());        // typeId: 12 (Именно он вызывал ошибку ранее)
  Hive.registerAdapter(LiveMotionAdapter());         // typeId: 13

  // ❌ VideoFormatAdapter() УДАЛЕН, так как VideoFormat не является Hive-типом (@HiveType)

  // Инициализация репозитория проектов
  final projectRepo = ProjectRepository();
  await projectRepo.init();

  // ✅ Инициализация хранилища медиа (папки clips/ и music/)
  final mediaStorage = MediaStorageService();
  await mediaStorage.init();

  // ✅ Инициализация встроенной музыки (копируем треки из assets)
  final bundledMusic = BundledMusicService(mediaStorage);
  await bundledMusic.initialize();

  runApp(
    ProviderScope(
      overrides: [
        projectRepositoryProvider.overrideWithValue(projectRepo),
        mediaStorageProvider.overrideWithValue(mediaStorage),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Твоё Видео',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}