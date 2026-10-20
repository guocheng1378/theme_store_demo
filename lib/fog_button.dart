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

/// 雾面按钮 —— 字节码真值 + 多轮评审补强：
/// ① 结构 = 开关式系统模糊(toq)，**双层羽化轮廓**：
///    外圈(半径 +8px) σ8 轻糊做过渡环、内圈 σ26 主糊。
///    模糊在圆周不再刀切（圈内突糊/圈外清晰 = 评审“还剩一点边界”主源），
///    外圈先糊一层，内容进入柔和过渡带。
/// ② 混色 = ColorBlendToken.l 三层（darken / luminosity / softLight），
///    每层用径向渐变 Shader 提供逐像素 alpha（0.72 内满 → 圆周透），
///    blendMode 逐像素直绘 framebuffer —— 不进 saveLayer，不破模糊。
/// ③ 球面明暗：上白(0x2E) → 中透 → 下黑(0x33) 顶光源，径向渐隐收边。
/// ④ 边界融合：黑底 + 球面层同样径向渐隐；去整圈环线，只留
///    1.2px/0x55 顶部柔化反光 + 点亮态软辉光圈（蒙版模糊，非实线）。
/// ⑤ 浮起感：环境阴影 #59000000/64px + 接触阴影 #66000000/14px/坠6px。
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
                // 浮起感：环境光晕 + 接触阴影（下坠 6px）
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
                // 双层羽化模糊轮廓：外圈 σ8 过渡环 → 内圈 σ26 主糊
                SizedBox(
                  width: s + 16,
                  height: s + 16,
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: SizedBox(
                        width: s + 16,
                        height: s + 16,
                        child: Center(
                          child: ClipOval(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                              child: SizedBox(
                                width: s,
                                height: s,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // 玻璃底 + 球面：径向渐隐收边（75% 内满 → 圆周透），
                                    // ShaderMask 只包普通 alpha 层，避开混色 saveLayer 坑
                                    Positioned.fill(
                                      child: ShaderMask(
                                        shaderCallback: (rect) => RadialGradient(
                                          radius: 1.0,
                                          stops: const [0.0, 0.75, 1.0],
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
                                    // 三层混色：径向渐变 Shader 逐像素控 alpha，
                                    // blendMode 直绘 framebuffer（不包 saveLayer）
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _MixLayersPainter(v),
                                      ),
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
                                      child: CustomPaint(
                                        painter: _BloomStrokePainter(v),
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

/// ColorBlendToken.l 三层混色（alpha 随 v 爬升），
/// 每层用径向渐变 Shader 把 alpha 推到圆周归零 —— 混色边界化开，
/// 同时保持 blendMode 在 framebuffer 上逐像素直绘（不进 saveLayer）。
class _MixLayersPainter extends CustomPainter {
  _MixLayersPainter(this.v);

  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    if (v <= 0.01) return;
    final rect = Offset.zero & size;

    void blend(Color c, BlendMode m) {
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = m
          ..shader = RadialGradient(
            radius: 1.0,
            stops: const [0.0, 0.72, 1.0],
            colors: [c, c, c.withOpacity(0)],
          ).createShader(rect),
      );
    }

    blend(Color.fromARGB((0x1A * v).round(), 0, 0, 0), BlendMode.darken);
    blend(Color.fromARGB((0x99 * v).round(), 0x6C, 0x6C, 0x6C),
        BlendMode.luminosity);
    blend(Color.fromARGB((0x99 * v).round(), 0x06, 0x06, 0x06),
        BlendMode.softLight);
  }

  @override
  bool shouldRepaint(_MixLayersPainter old) => old.v != v;
}

/// 顶部柔化反光弧（1.2px/0x55/2.5 蒙版，高光非实线）
/// + 点亮态软辉光圈。整圈环线已移除（评审“界限”）。
class _BloomStrokePainter extends CustomPainter {
  _BloomStrokePainter(this.v);

  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r - 1.6);

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = SweepGradient(
        colors: const [
          Color(0x55FFFFFF),
          Color(0x1AFFFFFF),
          Color(0x00FFFFFF),
          Color(0x00FFFFFF),
          Color(0x55FFFFFF),
        ],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawArc(rect, math.pi, math.pi, false, rim);

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
