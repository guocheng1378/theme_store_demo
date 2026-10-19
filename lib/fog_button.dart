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

/// 雾面按钮 —— 字节码真值 + 三轮评审补强：
/// ① 结构 = 开关式系统模糊(toq)：ClipOval 裁轮廓 + BackdropFilter。
/// ② 混色 = ColorBlendToken.l 三层（darken / luminosity / softLight），
///    alpha 随亮暗 v 爬升；直接绘 framebuffer（不进 saveLayer）。
/// ③ 球面明暗：上白(0x2E) → 中透 → 下黑(0x33) 顶光源。
/// ④ 边界融合（评审“与界面有界限”）：
///    - 黑底 + 球面层包一层径向渐隐 ShaderMask（80% 内满、100% 透），
///      玻璃到圆周自然融入内容，不再硬边收口；
///    - 去掉整圈 Bloom 环线（那是拿笔画的圈），只留顶部柔化反光弧
///      + 点亮态软辉光圈（蒙版模糊，非实线）。
/// ⑤ 浮起感（评审“没浮起来”）：环境阴影 #59000000/64px + 接触阴影
///    #66000000/14px/下坠6px；白辉光只当氛围，不承担边界。
/// ⑥ 图标恒白 + 重投影(0x8A/10px)。
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
                // 氛围辉光（点亮态）：软，不承担边界
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
                // 浮起感：环境光晕 + 加强接触阴影（下坠 6px）
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
                        color: Color(0x66000000),
                        offset: Offset(0, 6),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                ),
                // 雾面本体
                ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: SizedBox(
                      width: s,
                      height: s,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // 玻璃底 + 球面：径向渐隐收边（80% 内满 → 圆周透），
                          // ShaderMask 只包普通 alpha 层，避开混色 saveLayer 坑
                          Positioned.fill(
                            child: ShaderMask(
                              shaderCallback: (rect) => RadialGradient(
                                radius: 1.0,
                                stops: const [0.0, 0.80, 1.0],
                                colors: [
                                  Colors.white,
                                  Colors.white,
                                  Colors.transparent,
                                ],
                              ).createShader(rect),
                              blendMode: BlendMode.dstIn,
                              child: Stack(
                                children: const [
                                  ColoredBox(color: Color(0x1F000000)),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Color(0x2EFFFFFF),
                                          Colors.transparent,
                                          Color(0x33000000),
                                        ],
                                        stops: [0.0, 0.45, 1.0],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 三层混色：必须直绘 framebuffer（不包 ShaderMask）
                          Positioned.fill(
                            child: CustomPaint(painter: _MixLayersPainter(v)),
                          ),
                          // 图标恒白 + 重投影
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

    canvas.drawRect(
      rect,
      Paint()
        ..color = Color.fromARGB((0x1A * v).round(), 0, 0, 0)
        ..blendMode = BlendMode.darken,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = Color.fromARGB((0x99 * v).round(), 0x6C, 0x6C, 0x6C)
        ..blendMode = BlendMode.luminosity,
    );
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

/// 顶部柔和反光弧（非整圈实线——评审“与界面有界限”）
/// + 点亮态软辉光圈。整圈 Bloom 描边已移除。
class _BloomStrokePainter extends CustomPainter {
  _BloomStrokePainter(this.v);

  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r - 1.6);

    // 顶部反光弧：柔化（宽 1.4、蒙 2px、顶点白 0.7 → 两侧退场）
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = SweepGradient(
        colors: const [
          Color(0xB3FFFFFF),
          Color(0x33FFFFFF),
          Color(0x00FFFFFF),
          Color(0x00FFFFFF),
          Color(0xB3FFFFFF),
        ],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawArc(rect, math.pi, math.pi, false, rim);

    // 点亮态软辉光圈（蒙版模糊，非实线）
    if (v > 0.02) {
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withOpacity(0.35 * v)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 3 * v);
      canvas.drawCircle(c, r - 1, glow);
    }
  }

  @override
  bool shouldRepaint(_BloomStrokePainter old) => old.v != v;
}
