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

  // Регистрация адаптеров моделей
  Hive.registerAdapter(VideoProjectAdapter());
  Hive.registerAdapter(PhotoLayerAdapter());
  Hive.registerAdapter(TextLayerAdapter());
  Hive.registerAdapter(TemplateAdapter());
  Hive.registerAdapter(TransitionTypeAdapter());
  Hive.registerAdapter(AnimationTypeAdapter());
  Hive.registerAdapter(AudioTrackAdapter());
  Hive.registerAdapter(FilterTypeAdapter());
  Hive.registerAdapter(EntranceAnimationAdapter()); // ✅ ДОБАВИТЬ
  Hive.registerAdapter(FitModeAdapter());        // ✅ ДОБАВИТЬ
  Hive.registerAdapter(BackgroundTypeAdapter()); // ✅ ДОБАВИТЬ
  
  // Инициализация репозитория проектов
  final projectRepo = ProjectRepository();
  await projectRepo.init();

    // ✅ Инициализация хранилища медиа (папки clips/ и music/)
  final mediaStorage = MediaStorageService();
  await mediaStorage.init();

  // ✅ Инициализация встроенной музыки (копируем 8 треков из assets)
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