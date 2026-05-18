import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF00FFD1);
  static const Color secondary = Color(0xFFFF6B35);
  static const Color background = Color(0xFF0A0E17);
  static const Color surface = Color(0xFF1A1F2E);
  static const Color error = Color(0xFFFF0044);
  static const Color success = Color(0xFF00FF88);
  static const Color warning = Color(0xFFFFAA00);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primary,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
        error: error,
      ),
      fontFamily: 'Rajdhani',
      textTheme: const TextTheme(
        displayLarge: TextStyle(
            fontFamily: 'Orbitron',
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: primary),
        displayMedium: TextStyle(
            fontFamily: 'Orbitron', fontSize: 24, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(fontSize: 16),
        bodyMedium: TextStyle(fontSize: 14),
      ),
      iconTheme: const IconThemeData(
        color: Color(0xFFE8FFF9),
        size: 26,
      ),
      primaryIconTheme: const IconThemeData(
        color: primary,
        size: 26,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Color(0xFFE8FFF9),
        iconTheme: IconThemeData(
          color: Color(0xFFE8FFF9),
          size: 26,
        ),
        actionsIconTheme: IconThemeData(
          color: Color(0xFFE8FFF9),
          size: 26,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: const Color(0xFFE8FFF9),
          iconSize: 26,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: Color(0xFFE8FFF9),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _HudPageTransitionsBuilder(),
          TargetPlatform.iOS: _HudPageTransitionsBuilder(),
          TargetPlatform.macOS: _HudPageTransitionsBuilder(),
          TargetPlatform.linux: _HudPageTransitionsBuilder(),
          TargetPlatform.windows: _HudPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: primary.withValues(alpha: 0.3)),
        ),
      ),
    );
  }
}

class _HudPageTransitionsBuilder extends PageTransitionsBuilder {
  const _HudPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final fade = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(fade);
    final scale = Tween<double>(
      begin: 0.992,
      end: 1,
    ).animate(fade);

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: ScaleTransition(
          scale: scale,
          child: child,
        ),
      ),
    );
  }
}
