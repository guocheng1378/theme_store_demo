import 'dart:math' as math;
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

/// 雾面按钮 —— 字节码真值 + 评审两轮补强（亮 / 立体）：
/// ① 结构 = 开关式系统模糊(toq)：ClipOval 严格裁轮廓 + BackdropFilter。
/// ② 混色 = ColorBlendToken.l 三层（层1 darken 预案降级 / 层2 luminosity /
///    层3 softLight），alpha 随亮暗 v 爬升。
/// ③ 阴影 = ShadowToken.f7l8 环境阴影（#59000000 / 64px）+ 贴地接触
///    阴影（#40000000 / 10px / 下坠 4px）—— 负立体感。
/// ④ 球面明暗层：盘内上白(0x2E) → 中透 → 下黑(0x33) 纵向渐变，
///    模拟顶光球体——评审结论“不立体”的直接修复。
/// ⑤ 亮化：辉光 0.40（原 0.30）、顶部高光弧白 0.55 渐隐、
///    Bloom 描边亮0.45/暗0.15、箭头白 + 重投影(0x8A/10px)。
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
                // ⑤ 羽化辉光：提亮 0.40 / 0.18，单侧 4 → 12dp
                Container(
                  width: s + 8 + 16 * v,
                  height: s + 8 + 16 * v,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      radius: 0.5 + 0.12 * v,
                      colors: [
                        Colors.white.withOpacity(0.40 * v),
                        Colors.white.withOpacity(0.18 * v),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                // ③ 阴影：环境阴影（真值 64px）+ 贴地接触阴影（立体）
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
                      const BoxShadow(
                        color: Color(0x40000000),
                        offset: Offset(0, 4),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
                // 雾面本体：模糊 + 混色 + 球面 + 图标 + Bloom
                ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: SizedBox(
                      width: s,
                      height: s,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // 常驻黑底：托住圆盘轮廓与箭头对比
                          Positioned.fill(
                            child: ColoredBox(color: Color(0x1F000000)),
                          ),
                          Positioned.fill(
                            child: CustomPaint(painter: _MixLayersPainter(v)),
                          ),
                          // ④ 球面明暗：顶光 → 底部阴影，盘变“球”
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    const Color(0x2EFFFFFF),
                                    Colors.transparent,
                                    const Color(0x33000000),
                                  ],
                                  stops: const [0.0, 0.45, 1.0],
                                ),
                              ),
                            ),
                          ),
                          // 图标恒白 + 重投影：白更锐
                          Icon(
                            widget.icon,
                            size: 26,
                            color: Colors.white,
                            shadows: const [
                              Shadow(
                                color: Color(0x8A000000),
                                blurRadius: 10,
                                offset: Offset(0, 2),
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

/// ColorBlendToken.l 三层混色（alpha 随 v 爬升），与模糊后的背景相混。
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

/// Bloom 三层描边：顶光高光弧（立体感）+ 环形描边亮0.45/暗0.15 + 光圈。
class _BloomStrokePainter extends CustomPainter {
  _BloomStrokePainter(this.v);

  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r - 1.4);

    // ① 顶部高光弧：白 0.55 → 0.18 渐变压在上缘（顶光源）
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = SweepGradient(
        colors: const [
          Colors.white,
          Color(0x55FFFFFF),
          Color(0x00FFFFFF),
          Color(0x00FFFFFF),
          Colors.white,
        ],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
    canvas.drawArc(rect, math.pi, math.pi, false, rim);

    // ② 光圈（v > 0 才加宽）
    if (v > 0.02) {
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withOpacity(0.40 * v)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + 3 * v);
      canvas.drawCircle(c, r - 1, glow);
    }
    // ③ Bloom 环形描边：亮态 0.45 / 暗态 0.15
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withOpacity(0.15 + 0.30 * v);
    canvas.drawCircle(c, r - 1.4, line);
  }

  @override
  bool shouldRepaint(_BloomStrokePainter old) => old.v != v;
}
