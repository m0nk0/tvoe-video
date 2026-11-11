import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Для rootBundle
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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

  // 1. Инициализация Hive
  await Hive.initFlutter();

  // Регистрация адаптеров моделей
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
  Hive.registerAdapter(OverlayTypeAdapter());        // typeId: 12
  Hive.registerAdapter(LiveMotionAdapter());         // typeId: 13

  // 2. Проверка первого запуска и создание демо-проекта
  final prefs = await SharedPreferences.getInstance();
  final isFirstLaunch = prefs.getBool('isFirstLaunch') ?? true;

  if (isFirstLaunch) {
    print('🚀 Первый запуск! Создаем демо-проект...');
    try {
      await _createDemoProject();
      await prefs.setBool('isFirstLaunch', false);
      print('✅ Демо-проект успешно создан!');
    } catch (e) {
      print('⚠️ Ошибка создания демо-проекта (не критично): $e');
    }
  }

  // 3. Инициализация репозитория и хранилища
  final projectRepo = ProjectRepository();
  await projectRepo.init();

  final mediaStorage = MediaStorageService();
  await mediaStorage.init();

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

// ==========================================
// Создание демо-проекта из assets
// ==========================================
Future<void> _createDemoProject() async {
  final mediaStorage = MediaStorageService();
  await mediaStorage.init();

  final projectRepo = ProjectRepository();
  await projectRepo.init();

  final demoImageNames = [
    'demo_1.jpg', 'demo_2.jpg', 'demo_3.jpg', 
    'demo_4.jpg', 'demo_5.jpg', 'demo_6.jpg'
  ];
  
  final photoLayers = <PhotoLayer>[];

  for (int i = 0; i < demoImageNames.length; i++) {
    final assetName = 'assets/demo/${demoImageNames[i]}';
    
    try {
      // Читаем байты из assets
      final byteData = await rootBundle.load(assetName);
      final bytes = byteData.buffer.asUint8List();

      // Сохраняем во временный файл
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/demo_temp_$i.jpg');
      await tempFile.writeAsBytes(bytes);

      // Импортируем в локальное хранилище приложения
      final localPath = await mediaStorage.importPhoto(tempFile.path);

      // Создаем PhotoLayer с разнообразными эффектами для демонстрации
      photoLayers.add(PhotoLayer(
        imagePath: localPath,
        durationMilliseconds: 2000 + (i * 500), // 2.0с, 2.5с, 3.0с и т.д.
        transition: i == 0 ? TransitionType.none : TransitionType.fade,
        filter: i % 2 == 0 ? FilterType.none : FilterType.vintage,
        liveMotion: i % 2 == 0 ? LiveMotion.zoomIn : LiveMotion.panRight,
        entranceAnimation: EntranceAnimation.fadeIn,
        entranceDurationMs: 500,
      ));

      // Удаляем временный файл
      if (tempFile.existsSync()) tempFile.deleteSync();
    } catch (e) {
      print('⚠️ Не удалось загрузить демо-фото $assetName: $e');
    }
  }

  // Добавляем встроенную музыку
  final bundledMusic = BundledMusicService(mediaStorage);
  await bundledMusic.initialize();
  
  // Берем первый доступный трек или трек для стиля "family"
  final musicFile = bundledMusic.pickForStyle('family') ?? 
                    (await mediaStorage.listMusic()).firstOrNull;

  AudioTrack? audioTrack;
  if (musicFile != null) {
    audioTrack = AudioTrack(
      filePath: musicFile.path,
      title: MediaStorageService.displayName(musicFile),
      isFromInternet: false,
    );
  }

  // Создаем финальный проект
  final demoProject = VideoProject(
    id: const Uuid().v4(),
    name: '🔥 Тестовый проект (не удалять)',
    photos: photoLayers,
        texts: [
      TextLayer(
        text: 'Твоё Видео',
        startTimeMilliseconds: 0,
        endTimeMilliseconds: 2500,
        animation: AnimationType.fadeIn,
        fontSize: 32,
      ),
      TextLayer(
        text: 'Создавай клипы за минуты',
        startTimeMilliseconds: 2500,
        endTimeMilliseconds: 5500,
        animation: AnimationType.slideUp,
        fontSize: 24,
      ),
    ],
    audioTrack: audioTrack,
    formatId: 0, // 9:16 по умолчанию
    overlayType: OverlayType.film, // Демонстрация оверлеев!
    overlayIntensity: 0.5,
    cinematicIntensity: 0.3,
  );

  await projectRepo.saveProject(demoProject);
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