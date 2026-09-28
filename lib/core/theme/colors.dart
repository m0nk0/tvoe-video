import 'package:flutter/material.dart';

class AppColors {
  // Основные цвета
  static const Color primary = Color(0xFFD946EF);       // Неоновый фиолетовый/маджента
  static const Color primaryDark = Color(0xFFA21CAF);   // Тёмный фиолетовый
  static const Color primaryLight = Color(0xFFE879F9);  // Светлый фиолетовый (glow)

  // Фоновые цвета
  static const Color background = Color(0xFF0A0118);    // Глубокий тёмно-фиолетовый
  static const Color surface = Color(0xFF1A0B2E);       // Карточки, панели
  static const Color surfaceLight = Color(0xFF2D1B4E);  // Raised элементы

  // Текстовые цвета
  static const Color textPrimary = Color(0xFFFFFFFF);   // Белый
  static const Color textSecondary = Color(0xFFD8B4FE); // Светло-фиолетовый
  static const Color textMuted = Color(0xFFA78BFA);     // Приглушённый фиолетовый

  // Системные цвета
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Градиенты
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [background, surface],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}