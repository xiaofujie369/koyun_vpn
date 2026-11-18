import 'package:flutter/material.dart';

/// 设计语言：默认 1.1.6 的奶白色主题，设置里可选深色；1px 细边框、小圆角、紧凑字号、单色图标，几乎不用阴影；
/// 唯一的彩色是强调色（Logo 的紫色）和状态色。
///
/// 颜色是“当前主题”的取值，切换主题时由 [ThemeController] 换一套并重建界面，
/// 所以这些不是 const，用到它们的地方不能写 const。
class KPalette {
  const KPalette({
    required this.dark,
    required this.bg,
    required this.sidebar,
    required this.surface,
    required this.field,
    required this.hover,
    required this.border,
    required this.ink,
    required this.onInk,
    required this.sub,
    required this.faint,
    required this.accent,
    required this.accentSoft,
    required this.ok,
    required this.okSoft,
    required this.warn,
    required this.warnSoft,
    required this.danger,
    required this.dangerSoft,
  });
  final bool dark;
  final Color bg, sidebar, surface, field, hover, border, ink, onInk, sub, faint;
  final Color accent, accentSoft, ok, okSoft, warn, warnSoft, danger, dangerSoft;

  /// 1.1.6 的奶白色主题（默认）
  static const light = KPalette(
    dark: false,
    bg: Color(0xFFFAF8F4),
    sidebar: Color(0xFFF3F0EA),
    surface: Color(0xFFFFFFFF),
    field: Color(0xFFF5F3EE),
    hover: Color(0xFFEDEAE3),
    border: Color(0xFFE6E2D9),
    ink: Color(0xFF1F1D1A),
    onInk: Color(0xFFFFFFFF),
    sub: Color(0xFF6F6A61),
    faint: Color(0xFFA59F94),
    accent: Color(0xFF7C6BD6),
    accentSoft: Color(0xFFEFEBFB),
    ok: Color(0xFF2F9E6B),
    okSoft: Color(0xFFE6F4EC),
    warn: Color(0xFFC98A1C),
    warnSoft: Color(0xFFFBF2DF),
    danger: Color(0xFFD1453B),
    dangerSoft: Color(0xFFFBE7E5),
  );

  static const darkTheme = KPalette(
    dark: true,
    bg: Color(0xFF0B0B0D),
    sidebar: Color(0xFF111114),
    surface: Color(0xFF151518),
    field: Color(0xFF1E1E22),
    hover: Color(0xFF2A2A30),
    border: Color(0xFF2A2A30),
    ink: Color(0xFFF4F4F5),
    onInk: Color(0xFF0B0B0D),
    sub: Color(0xFFA1A1AA),
    faint: Color(0xFF7A7A84),
    accent: Color(0xFF8B7BEA),
    accentSoft: Color(0xFF26213F),
    ok: Color(0xFF4ADE80),
    okSoft: Color(0xFF13291C),
    warn: Color(0xFFFBBF24),
    warnSoft: Color(0xFF3A2A10),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0xFF3A1717),
  );
}

class KColors {
  static KPalette p = KPalette.light;

  static bool get isDark => p.dark;
  static Color get bg => p.bg;
  static Color get sidebar => p.sidebar;
  static Color get surface => p.surface;
  static Color get field => p.field;
  static Color get hover => p.hover;
  static Color get border => p.border;
  static Color get ink => p.ink;

  /// 以 [ink] 为底色时的文字颜色（白色主题是白字，黑色主题是黑字）
  static Color get onInk => p.onInk;
  static Color get sub => p.sub;
  static Color get faint => p.faint;
  static Color get accent => p.accent;
  static Color get accentSoft => p.accentSoft;
  static Color get ok => p.ok;
  static Color get okSoft => p.okSoft;
  static Color get warn => p.warn;
  static Color get warnSoft => p.warnSoft;
  static Color get danger => p.danger;
  static Color get dangerSoft => p.dangerSoft;

  // 兼容旧名称
  static Color get lavender => p.accent;
}

/// 主题：跟随系统 / 白色 / 黑色。切换时换调色板并让整个界面重建（保留页面状态）
class ThemeController extends ChangeNotifier {
  ThemeController(this._mode, {this.onSave});
  ThemeMode _mode;
  Brightness _platform = Brightness.light;
  final void Function(ThemeMode)? onSave;

