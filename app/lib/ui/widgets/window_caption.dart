import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme.dart';

/// Windows 隐藏了系统标题栏（Big Sur 风格，侧边栏铺满）：窗口按钮和拖动区域由 App 自己画。
/// macOS / Linux 保留系统标题栏（没有 Mac 真机验证，不冒红绿灯和返回按钮重叠的风险）。
bool debugWindowsChrome = false; // 测试 / 截图时在 Linux 上也画出 Windows 的窗口按钮
bool get useWindowsChrome => Platform.isWindows || debugWindowsChrome;

const kWindowCaptionHeight = 34.0;

/// 页面顶栏（AppBar）的可拖动背景：AppBar 里的空白处可以拖动窗口
Widget? get windowDragArea => useWindowsChrome ? const DragToMoveArea(child: SizedBox.expand()) : null;

/// Windows 标准的窗口按钮（最小化 / 最大化或还原 / 关闭），放在右上角；关闭悬停变红
class WindowCaption extends StatefulWidget {
  const WindowCaption({super.key});
  @override
  State<WindowCaption> createState() => _WindowCaptionState();
}

class _WindowCaptionState extends State<WindowCaption> with WindowListener {
  bool _max = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) => mounted ? setState(() => _max = v) : null).catchError((_) {});
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _max = true);
  @override
  void onWindowUnmaximize() => setState(() => _max = false);

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _CaptionButton(icon: Icons.remove, tooltip: zh ? '最小化' : 'Minimize', onTap: () => windowManager.minimize()),
      _CaptionButton(
        icon: _max ? Icons.filter_none : Icons.crop_square,
        iconSize: _max ? 12 : 14,
        tooltip: _max ? (zh ? '还原' : 'Restore') : (zh ? '最大化' : 'Maximize'),
        onTap: () async => await windowManager.isMaximized() ? windowManager.unmaximize() : windowManager.maximize(),
      ),
      _CaptionButton(icon: Icons.close, tooltip: zh ? '关闭' : 'Close', close: true, onTap: () => windowManager.close()),
    ]);
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({required this.icon, required this.tooltip, required this.onTap, this.close = false, this.iconSize = 15});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool close;
  final double iconSize;
  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final bg = !_hover ? Colors.transparent : (widget.close ? const Color(0xFFC42B1C) : KColors.hover);
    // 不用 Tooltip：这组按钮叠在导航层外面（所有页面之上），那里没有 Overlay，Tooltip 会报错
    return Semantics(
        button: true,
        label: widget.tooltip,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              width: 46,
              height: kWindowCaptionHeight,
              color: bg,
              alignment: Alignment.center,
              child: Icon(widget.icon,
                  size: widget.iconSize, color: _hover && widget.close ? Colors.white : KColors.ink.withValues(alpha: 0.8)),
            ),
          ),
        ),
    );
  }
}

