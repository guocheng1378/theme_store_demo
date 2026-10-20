import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 雾面按钮 —— 多轮评审收敛：
/// ① 拖起 = **动画式拎起**：内容一动（px>4）立即触发拎起弹簧
///    （320/19，约 0.3s，末尾微回弹）上升 -16px；回顶落回。
///    与滑速无关，快甩慢划都看得见“被拖起”。
/// ② 变亮 = 玻璃内提亮白 + 辉光/反光弧随拎起同步走。
/// ③ 慢雾 = 软弹簧（55/16，约 0.6s），40px 才起步 ——
///    “先抬起变亮，雾再慢慢罩上”。
/// ④ 混色（2026-10-20 13:53 官方截图色语言修正）：
///    官方页面深色元素（推荐选中胶囊/底栏图标）= **干净近黑**。
///    旧三层含 luminosity(#6C6C6C) 强制抽灰度 = 浑浊发脏；
///    现在去掉灰混，只留 darken(#000) + softLight(#030303)，
///    深色态 = 干净透黑（能透出底下模糊内容），对齐推荐胶囊色感；
///    每层仍径向渐变 Shader 逐像素 alpha（0.72 内满 → 圆周透），
///    blendMode 逐像素直绘 framebuffer —— 不进 saveLayer。
/// ⑤ 结构 = 开关式系统模糊(toq)，三级模糊阶梯：+12σ6 → +6σ12
///    → 核心σ26，每级跳变 ≤2.2×，圆周无单步硬跳。
/// ⑥ 地面投影不动（#8C000000/18px/坠8 + #59000000/56px/坠5），
///    球起缝隙变宽 = 托起。
/// ⑦ 图标恒白 + 重投影(0x8A/10px)。
class FogButton extends StatefulWidget {
  const FogButton({
    super.key,
    required this.scrollListenable,
    this.onTap,
    this.size = 58,
    this.icon = Icons.arrow_upward,
  });

  /// 滚动像素（非负）。px>4 触发拎起；fog = clamp((px-40)/90)。
  final ValueListenable<double> scrollListenable;
  final VoidCallback? onTap;
  final double size;
  final IconData icon;

  @override
  State<FogButton> createState() => _FogButtonState();
}

