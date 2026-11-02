import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../app_config.dart';
import '../theme.dart';
import '../util.dart';

/// Windows 上隐藏系统标题栏，用自己画的标题栏（和 Codex 桌面端一样）。
/// 测试时可以强制打开。
bool forceCustomTitleBar = false;
bool get useCustomTitleBar => Platform.isWindows || forceCustomTitleBar;
double get kTitleBarHeight => useCustomTitleBar ? 38 : 0;

/// 主界面打开时为 true：标题栏左侧画成侧边栏颜色，和侧边栏连成一体
final shellActive = ValueNotifier<bool>(false);

/// 侧边栏宽度（标题栏和主界面共用）
const kSidebarWidth = 232.0;
const kWideBreakpoint = 720.0;

class WindowBar extends StatelessWidget {
  const WindowBar({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;
    return ValueListenableBuilder<bool>(
      valueListenable: shellActive,
      builder: (context, shell, _) {
        final split = shell && wide;
        // 标题栏在页面框架之外，需要自己提供 Material（文字样式 / 字体）
        return Material(
          type: MaterialType.transparency,
          textStyle: const TextStyle(fontFamily: kFont, color: KColors.ink),
          child: SizedBox(
          height: kTitleBarHeight,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: split ? kSidebarWidth : null,
              decoration: BoxDecoration(
                color: split ? KColors.sidebar : KColors.bg,
                border: split ? const Border(right: BorderSide(color: KColors.border)) : null,
              ),
              padding: const EdgeInsets.only(left: 14, right: 12),
              child: const _DragArea(
                child: Row(children: [
                  KLogo(size: 18),
                  SizedBox(width: 8),
                  Text(AppConfig.appName,
                      style: TextStyle(fontFamily: kFont, fontSize: 12.5, fontWeight: FontWeight.w600, color: KColors.ink)),
                ]),
              ),
            ),
            const Expanded(child: ColoredBox(color: KColors.bg, child: _DragArea(child: SizedBox.expand()))),
            const ColoredBox(color: KColors.bg, child: _WindowButtons()),
          ]),
          ),
        );
      },
    );
  }
}

class _DragArea extends StatelessWidget {
  const _DragArea({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => windowManager.startDragging(),
        onDoubleTap: () async =>
            await windowManager.isMaximized() ? windowManager.unmaximize() : windowManager.maximize(),
        child: child,
      );
}

class _WindowButtons extends StatefulWidget {
  const _WindowButtons();
  @override
  State<_WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<_WindowButtons> with WindowListener {
  bool _max = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      windowManager.addListener(this);
      windowManager.isMaximized().then((v) => mounted ? setState(() => _max = v) : null);
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _max = true);
  @override
  void onWindowUnmaximize() => setState(() => _max = false);

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Row(children: [
      _CaptionButton(icon: Icons.remove_rounded, tooltip: t.minimize, onTap: () => windowManager.minimize()),
      _CaptionButton(
        icon: _max ? Icons.filter_none_rounded : Icons.crop_square_rounded,
        iconSize: _max ? 12 : 14,
        tooltip: t.maximize,
        onTap: () => _max ? windowManager.unmaximize() : windowManager.maximize(),
      ),
      // 关闭 = 隐藏到托盘（VPN 继续工作），真正退出在托盘菜单里
      _CaptionButton(icon: Icons.close_rounded, tooltip: t.close, danger: true, onTap: () => windowManager.close()),
    ]);
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({required this.icon, required this.tooltip, required this.onTap, this.danger = false, this.iconSize = 16});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;
  final double iconSize;
  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final bg = !_hover ? Colors.transparent : (widget.danger ? const Color(0xFFE81123) : KColors.hover);
    final fg = _hover && widget.danger ? Colors.white : KColors.sub;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: kTitleBarHeight,
          color: bg,
          child: Icon(widget.icon, size: widget.iconSize, color: fg),
        ),
      ),
    );
  }
}