  ThemeMode get mode => _mode;
  bool get dark => _mode == ThemeMode.dark || (_mode == ThemeMode.system && _platform == Brightness.dark);

  void setPlatform(Brightness b) {
    if (b == _platform) return;
    _platform = b;
    _apply();
  }

  void setMode(ThemeMode m) {
    if (m == _mode) return;
    _mode = m;
    onSave?.call(m);
    _apply();
  }

  /// 白色 ↔ 黑色（顶部按钮用）：直接选定，不再跟随系统
  void toggle() => setMode(dark ? ThemeMode.light : ThemeMode.dark);

  void _apply() {
    final p = dark ? KPalette.darkTheme : KPalette.light;
    if (identical(p, KColors.p)) return;
    KColors.p = p;
    notifyListeners();
  }

  /// 首次启动前调用，保证第一帧就是正确的颜色
  void init(Brightness platform) {
    _platform = platform;
    KColors.p = dark ? KPalette.darkTheme : KPalette.light;
  }
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
    brightness: KColors.isDark ? Brightness.dark : Brightness.light,
    useMaterial3: true,
    fontFamily: kFont,
    fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei UI', 'Noto Sans CJK SC', 'Noto Color Emoji', 'Segoe UI Emoji'],
    scaffoldBackgroundColor: KColors.bg,
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    colorScheme: ColorScheme.fromSeed(
      seedColor: KColors.accent,
      brightness: KColors.isDark ? Brightness.dark : Brightness.light,
      onSurface: KColors.ink,
      surface: KColors.surface,
      primary: KColors.ink,
      onPrimary: KColors.onInk,
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
          bodyMedium: TextStyle(fontFamily: kFont, fontSize: KSize.body, height: 1.45, color: KColors.ink),
          bodySmall: TextStyle(fontFamily: kFont, fontSize: KSize.small, color: KColors.sub),
          titleMedium: TextStyle(fontFamily: kFont, fontSize: 14.5, fontWeight: FontWeight.w600, color: KColors.ink),
        ),
    appBarTheme: AppBarTheme(
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
        side: BorderSide(color: KColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KColors.surface,
      isDense: true,
      hintStyle: TextStyle(fontFamily: kFont, color: KColors.faint, fontSize: KSize.body),
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
        foregroundColor: KColors.onInk,
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
        side: BorderSide(color: KColors.border),
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
    listTileTheme: ListTileThemeData(
      dense: true,
      minVerticalPadding: 8,
      contentPadding: EdgeInsets.symmetric(horizontal: 14),
      iconColor: KColors.sub,
      titleTextStyle: TextStyle(fontFamily: kFont, fontSize: KSize.body, color: KColors.ink),
      subtitleTextStyle: TextStyle(fontFamily: kFont, fontSize: KSize.small, color: KColors.faint),
    ),
    dividerTheme: DividerThemeData(color: KColors.border, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: KColors.ink),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: KColors.ink, borderRadius: BorderRadius.circular(6)),
      textStyle: TextStyle(fontFamily: kFont, color: KColors.onInk, fontSize: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: KColors.ink,
      behavior: SnackBarBehavior.floating,
      width: 380,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentTextStyle: TextStyle(fontFamily: kFont, color: KColors.onInk, fontSize: KSize.body),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: KColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KSize.radiusLg)),
      titleTextStyle: TextStyle(fontFamily: kFont, fontSize: 16, fontWeight: FontWeight.w600, color: KColors.ink),
      contentTextStyle: TextStyle(fontFamily: kFont, fontSize: KSize.body, height: 1.5, color: KColors.sub),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: KColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      constraints: BoxConstraints(maxWidth: 560),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: KColors.surface,
      selectedColor: KColors.ink,
      labelStyle: const TextStyle(fontFamily: kFont, fontSize: KSize.small + 0.5),
      secondaryLabelStyle: TextStyle(fontFamily: kFont, fontSize: KSize.small + 0.5, color: KColors.onInk),
      side: BorderSide(color: KColors.border),
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
