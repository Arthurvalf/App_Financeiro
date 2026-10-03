import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Paleta: fundo claro e quente, tinta quase preta, destaque verde-limão.
class C {
  static const bg = Color(0xFFF5F5F0);
  static const surface = Colors.white;
  static const ink = Color(0xFF111111);
  static const muted = Color(0xFF6B6B66);
  static const line = Color(0xFFE6E6DF);
  static const lime = Color(0xFFD4F84B);
  static const limeDark = Color(0xFF3F4F00);
  static const green = Color(0xFF15803D);
  static const red = Color(0xFFDC2626);
  static const amber = Color(0xFFB45309);
  static const soft = Color(0xFFEDEDE6);
}

final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
String brl(double v) => _brl.format(v);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: C.ink, brightness: Brightness.light).copyWith(
    primary: C.ink,
    onPrimary: Colors.white,
    secondary: C.lime,
    onSecondary: C.ink,
    surface: C.surface,
    onSurface: C.ink,
    error: C.red,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: C.bg);
  final text = GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: C.ink, displayColor: C.ink);

  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: c, width: w),
      );

  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: C.bg,
      foregroundColor: C.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: border(C.line),
      enabledBorder: border(C.line),
      focusedBorder: border(C.ink, 1.5),
      errorBorder: border(C.red),
      labelStyle: const TextStyle(color: C.muted),
      hintStyle: const TextStyle(color: C.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 54),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.ink,
        minimumSize: const Size(64, 50),
        shape: const StadiumBorder(),
        side: const BorderSide(color: C.line),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: C.ink, textStyle: const TextStyle(fontWeight: FontWeight.w600)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: C.lime,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: const DividerThemeData(color: C.line, thickness: 1, space: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
  );
}
