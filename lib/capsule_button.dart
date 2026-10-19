import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 胶囊按钮：stadium 形（半径恒为高的一半，对应 buttonCapsuleRadius 体系）
/// + 果冻按压（对应 FolmeHover）。按压弹簧与全 App 统一 400 / 26。
class CapsuleButton extends StatefulWidget {
  const CapsuleButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
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
    // 禁用态（onTap == null）不播按压缩放，也不进按钮语义。
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
            height: h,
            padding: EdgeInsets.symmetric(
              horizontal: widget.dense ? 12.0 : 16.0,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xF2FFFFFF), Color(0xC8FFFFFF)],
              ),
              borderRadius: BorderRadius.circular(h / 2), // 胶囊
              border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
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
    );
  }
}
