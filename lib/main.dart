import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/theme/app_theme.dart';
import 'data/models/video_project.dart';
import 'data/models/photo_layer.dart';
import 'data/models/text_layer.dart';
import 'data/models/template.dart';
import 'data/repositories/project_repository.dart';
import 'features/home/home_screen.dart';

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository();
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  Hive.registerAdapter(VideoProjectAdapter());
  Hive.registerAdapter(PhotoLayerAdapter());
  Hive.registerAdapter(TextLayerAdapter());
  Hive.registerAdapter(TemplateAdapter());
  Hive.registerAdapter(TransitionTypeAdapter());
  Hive.registerAdapter(AnimationTypeAdapter());

  final projectRepo = ProjectRepository();
  await projectRepo.init();

  runApp(
    ProviderScope(
      overrides: [
        projectRepositoryProvider.overrideWithValue(projectRepo),
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