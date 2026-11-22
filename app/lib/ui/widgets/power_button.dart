import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/core_backend.dart';
import '../theme.dart';

/// 连接按钮：细圆环 + 中心电源图标。
/// 未连接=灰环；连接中=紫色弧线旋转；已连接=紫色实心 + 柔和光晕。
class PowerButton extends StatefulWidget {
  const PowerButton({super.key, required this.status, required this.onTap, this.size = 112});
  final CoreStatus status;
  final VoidCallback onTap;
  final double size;

  @override
  State<PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<PowerButton> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _hover = false;

  bool get _busy => widget.status == CoreStatus.starting || widget.status == CoreStatus.stopping;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PowerButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_busy && !_spin.isAnimating) _spin.repeat();
    if (!_busy && _spin.isAnimating) _spin.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final on = widget.status == CoreStatus.running;
    return MouseRegion(
      cursor: _busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _busy ? null : widget.onTap,
        child: AnimatedScale(
          scale: _hover && !_busy ? 1.03 : 1,
          duration: const Duration(milliseconds: 160),
          child: SizedBox(
            width: s,
            height: s,
            child: Stack(alignment: Alignment.center, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // 已连接：紫 → 蓝紫渐变 + 柔光；未连接：白色圆盘 + 柔和阴影
                  color: on ? null : KColors.card,
                  gradient: on ? KColors.gradient : null,
                  border: on ? null : Border.all(color: KColors.border, width: 0.8),
                  boxShadow: on
                      ? [
                          // 只有柔和的投影，没有光环。阴影比按钮小一圈（spread 为负）、往下偏同样的距离：
                          // 即使模糊没生效也完全藏在按钮后面，不会在下方露出一道月牙形的硬边
                          BoxShadow(
                              color: KColors.p.gradient[1].withValues(alpha: 0.32),
                              blurRadius: 26,
                              spreadRadius: -8,
                              offset: const Offset(0, 8)),
                        ]
                      : [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: KColors.isDark ? 0.28 : 0.08),
                              blurRadius: 22,
                              spreadRadius: -6,
                              offset: const Offset(0, 6)),
                        ],
                ),
              ),
              if (_busy)
                RotationTransition(
                  turns: _spin,
                  child: CustomPaint(size: Size(s - 10, s - 10), painter: _ArcPainter()),
                ),
              Icon(Icons.power_settings_new_rounded,
                  size: s * 0.36,
                  color: on ? Colors.white : (_busy ? KColors.accent : KColors.sub)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = KColors.accent;
    canvas.drawArc(Offset.zero & size, -pi / 2, pi * 0.6, false, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
