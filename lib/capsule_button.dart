import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

// 小米磨砂玻璃胶囊按钮（搜索等输入位）：
// - 真磨砂：BackdropFilter 背景模糊 18 + 奶白玻璃 55% + 白描边 55%；
// - 交互：按下 scale→0.96（80ms easeOut），松手 spring(400/26) 回弹。
class CapsuleButton extends StatefulWidget {
  const CapsuleButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool dense;

  @override
  State<CapsuleButton> createState() => _CapsuleButtonState();
}

class _CapsuleButtonState extends State<CapsuleButton>
    with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 400,
    damping: 26,
  );

  late final AnimationController _p = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 80),
  );

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  void _release() {
    _p.animateWith(SpringSimulation(_spring, _p.value, 1, _p.velocity));
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.dense ? 32.0 : 40.0;
    final enabled = widget.onTap != null;
    return Semantics(
      button: enabled,
      child: GestureDetector(
        onTapDown: enabled
            ? (_) => _p.animateTo(0, curve: Curves.easeOut)
            : null,
        onTapUp: enabled ? (_) => _release() : null,
        onTapCancel: enabled ? _release : null,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _p,
          builder: (context, child) =>
              Transform.scale(scale: 0.96 + 0.04 * _p.value, child: child),
          child: Container(
            // 外层只负责投影（先于 ClipRRect 绘制，不会被裁掉）
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(h / 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(h / 2),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  height: h,
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.dense ? 12.0 : 16.0,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x8CFFFFFF),
                    borderRadius: BorderRadius.circular(h / 2),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(
                          widget.icon,
                          size: h * 0.45,
                          color: const Color(0x8A000000),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: h * 0.36,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xE6000000),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
