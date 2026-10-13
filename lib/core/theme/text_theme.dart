import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppTextTheme {
  static TextTheme get light {
    return TextTheme(
      displayLarge: GoogleFonts.unbounded(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: AppColors.textPrimary),
      displayMedium: GoogleFonts.unbounded(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
      headlineLarge: GoogleFonts.unbounded(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      headlineMedium: GoogleFonts.unbounded(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      titleLarge: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      titleMedium: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      bodyLarge: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.textPrimary),
      bodyMedium: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
      labelLarge: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: AppColors.textPrimary),
      labelSmall: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted),
    );
  }
}