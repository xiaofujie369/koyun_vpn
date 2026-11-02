import 'package:flutter/material.dart';

/// 奶白色主题。强调色取自 Logo：薰衣草紫 + 樱花粉。
class KColors {
  static const bg = Color(0xFFF7F3EA); // 奶白底
  static const surface = Color(0xFFFFFCF6); // 卡片
  static const field = Color(0xFFF1ECE2); // 输入框
  static const border = Color(0xFFE9E2D4);
  static const ink = Color(0xFF2F2A26); // 主文字 / 主按钮（暖黑）
  static const sub = Color(0xFF8E8679); // 次要文字
  static const faint = Color(0xFFB9B1A3);
  static const lavender = Color(0xFF9B86D6);
  static const sakura = Color(0xFFEBA9BC);
  static const ok = Color(0xFF4FAE7E);
  static const warn = Color(0xFFDB9A2B);
  static const danger = Color(0xFFD65A55);

  static const connectedGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [lavender, sakura],
  );
}

const kFont = 'HarmonyOS Sans';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: kFont,
    // 日文 / 韩文等 HarmonyOS Sans SC 不含的字形，回退到系统字体
    fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei', 'Noto Sans CJK SC', 'sans-serif'],
    scaffoldBackgroundColor: KColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: KColors.lavender,
      surface: KColors.surface,
      primary: KColors.ink,
      onPrimary: Colors.white,
      secondary: KColors.lavender,
      error: KColors.danger,
      brightness: Brightness.light,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: KColors.ink, displayColor: KColors.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: KColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: KColors.ink,
      titleTextStyle: TextStyle(
          fontFamily: kFont, fontSize: 18, fontWeight: FontWeight.w700, color: KColors.ink),
    ),
    cardTheme: CardThemeData(
      color: KColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: KColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KColors.field,
      hintStyle: const TextStyle(color: KColors.faint, fontSize: 15),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      prefixIconColor: KColors.sub,
      suffixIconColor: KColors.sub,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: KColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: KColors.lavender, width: 1.4)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: KColors.danger)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: KColors.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: kFont, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: KColors.ink,
        minimumSize: const Size.fromHeight(54),
        side: const BorderSide(color: KColors.border, width: 1.4),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: kFont, fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: KColors.sub,
        textStyle: const TextStyle(fontFamily: kFont, fontSize: 14),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : KColors.faint),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? KColors.lavender : KColors.field),
      trackOutlineColor: WidgetStateProperty.all(KColors.border),
    ),
    dividerTheme: const DividerThemeData(color: KColors.border, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: KColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentTextStyle: const TextStyle(fontFamily: kFont, color: Colors.white),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: KColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: KColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
  );
}
