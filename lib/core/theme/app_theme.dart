import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/constants.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    final baseTextTheme = ThemeData.dark().textTheme;
    final interTextTheme = GoogleFonts.interTextTheme(baseTextTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      textTheme: interTextTheme,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.surface,
        primary: AppColors.accent,
        secondary: AppColors.accentDim,
        onSurface: AppColors.textPrimary,
        onPrimary: AppColors.background,
        error: AppColors.error,
        onError: Colors.white,
        outline: AppColors.border,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          letterSpacing: -0.2,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.background,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLG),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.spacingLG,
          vertical: AppDimens.spacingMD,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: GoogleFonts.inter(
          fontSize: 13,
          color: AppColors.textMuted,
        ),
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.background,
          minimumSize: const Size(double.infinity, AppDimens.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusMD),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppDimens.radiusXXL),
          ),
        ),
        elevation: 0,
      ),
      iconTheme: const IconThemeData(
        color: AppColors.textSecondary,
        size: AppDimens.iconSizeMD,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: GoogleFonts.inter(
          fontSize: 13,
          color: AppColors.textPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
