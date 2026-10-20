import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 雾面按钮 —— 时序按用户 2026-10-20 描述重排：
/// “界面滑上去 → 按钮被拖起变亮 → 然后慢慢模糊”，
/// 顶带要晚于按钮，不能读成“整块蒙版被拖上来”。
/// ① 拖起：滚动 0→40px 线性上提 -12px（内容滑、按钮被拎起），
///    阴影留在地面 → 缝隙变宽 = 升起感（不再用二元 latch 硬跳）。
/// ② 变亮：同 0→40px 玻璃内白提升（0.30）+ 辉光/反光弧同步起，
///    按钮先“亮起来”。
/// ③ 慢慢模糊：雾态目标 = clamp((px-40)/90)，从 40px 才开始、90px
///    走完，且用软弹簧（90/20，临界阻尼 ≈0.4s 收敛）跟随，
///    “亮起 → 后慢雾”两段式；回滑自动逆放。
/// ④ 结构 = 开关式系统模糊(toq)，三级模糊阶梯：+12px σ6 → +6px σ12
///    → 核心 σ26，每级跳变 ≤2.2×，圆周无单步硬跳。
/// ⑤ 混色 = ColorBlendToken.l 三层（darken/luminosity/softLight），
///    每层径向渐变 Shader 逐像素 alpha（0.72 内满 → 圆周透），
///    blendMode 逐像素直绘 framebuffer —— 不进 saveLayer。
/// ⑥ 球面明暗 + 地面投影（#8C000000/18px/坠8 + #59000000/56px/坠5）。
/// ⑦ 图标恒白 + 重投影(0x8A/10px)；顶部反光弧 1.2px 柔化。
class FogButton extends StatefulWidget {
  const FogButton({
    super.key,
    required this.scrollListenable,
    this.onTap,
    this.size = 58,
    this.icon = Icons.arrow_upward,
  });

  /// 滚动像素（非负）。内部拆成 lift/bright（0-40px）与 fog（40-130px）。
  final ValueListenable<double> scrollListenable;
  final VoidCallback? onTap;
  final double size;
  final IconData icon;

  @override
  State<FogButton> createState() => _FogButtonState();
}

class _FogButtonState extends State<FogButton>
    with SingleTickerProviderStateMixin {
  // 软弹簧：临界阻尼、约 0.4s 收敛 —— “慢慢模糊”的手感来源。
  static const _fogSpring =
      SpringDescription(mass: 1, stiffness: 90, damping: 20);

  late final AnimationController _c = AnimationController(vsync: this);
  double _target = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollListenable.addListener(_onScroll);
    _onScroll();
  }

  void _onScroll() {
    final t = ((widget.scrollListenable.value - 40) / 90)
        .clamp(0.0, 1.0)
        .toDouble();
    if ((t - _target).abs() < 0.003) return;
    _target = t;
    _c.animateWith(
      SpringSimulation(_fogSpring, _c.value, t, _c.velocity),
    );
  }

  @override
  void dispose() {
    widget.scrollListenable.removeListener(_onScroll);
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
        animation: Listenable.merge([_c, widget.scrollListenable]),
        builder: (context, _) {
          final double px = widget.scrollListenable.value;
          // 拖起 + 变亮：0→40px 即时跟随（内容滑、按钮被拎起）
          final double lift = (px / 40).clamp(0.0, 1.0).toDouble();
          final double bright = lift;
          // 慢雾：40px 起步，软弹簧慢慢跟
          final double fog = _c.value.clamp(0.0, 1.0).toDouble();
          // 亮度被雾接管：亮起后随雾加深逐渐收回
          final double glow = bright * (1 - 0.6 * fog);

          return SizedBox(
            width: s + 40,
            height: s + 40,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // 氛围辉光：随“变亮”起来、被雾慢慢吹淡
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
                // 地面投影：阴影不动，球起缝隙变宽 = 升起感
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
                // 拖起：整体上提 -12px·lift（阴影留地面）
                Transform.translate(
                  offset: Offset(0, -12 * lift),
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
                                                      // 变亮层：随 lift 起、
                                                      // 被 fog 收回
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
                                              // 三层混色（随雾态），直绘
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

/// ColorBlendToken.l 三层混色（alpha 随雾态 fog 爬升），
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

    blend(Color.fromARGB((0x1A * v).round(), 0, 0, 0), BlendMode.darken);
    blend(Color.fromARGB((0x99 * v).round(), 0x6C, 0x6C, 0x6C),
        BlendMode.luminosity);
    blend(Color.fromARGB((0x99 * v).round(), 0x06, 0x06, 0x06),
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
