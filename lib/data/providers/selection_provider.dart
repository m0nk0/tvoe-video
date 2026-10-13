import 'package:flutter_riverpod/flutter_riverpod.dart';

// ==========================================
// Режим мультивыбора кадров на таймлайне
// ==========================================

/// Активен ли режим выделения
final isSelectionModeProvider = StateProvider<bool>((ref) => false);

/// Множество выбранных индексов кадров
final selectedFramesProvider = StateProvider<Set<int>>((ref) => {});

/// Хелперы управления выделением
class SelectionController {
  final WidgetRef ref;

  SelectionController(this.ref);

  bool get isActive => ref.read(isSelectionModeProvider);

  Set<int> get selected => ref.read(selectedFramesProvider);

  /// Войти в режим выделения с первым выбранным кадром
  void enter(int index) {
    ref.read(isSelectionModeProvider.notifier).state = true;
    ref.read(selectedFramesProvider.notifier).state = {index};
  }

  /// Переключить отметку кадра
  void toggle(int index) {
    final current = Set<int>.from(ref.read(selectedFramesProvider));
    if (current.contains(index)) {
      current.remove(index);
    } else {
      current.add(index);
    }
    ref.read(selectedFramesProvider.notifier).state = current;
  }

  /// Выбрать все кадры проекта
  void selectAll(int totalFrames) {
    ref.read(selectedFramesProvider.notifier).state =
        List.generate(totalFrames, (i) => i).toSet();
  }

  /// Сбросить отметки (остаться в режиме)
  void clear() {
    ref.read(selectedFramesProvider.notifier).state = {};
  }

  /// Выйти из режима выделения
  void exit() {
    ref.read(isSelectionModeProvider.notifier).state = false;
    ref.read(selectedFramesProvider.notifier).state = {};
  }

  /// Целевые индексы для применения эффектов:
  /// если режим активен и есть выбор — список выбранных (отсортированный),
  /// иначе — текущий кадр
  List<int> targetIndices(int currentIndex) {
    if (isActive && selected.isNotEmpty) {
      final list = selected.toList()..sort();
      return list;
    }
    return [currentIndex];
  }
}