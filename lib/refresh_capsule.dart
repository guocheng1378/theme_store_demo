import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 下拉刷新胶囊 —— 按字节码真值重建：
/// ① 触发距离 = miuix_sbl_action_indeterminate_distance = **72dp**【资源】，
///    进度 = clamp(下拉量 ÷ 72, 0, 1)（DefaultTrigger.r8s8 口径）。
/// ② 入场 = DefaultTrigger.mbx 的 Folme 状态机【字节码】：
///    start{α0, y-180} → show{α1, y+25}（第 1 段，参数 120）→ hide{α1, y0}（第 2 段，参数 40）。
///    本实现按 120ms + 40ms 两段解读（参数若为弹簧系数，真机再校）。
/// ③ 退出 = 入场逆放；胶囊色 #D9FFFFFF【资源】。
/// ④ topOffset：胶囊起始 Y（头部方案下传头部高度，从雾面带下缘探出）。
/// ⑤ 两个 AnimationController（_c/_e）→ 必须 TickerProviderStateMixin。
class RefreshCapsule extends StatefulWidget {
  const RefreshCapsule({
    super.key,
    required this.onRefresh,
    required this.child,
    this.topOffset = 8,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final double topOffset;

  @override
  State<RefreshCapsule> createState() => RefreshCapsuleState();
}

class RefreshCapsuleState extends State<RefreshCapsule>
    with TickerProviderStateMixin {
  static const _spring =
      SpringDescription(mass: 1, stiffness: 380, damping: 24);
  static const _triggerDist = 72.0; // 真值 72dp（大字体 83dp）
  static const _enterSeg1 = 0.75; // 120 / (120+40)

  late final AnimationController _c = AnimationController(vsync: this); // 拉伸
  late final AnimationController _e = AnimationController(vsync: this); // 入场
  bool _refreshing = false;
  bool _settling = false;

  @override
  void dispose() {
    _c.dispose();
    _e.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (_refreshing || _settling) return false;
    final px = n.metrics.pixels;
    _c.stop();
    _c.value = px < 0 ? (-px / _triggerDist).clamp(0.0, 1.0).toDouble() : 0.0;
    return false;
  }

  void _release() {
    if (_refreshing || _settling) return;
    if (_c.value >= 1.0) {
      _start();
    } else if (_c.value > 0) {
      _settling = true;
      _c.animateWith(SpringSimulation(_spring, _c.value, 0, _c.velocity));
    }
  }

  Future<void> _start() async {
    setState(() => _refreshing = true);
    _settling = true;
    _c.stop();
    _c.value = 0.0; // 拉伸指示退场，入场序列接管
    _e.value = 0.0;
    // 入场：-180 → +25（120ms）→ 0（40ms）
    _e.animateTo(1, duration: const Duration(milliseconds: 160));
    try {
      await widget.onRefresh();
    } finally {
      if (!mounted) return;
      setState(() => _refreshing = false);
      // 退出：入场逆放
      await _e.animateBack(0, duration: const Duration(milliseconds: 160));
      if (!mounted) return;
      _settling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _settling = false,
            onPointerUp: (_) => _release(),
            child: widget.child,
          ),
        ),
        Positioned(
          top: widget.topOffset,
          left: 0,
          right: 0,
          child: IgnorePointer(child: _view()),
        ),
      ],
    );
  }

  Widget _view() {
    return AnimatedBuilder(
      animation: Listenable.merge([_c, _e]),
      builder: (context, _) {
        final double e = _e.value;
        final double dv = _c.value.clamp(0.0, 1.0).toDouble();
        final bool entry = _refreshing || e > 0;

        // ---------- 入场序列（mbx 真值：-180 → +25 → 0，α 0 → 1） ----------
        if (entry) {
          double dy;
          double alpha;
          if (e <= _enterSeg1) {
            final t = e / _enterSeg1;
            final eased = Curves.easeOutCubic.transform(t);
            dy = -180 + 205 * eased; // -180 → +25
            alpha = t;
          } else {
            final t = (e - _enterSeg1) / (1 - _enterSeg1);
            dy = 25 * (1 - t); // +25 → 0
            alpha = 1;
          }
          return Opacity(
            opacity: alpha.clamp(0.0, 1.0).toDouble(),
            child: Transform.translate(
              offset: Offset(0, dy),
              child: _capsule(34.0, 72.0, showSpinner: _refreshing),
            ),
          );
        }

        // ---------- 拉伸阶段（跟手） ----------
        if (dv < 0.01) return const SizedBox(height: 0);
        final h = 34.0 + 18 * dv;
        final w = 72.0 + 30 * dv;
        return Transform.translate(
          offset: Offset(0, 26 * dv),
          child: _capsule(h, w, showSpinner: false, scale: 1 - 0.25 * dv),
        );
      },
    );
  }

  Widget _capsule(double h, double w,
      {required bool showSpinner, double scale = 1}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(h / 2),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: const Color(0xD9FFFFFF), // 真值 #D9FFFFFF
            borderRadius: BorderRadius.circular(h / 2),
            border: Border.all(color: Colors.white.withOpacity(0.65)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: showSpinner
                ? const CupertinoActivityIndicator(radius: 7)
                : Transform.scale(
                    scale: scale,
                    child: const Icon(
                      Icons.arrow_downward,
                      size: 18,
                      color: Color(0x8A000000),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
