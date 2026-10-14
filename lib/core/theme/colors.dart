import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF048B2A);       // 🟢 Зелёный (Export, Record, Active)
  static const Color primaryDark = Color(0xFF036B20);
  static const Color primaryLight = Color(0xFF0AB840);

  static const Color aiAccent = Color(0xFFD946EF);      // 🟣 Фиолетовый только для AI
  static const Color aiAccentLight = Color(0xFFE879F9);

  static const Color background = Color(0xFF040505);    // Почти чёрный фон
  static const Color surface = Color(0xFF121518);       // Карточки
  static const Color surfaceLight = Color(0xFF1E2329);  // Активные элементы

  static const Color textPrimary = Color(0xFFC6CFD1);   // Основной текст
  static const Color textSecondary = Color(0xFF9AA5B1); 
  static const Color textMuted = Color(0xFF6B7880);     

  static const Color success = Color(0xFF048B2A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  static const Color border = Color(0xFF2A3238);
  static const Color divider = Color(0xFF1E2329);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient aiGradient = LinearGradient(
    colors: [aiAccent, Color(0xFFA21CAF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}