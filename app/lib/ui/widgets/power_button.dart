import 'package:flutter/material.dart';

import '../../core/core_backend.dart';
import '../theme.dart';

/// 中间的大电源按钮：未连接=奶白色；连接中=旋转渐变环；已连接=紫粉渐变发光
class PowerButton extends StatefulWidget {
  const PowerButton({super.key, required this.status, required this.onTap, this.size = 150});
  final CoreStatus status;
  final VoidCallback onTap;
  final double size;

  @override
  State<PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<PowerButton> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didUpdateWidget(covariant PowerButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    final busy = widget.status == CoreStatus.starting || widget.status == CoreStatus.stopping;
    if (busy && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!busy && _spin.isAnimating) {
      _spin.stop();
    }
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
    final busy = widget.status == CoreStatus.starting || widget.status == CoreStatus.stopping;
    return GestureDetector(
      onTap: busy ? null : widget.onTap,
      child: MouseRegion(
        cursor: busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: SizedBox(
          width: s + 40,
          height: s + 40,
          child: Stack(alignment: Alignment.center, children: [
            // 外圈光晕
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: s + 36,
              height: s + 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: on
                        ? KColors.lavender.withValues(alpha: 0.45)
                        : Colors.black.withValues(alpha: 0.06),
                    blurRadius: on ? 46 : 26,
                    spreadRadius: on ? 4 : 0,
                  ),
                ],
              ),
            ),
            if (busy)
              RotationTransition(
                turns: _spin,
                child: Container(
                  width: s + 14,
                  height: s + 14,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(colors: [
                      Color(0x00EBA9BC),
                      KColors.sakura,
                      KColors.lavender,
                    ]),
                  ),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? null : KColors.surface,
                gradient: on ? KColors.connectedGradient : null,
                border: Border.all(color: on ? Colors.white54 : KColors.border, width: 2),
              ),
              child: Icon(
                Icons.power_settings_new_rounded,
                size: s * 0.42,
                color: on ? Colors.white : (busy ? KColors.lavender : KColors.faint),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
