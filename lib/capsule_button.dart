import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

// 小米磨砂玻璃胶囊按钮（搜索位）——材质回真值（06:43 评审
// “按钮和胶囊的材质跟主题还是有差距”，SPECS §六【资源】）：
// - 搜索底 = **#0A000000**（真值 4% 黑薄纱压在真模糊上，弃白底 0x8C）；
// - 搜索图标 = **#4D000000**（真值 30% 黑，弃 0x8A）；
// - 搜索词字号 = **17sp**（真值，弃 h*0.36）；
// - 真磨砂：BackdropFilter 背景模糊 18 不变；
// - 内描边删除：01:07 已把高亮描边提到外层 Stack 覆盖层
//   （0.15+0.70×接近度），内圈再画一圈就是双圈脏边；
// - 黑投影 0x14 已删（2026-10-20 21:30 评审“阴影要去掉”）；
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
          // 材质 = 真值薄纱底（#0A000000）+ 真模糊 18；玻璃边缘交给
          // 外层接近度覆盖描边，这里不再画内圈（避免双圈）。
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
                  color: const Color(0x0A000000), // 真值搜索底 #0a000000
                  borderRadius: BorderRadius.circular(h / 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(
                        widget.icon,
                        size: h * 0.45,
                        color: const Color(0x4D000000), // 真值搜索图标
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: widget.dense ? h * 0.36 : 17.0, // 真值 17sp
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
    );
  }
}
