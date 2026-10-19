import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 滚动方向迟滞锁存：上滑累计 >16px 点亮、下滑累计 <-16px 熄灭，中间回差防抖。
class ScrollLatch {
  ScrollLatch({this.threshold = 16});

  final double threshold;
  double _ref = 0;
  bool lit = false;

  void update(double px, void Function(bool) on) {
    final d = px - _ref;
    if (!lit && d > threshold) {
      lit = true;
      _ref = px;
      on(true);
    } else if (lit && d < -threshold) {
      lit = false;
      _ref = px;
      on(false);
    }
  }
}

/// 雾面按钮 —— 按字节码真值重建：
/// ① 结构 = 开关式系统模糊(toq)：ClipOval 严格裁轮廓 + BackdropFilter + 底色隐身。
/// ② 混色 = ColorBlendToken.l 手机档三层【字节码】：
///    层1 #1A000000 + plusDarker（CI 3.47.4 无 plusDarker，按预案降级 darken）
///    层2 #996C6C6C + luminosity
///    层3 #99060606 + softLight
///    各层 alpha 随亮暗 v 爬升（对应 k(boolean) 的 0→1 口径）。
/// ③ 阴影 = ShadowToken.f7l8【字节码】：色 #59000000、横移0、下坠2px、扩散64px。
/// ④ 辉光 4→12dp、Bloom 描边亮0.45/暗0.15、亮暗弹簧 400/26。
/// ⑤ 图标恒白 + 微投影（评审结论：图标要亮；暗态玻璃 alpha 归零时
///    白图标会浮在浅底上“没亮”，补 8% 常驻黑底托住圆盘轮廓）。
class FogButton extends StatefulWidget {
  const FogButton({
    super.key,
    required this.litListenable,
    this.onTap,
    this.size = 58,
    this.icon = Icons.arrow_upward,
  });

  final ValueListenable<bool> litListenable;
  final VoidCallback? onTap;
  final double size;
  final IconData icon;

  @override
  State<FogButton> createState() => _FogButtonState();
}

class _FogButtonState extends State<FogButton>
    with SingleTickerProviderStateMixin {
  static const _spring =
      SpringDescription(mass: 1, stiffness: 400, damping: 26);

  late final AnimationController _c = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    widget.litListenable.addListener(_sync);
  }

  void _sync() {
    _c.animateWith(SpringSimulation(
      _spring,
      _c.value,
      widget.litListenable.value ? 1.0 : 0.0,
      _c.velocity,
    ));
  }

  @override
  void dispose() {
    widget.litListenable.removeListener(_sync);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final double v = _c.value.clamp(0.0, 1.0).toDouble();
          return SizedBox(
            width: s + 40,
            height: s + 40,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // ① 羽化辉光：单侧 4 → 12dp，白色平涂无方向
                Container(
                  width: s + 8 + 16 * v,
                  height: s + 8 + 16 * v,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      radius: 0.5 + 0.12 * v,
                      colors: [
                        Colors.white.withOpacity(0.30 * v),
                        Colors.white.withOpacity(0.12 * v),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                // ② 阴影：ShadowToken.f7l8 真值直译（px 按 dpr 换 dp）
                Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x59000000),
                        offset: Offset(0, 2 / dpr),
                        blurRadius: 64 / dpr,
                      ),
                    ],
                  ),
                ),
                // ③ 雾面本体：模糊 + 三层混色 + 图标 + Bloom
                ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: SizedBox(
                      width: s,
                      height: s,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // ⑤ 常驻 8% 黑底：暗态（三层 alpha=0）也有圆盘轮廓
                          Positioned.fill(
                            child: ColoredBox(color: Color(0x14000000)),
                          ),
                          Positioned.fill(
                            child: CustomPaint(painter: _MixLayersPainter(v)),
                          ),
                          // 图标恒白 + 微投影：亮态压中灰玻璃、暗态压浅底都亮
                          Icon(
                            widget.icon,
                            size: 26,
                            color: Colors.white,
                            shadows: const [
                              Shadow(
                                color: Color(0x59000000),
                                blurRadius: 8,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          Positioned.fill(
                            child:
                                CustomPaint(painter: _BloomStrokePainter(v)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// ColorBlendToken.l 三层混色（alpha 随 v 爬升）。
/// 绘制发生在 BackdropFilter 之后的同一帧缓冲上，blendMode 与模糊后的背景相混。
class _MixLayersPainter extends CustomPainter {
  _MixLayersPainter(this.v);

  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    if (v <= 0.01) return;
    final rect = Offset.zero & size;

    // 层1 #1A000000 × darken（plusDarker 预案降级）
    canvas.drawRect(
      rect,
      Paint()
        ..color = Color.fromARGB((0x1A * v).round(), 0, 0, 0)
        ..blendMode = BlendMode.darken,
    );
    // 层2 #996C6C6C × luminosity
    canvas.drawRect(
      rect,
      Paint()
        ..color = Color.fromARGB((0x99 * v).round(), 0x6C, 0x6C, 0x6C)
        ..blendMode = BlendMode.luminosity,
    );
    // 层3 #99060606 × softLight
    canvas.drawRect(
      rect,
      Paint()
        ..color = Color.fromARGB((0x99 * v).round(), 0x06, 0x06, 0x06)
        ..blendMode = BlendMode.softLight,
    );
  }

  @override
  bool shouldRepaint(_MixLayersPainter old) => old.v != v;
}

/// Bloom 环形描边：亮态 0.45 / 暗态 0.15，光圈随 v 加宽。
/// 暗态也画（0.15 起），保证熄灯时圆盘边缘可读。
class _BloomStrokePainter extends CustomPainter {
  _BloomStrokePainter(this.v);

  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    if (v > 0.02) {
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withOpacity(0.35 * v)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + 3 * v);
      canvas.drawCircle(c, r - 1, glow);
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withOpacity(0.15 + 0.30 * v); // 0.15 → 0.45
    canvas.drawCircle(c, r - 1.4, line);
  }

  @override
  bool shouldRepaint(_BloomStrokePainter old) => old.v != v;
}
