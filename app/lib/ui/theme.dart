import 'package:flutter/material.dart';

/// 设计语言：参考 Codex / Linear 一类工具型产品——
/// 暖白底、1px 细边框、小圆角、紧凑字号、单色图标，几乎不用阴影；
/// 唯一的彩色是"已连接"状态，取自 Logo 的薰衣草紫。
class KColors {
  static const bg = Color(0xFFFAF8F4); // 主背景（奶白）
  static const sidebar = Color(0xFFF3F0EA); // 侧边栏
  static const surface = Color(0xFFFFFFFF); // 卡片
  static const field = Color(0xFFF5F3EE); // 输入框 / 分段控件底
  static const hover = Color(0xFFEDEAE3); // 选中 / 悬停
  static const border = Color(0xFFE6E2D9);
  static const ink = Color(0xFF1F1D1A); // 主文字
  static const sub = Color(0xFF6F6A61); // 次要文字
  static const faint = Color(0xFFA59F94); // 弱提示
  static const accent = Color(0xFF7C6BD6); // 强调：薰衣草紫
  static const accentSoft = Color(0xFFEFEBFB);
  static const ok = Color(0xFF2F9E6B);
  static const okSoft = Color(0xFFE6F4EC);
  static const warn = Color(0xFFC98A1C);
  static const warnSoft = Color(0xFFFBF2DF);
  static const danger = Color(0xFFD1453B);

  // 兼容旧名称
  static const lavender = accent;
}

/// 尺寸规范（紧凑）
class KSize {
  static const radius = 10.0;
  static const radiusLg = 14.0;
  static const control = 38.0; // 按钮 / 输入框高度
  static const body = 13.5;
  static const small = 12.0;
  static const title = 20.0;
}

const kFont = 'HarmonyOS Sans';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: kFont,
    fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei UI', 'Noto Sans CJK SC', 'Noto Color Emoji', 'Segoe UI Emoji'],
    scaffoldBackgroundColor: KColors.bg,
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    colorScheme: ColorScheme.fromSeed(
      seedColor: KColors.accent,
      surface: KColors.surface,
      primary: KColors.ink,
      onPrimary: Colors.white,
      secondary: KColors.accent,
      error: KColors.danger,
    ),
  );
  OutlineInputBorder ob(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(KSize.radius), borderSide: BorderSide(color: c, width: w));
  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: KColors.ink, displayColor: KColors.ink)
        .copyWith(
          bodyMedium: const TextStyle(fontFamily: kFont, fontSize: KSize.body, height: 1.45, color: KColors.ink),
          bodySmall: const TextStyle(fontFamily: kFont, fontSize: KSize.small, color: KColors.sub),
          titleMedium: const TextStyle(fontFamily: kFont, fontSize: 14.5, fontWeight: FontWeight.w600, color: KColors.ink),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: KColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 48,
      foregroundColor: KColors.ink,
      titleTextStyle: TextStyle(fontFamily: kFont, fontSize: 15, fontWeight: FontWeight.w600, color: KColors.ink),
    ),
    cardTheme: CardThemeData(
      color: KColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KSize.radiusLg),
        side: const BorderSide(color: KColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KColors.surface,
      isDense: true,
      hintStyle: const TextStyle(fontFamily: kFont, color: KColors.faint, fontSize: KSize.body),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      prefixIconColor: KColors.faint,
      suffixIconColor: KColors.faint,
      prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 20),
      border: ob(KColors.border),
      enabledBorder: ob(KColors.border),
      focusedBorder: ob(KColors.accent, 1.4),
      errorBorder: ob(KColors.danger),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: KColors.ink,
        foregroundColor: Colors.white,
        disabledBackgroundColor: KColors.hover,
        minimumSize: const Size(64, KSize.control),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KSize.radius)),
        textStyle: const TextStyle(fontFamily: kFont, fontSize: KSize.body, fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: KColors.ink,
        backgroundColor: KColors.surface,
        minimumSize: const Size(64, KSize.control),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        side: const BorderSide(color: KColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KSize.radius)),
        textStyle: const TextStyle(fontFamily: kFont, fontSize: KSize.body, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: KColors.sub,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontFamily: kFont, fontSize: KSize.small + 0.5),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: KColors.sub,
        iconSize: 18,
        minimumSize: const Size(32, 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? KColors.ink : KColors.hover),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      thumbIcon: WidgetStateProperty.all(const Icon(null)),
    ),
    listTileTheme: const ListTileThemeData(
      dense: true,
      minVerticalPadding: 8,
      contentPadding: EdgeInsets.symmetric(horizontal: 14),
      iconColor: KColors.sub,
      titleTextStyle: TextStyle(fontFamily: kFont, fontSize: KSize.body, color: KColors.ink),
      subtitleTextStyle: TextStyle(fontFamily: kFont, fontSize: KSize.small, color: KColors.faint),
    ),
    dividerTheme: const DividerThemeData(color: KColors.border, thickness: 1, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: KColors.ink),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: KColors.ink, borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(fontFamily: kFont, color: Colors.white, fontSize: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: KColors.ink,
      behavior: SnackBarBehavior.floating,
      width: 380,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentTextStyle: const TextStyle(fontFamily: kFont, color: Colors.white, fontSize: KSize.body),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: KColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KSize.radiusLg)),
      titleTextStyle: const TextStyle(fontFamily: kFont, fontSize: 16, fontWeight: FontWeight.w600, color: KColors.ink),
      contentTextStyle: const TextStyle(fontFamily: kFont, fontSize: KSize.body, height: 1.5, color: KColors.sub),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: KColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      constraints: BoxConstraints(maxWidth: 560),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: KColors.surface,
      selectedColor: KColors.ink,
      labelStyle: const TextStyle(fontFamily: kFont, fontSize: KSize.small + 0.5),
      secondaryLabelStyle: const TextStyle(fontFamily: kFont, fontSize: KSize.small + 0.5, color: Colors.white),
      side: const BorderSide(color: KColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      showCheckmark: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 60,
      backgroundColor: KColors.surface,
      indicatorColor: KColors.hover,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontFamily: kFont, fontSize: 11)),
    ),
  );
}
