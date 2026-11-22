import 'package:flutter/material.dart';

/// 设计语言（1.1.8，Big Sur 风格）：全高侧边栏 + 浅灰底白卡片 + 柔和阴影 + 紫色渐变强调；设置里可选深色；1px 细边框、小圆角、紧凑字号、单色图标，几乎不用阴影；
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
    required this.gradient,
    required this.sidebarGradient,
    required this.card,
    required this.bgGradient,
  });
  final bool dark;
  final Color bg, sidebar, surface, field, hover, border, ink, onInk, sub, faint;
  final Color accent, accentSoft, ok, okSoft, warn, warnSoft, danger, dangerSoft;

  /// 强调渐变（紫 → 蓝紫）：只用在连接按钮、侧边栏选中项、主按钮等少数地方
  final List<Color> gradient;

  /// 侧边栏的淡淡渐变（模拟 Big Sur 的磨砂侧边栏）
  final List<Color> sidebarGradient;

  /// 卡片：半透明白（磨砂），透出底下的渐变
  final Color card;

  /// 内容区底色：左上淡粉 → 中间浅灰 → 右上淡蓝
  final List<Color> bgGradient;

  /// 浅色（默认，1.1.8 Big Sur 风格，参考用户给的 Mac 截图）：
  /// 粉色磨砂侧边栏 + 很淡的粉 / 蓝渐变底 + 半透明白卡片；强调色蓝紫，连接按钮蓝 → 紫渐变
  static const light = KPalette(
    dark: false,
    bg: Color(0xFFF1EEF0),
    sidebar: Color(0xFFF0D9DF),
    surface: Color(0xFFFFFFFF),
    card: Color(0xD9FFFFFF),
    field: Color(0x14000000),
    hover: Color(0x12000000),
    border: Color(0x14000000),
    ink: Color(0xFF1D1D1F),
    onInk: Color(0xFFFFFFFF),
    sub: Color(0xFF6E6E73),
    faint: Color(0xFF9A98A0),
    accent: Color(0xFF5B6CF2),
    accentSoft: Color(0xFFE8EBFE),
    ok: Color(0xFF1F9D55),
    okSoft: Color(0xFFE2F4E8),
    warn: Color(0xFFB86E00),
    warnSoft: Color(0xFFFFF1DA),
    danger: Color(0xFFDC3545),
    dangerSoft: Color(0xFFFDE8EA),
    gradient: [Color(0xFF6A8DFA), Color(0xFF5B6CF2), Color(0xFF7B5AEE)],
    sidebarGradient: [Color(0xFFF3DCE2), Color(0xFFEBD2DA)],
    bgGradient: [Color(0xFFF2E6EA), Color(0xFFF1EFF0), Color(0xFFDFE8F0)],
  );

  static const darkTheme = KPalette(
    dark: true,
    bg: Color(0xFF1C1B21),
    sidebar: Color(0xFF2B2229),
    surface: Color(0xFF2A2A2F),
    card: Color(0x14FFFFFF),
    field: Color(0x1FFFFFFF),
    hover: Color(0x1AFFFFFF),
    border: Color(0x1FFFFFFF),
    ink: Color(0xFFF5F5F7),
    onInk: Color(0xFF1C1C1E),
    sub: Color(0xFFA6A4AD),
    faint: Color(0xFF7A7882),
    accent: Color(0xFF8394FF),
    accentSoft: Color(0xFF262B4A),
    ok: Color(0xFF4ADE80),
    okSoft: Color(0xFF16291D),
    warn: Color(0xFFFBBF24),
    warnSoft: Color(0xFF3A2C12),
    danger: Color(0xFFFF6B6B),
    dangerSoft: Color(0xFF3A1A1C),
    gradient: [Color(0xFF7C9CFF), Color(0xFF6977F5), Color(0xFF8A68F2)],
    sidebarGradient: [Color(0xFF33252F), Color(0xFF281F28)],
    bgGradient: [Color(0xFF231C24), Color(0xFF1C1B21), Color(0xFF18202B)],
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

  static LinearGradient get gradient =>
      LinearGradient(colors: p.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight);
  static Color get card => p.card;
  static LinearGradient get bgGradient =>
      LinearGradient(colors: p.bgGradient, begin: Alignment.topLeft, end: Alignment.topRight, stops: const [0, 0.5, 1]);
  static LinearGradient get sidebarGradient =>
      LinearGradient(colors: p.sidebarGradient, begin: Alignment.topCenter, end: Alignment.bottomCenter);

  /// 卡片的柔和阴影（深色模式靠边框区分，不用阴影）
  static List<BoxShadow> get cardShadow => p.dark
      ? const []
      : const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 3, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x08000000), blurRadius: 14, offset: Offset(0, 4)),
        ];

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
  static const radius = 9.0;
  static const radiusLg = 12.0;
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
        backgroundColor: KColors.accent,
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
          (s) => s.contains(WidgetState.selected) ? KColors.accent : KColors.hover),
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