class _FogButtonState extends State<FogButton>
    with SingleTickerProviderStateMixin {
  // 慢雾：软弹簧，约 0.6s 收敛 —— “然后慢慢模糊”。
  static const _fogSpring =
      SpringDescription(mass: 1, stiffness: 55, damping: 16);
  // 拎起：快、带微回弹（阻尼比≈0.53，超调 ~12%）—— “被拖起”。
  static const _liftSpring =
      SpringDescription(mass: 1, stiffness: 320, damping: 19);

  late final AnimationController _c = AnimationController(vsync: this);
  late final AnimationController _liftC = AnimationController(vsync: this);
  double _target = 0;
  bool _lifted = false;

  @override
  void initState() {
    super.initState();
    widget.scrollListenable.addListener(_onScroll);
    _onScroll();
  }

  void _onScroll() {
    final px = widget.scrollListenable.value;
    // 拎起：内容一动立即拎（回顶落回），与滑速无关
    final up = px > 4;
    if (up != _lifted) {
      _lifted = up;
      _liftC.animateWith(SpringSimulation(
        _liftSpring,
        _liftC.value,
        up ? 1.0 : 0.0,
        _liftC.velocity,
      ));
    }
    // 慢雾：40px 才起步，软弹簧慢慢跟
    final t = ((px - 40) / 90).clamp(0.0, 1.0).toDouble();
    if ((t - _target).abs() < 0.003) return;
    _target = t;
    _c.animateWith(SpringSimulation(_fogSpring, _c.value, t, _c.velocity));
  }

  @override
  void dispose() {
    widget.scrollListenable.removeListener(_onScroll);
    _c.dispose();
    _liftC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_c, _liftC, widget.scrollListenable]),
        builder: (context, _) {
          // 拎起值（弹簧可超调到 ~1.12，上升末尾有回弹）
          final double lift = _liftC.value;
          final double bright = lift.clamp(0.0, 1.0).toDouble();
          final double fog = _c.value.clamp(0.0, 1.0).toDouble();
          final double glow = bright * (1 - 0.6 * fog);

          return SizedBox(
            width: s + 40,
            height: s + 40,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // 氛围辉光：随拎起变亮，被雾慢慢吹淡
                Container(
                  width: s + 8 + 14 * bright,
                  height: s + 8 + 14 * bright,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      radius: 0.5 + 0.1 * bright,
                      colors: [
                        Colors.white.withOpacity(0.34 * glow),
                        Colors.white.withOpacity(0.14 * glow),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                // 地面投影：阴影不动，球起缝隙变宽 = 托起
                Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x8C000000),
                        offset: const Offset(0, 8),
                        blurRadius: 18,
                      ),
                      BoxShadow(
                        color: const Color(0x59000000),
                        offset: Offset(0, 5 / dpr),
                        blurRadius: 56 / dpr,
                      ),
                    ],
                  ),
                ),
                // 拎起：整体上提 -16px·lift（可微超调，末尾回弹）
                Transform.translate(
                  offset: Offset(0, -16 * lift),
                  child: SizedBox(
                    width: s + 24,
                    height: s + 24,
                    // 三级模糊阶梯：+12σ6 → +6σ12 → 核心σ26
                    child: ClipOval(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: SizedBox(
                          width: s + 24,
                          height: s + 24,
                          child: Center(
                            child: ClipOval(
                              child: BackdropFilter(
                                filter:
                                    ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                child: SizedBox(
                                  width: s + 12,
                                  height: s + 12,
                                  child: Center(
                                    child: ClipOval(
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                            sigmaX: 26, sigmaY: 26),
                                        child: SizedBox(
                                          width: s,
                                          height: s,
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              // 玻璃底 + 提亮白 + 球面：
                                              // 径向渐隐收边（0.72 内满）
                                              Positioned.fill(
                                                child: ShaderMask(
                                                  shaderCallback: (rect) =>
                                                      RadialGradient(
                                                    radius: 1.0,
                                                    stops: const [
                                                      0.0,
                                                      0.72,
                                                      1.0
                                                    ],
                                                    colors: [
                                                      Colors.white,
                                                      Colors.white,
                                                      Colors.transparent,
                                                    ],
                                                  ).createShader(rect),
                                                  blendMode: BlendMode.dstIn,
                                                  child: Stack(
                                                    children: [
                                                      const ColoredBox(
                                                        color:
                                                            Color(0x1F000000),
                                                      ),
                                                      ColoredBox(
                                                        color: Colors.white
                                                            .withOpacity(
                                                          0.30 *
                                                              bright *
                                                              (1 -
                                                                  0.75 *
                                                                      fog),
                                                        ),
                                                      ),
                                                      const DecoratedBox(
                                                        decoration:
                                                            BoxDecoration(
                                                          gradient:
                                                              LinearGradient(
                                                            begin: Alignment
                                                                .topCenter,
                                                            end: Alignment
                                                                .bottomCenter,
                                                            colors: [
                                                              Color(
                                                                  0x2EFFFFFF),
                                                              Colors
                                                                  .transparent,
                                                              Color(
                                                                  0x33000000),
                                                            ],
                                                            stops: [
                                                              0.0,
                                                              0.45,
                                                              1.0
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              // 干净深黑混色（去灰混），
                                              // 直绘 framebuffer
                                              Positioned.fill(
                                                child: CustomPaint(
                                                  painter:
                                                      _MixLayersPainter(fog),
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
                                                  painter: _BloomStrokePainter(
                                                    bright: bright,
                                                    fog: fog,
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

/// 混色（13:53 色语言修正）：去掉 luminosity 灰混（强制抽灰度 = 浑浊），
/// 只留两层 —— darken(#000) 压暗 + softLight(#030303) 深邃，
/// 深色态 = 干净透黑（贴近官方“推荐”选中胶囊），底下模糊内容可透出。
/// 每层径向渐变 Shader 把 alpha 推到圆周归零，blendMode 逐像素直绘。
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

    // 干净压暗（对齐深色胶囊的透黑，不带灰混）
    blend(Color.fromARGB((0x2E * v).round(), 0, 0, 0), BlendMode.darken);
    blend(Color.fromARGB((0x99 * v).round(), 0x03, 0x03, 0x03),
        BlendMode.softLight);
  }

  @override
  bool shouldRepaint(_MixLayersPainter old) => old.v != v;
}

/// 顶部柔化反光弧 + 软辉光圈：强度随“亮”起、被“雾”压，
/// 整圈实线环已移除（评审“界限”）。
class _BloomStrokePainter extends CustomPainter {
  _BloomStrokePainter({required this.bright, required this.fog});

  final double bright;
  final double fog;

  @override
  void paint(Canvas canvas, Size size) {
    final rimA =
        (0.34 * bright * (1 - 0.45 * fog)).clamp(0.0, 1.0).toDouble();
    if (rimA <= 0.01 && fog <= 0.02) return;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r - 1.6);

    if (rimA > 0.01) {
      final rim = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = SweepGradient(
          colors: [
            Color.fromRGBO(255, 255, 255, rimA),
            Color.fromRGBO(255, 255, 255, rimA * 0.3),
            Colors.transparent,
            Colors.transparent,
            Color.fromRGBO(255, 255, 255, rimA),
          ],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      canvas.drawArc(rect, math.pi, math.pi, false, rim);
    }

    if (fog > 0.02) {
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withOpacity(0.28 * fog)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 3 * fog);
      canvas.drawCircle(c, r - 1, glow);
    }
  }

  @override
  bool shouldRepaint(_BloomStrokePainter old) =>
      old.bright != bright || old.fog != fog;
}
