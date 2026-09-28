import '../../data/models/photo_layer.dart';
import '../../data/models/template.dart';

/// Встроенные шаблоны (MVP: 3 штуки по паспорту проекта)
class DefaultTemplates {
  static final List<Template> all = [
    Template(
      id: 'dynamic',
      name: 'Динамика',
      category: 'Динамичные',
      photoDurationMilliseconds: 1500,
      defaultTransition: TransitionType.slideLeft,
    ),
    Template(
      id: 'romantic',
      name: 'Романтика',
      category: 'Романтичные',
      photoDurationMilliseconds: 3000,
      defaultTransition: TransitionType.fade,
    ),
    Template(
      id: 'minimal',
      name: 'Минимализм',
      category: 'Минимализм',
      photoDurationMilliseconds: 2500,
      defaultTransition: TransitionType.none,
    ),
  ];

  /// Категории для фильтра (горизонтальный скролл)
  static const List<String> categories = [
    'Все',
    'Динамичные',
    'Романтичные',
    'Минимализм',
  ];

  /// Фильтрация шаблонов по категории
  static List<Template> byCategory(String category) {
    if (category == 'Все') return all;
    return all.where((t) => t.category == category).toList();
  }

  /// Эмодзи-превью по категории (пока без GIF-ассетов)
  static String categoryEmoji(String category) {
    switch (category) {
      case 'Динамичные':
        return '⚡';
      case 'Романтичные':
        return '💜';
      case 'Минимализм':
        return '◻️';
      default:
        return '✨';
    }
  }
}