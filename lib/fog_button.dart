import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 雾面按钮 —— 小米柔光玻璃（2026-10-20 15:20 修“不亮/不动/只有黑”）：
/// **黑的根源**：地面投影那团 55% 黑圆盘压在球底，玻璃的
/// BackdropFilter 模糊采样把投影一起糊进球里 = 死黑。修：
/// · 投影减淡（0x8C→0x52、0x59→0x2E），缝隙仍在但不染黑球底；
/// · 白纱加底：恒定奶白 0x14→0x40（25%），雾态再 +0.30 ——
///   滚起来明显雾化、不再只有黑；总透光仍在，玻璃感不丢。
/// · **亮 = 拎起 × (0.6 + 0.4×接近度)**：一滚动立刻 60% 亮
///   （可见的动+亮），快到按钮（50px）拉满；辉光 0.34→0.42。
/// · 拎起 = px>4 立即弹（320/19 ~0.3s 微回弹）-16px；
///   慢雾 = 软弹簧（55/16 ~0.6s）40-130px。
/// · 模糊羽化/三级阶梯/骑缝位置不变。
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
  static const _fogSpring =
      SpringDescription(mass: 1, stiffness: 55, damping: 16);
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
          final double lift = _liftC.value;
          final double prox =
              (widget.scrollListenable.value / 50).clamp(0.0, 1.0).toDouble();
          // 亮 = 拎起 × (0.6 + 0.4×接近度)：一滚就 60% 亮，
          // 快到按钮（50px）拉满 —— “动+亮”立刻可见。
          final double bright =
              (lift * (0.6 + 0.4 * prox)).clamp(0.0, 1.0).toDouble();
          final double fog = _c.value.clamp(0.0, 1.0).toDouble();
          final double glow = bright * (1 - 0.5 * fog);

          return SizedBox(
            width: s + 40,
            height: s + 40,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // 氛围辉光（0.42，随亮起）
                Container(
                  width: s + 8 + 14 * bright,
                  height: s + 8 + 14 * bright,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      radius: 0.5 + 0.1 * bright,
                      colors: [
                        Colors.white.withOpacity(0.42 * glow),
                        Colors.white.withOpacity(0.18 * glow),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                // 地面投影（减淡：0x52/0x2E —— 不再把球底染黑）
                Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x52000000),
                        offset: const Offset(0, 8),
                        blurRadius: 18,
                      ),
                      BoxShadow(
                        color: const Color(0x2E000000),
                        offset: Offset(0, 5 / dpr),
                        blurRadius: 56 / dpr,
                      ),
                    ],
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, -16 * lift),
                  child: SizedBox(
                    width: s + 24,
                    height: s + 24,
                    child: ClipOval(
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) => RadialGradient(
                          radius: 1.0,
                          stops: const [0.0, 0.80, 1.0],
                          colors: [
                            Colors.white,
                            Colors.white,
                            Colors.transparent,
                          ],
                        ).createShader(rect),
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
                                                        // 恒定奶白底 0x40：
                                                        // 压住投影，不再死黑
                                                        const ColoredBox(
                                                          color:
                                                              Color(0x40FFFFFF),
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
                                                                    0x33FFFFFF),
                                                                Colors
                                                                    .transparent,
                                                                Color(
                                                                    0x14000000),
                                                              ],
                                                              stops: [
                                                                0.0,
                                                                0.45,
                                                                1.0
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                        ColoredBox(
                                                          color: Colors.white
                                                              .withOpacity(
                                                            0.30 * bright,
                                                          ),
                                                        ),
                                                        // 雾态奶白纱 +0.30
                                                        ColoredBox(
                                                          color: Colors.white
                                                              .withOpacity(
                                                            0.30 * fog,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
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
                                                    painter: _GlassRimPainter(
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
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 柔光玻璃边：常驻 1px 细白亮边 + 反光弧 + 雾态辉光圈。
class _GlassRimPainter extends CustomPainter {
  _GlassRimPainter({required this.bright, required this.fog});

  final double bright;
  final double fog;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r - 1.6);

    final rimA =
        (0.42 + 0.30 * bright).clamp(0.0, 1.0).toDouble();
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = SweepGradient(
        colors: [
          Color.fromRGBO(255, 255, 255, rimA),
          Color.fromRGBO(255, 255, 255, rimA * 0.55),
          Color.fromRGBO(255, 255, 255, rimA * 0.30),
          Color.fromRGBO(255, 255, 255, rimA * 0.55),
          Color.fromRGBO(255, 255, 255, rimA),
        ],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawCircle(c, r - 1.4, rim);

    final arcA =
        (0.34 * bright * (1 - 0.35 * fog)).clamp(0.0, 1.0).toDouble();
    if (arcA > 0.01) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = SweepGradient(
          colors: [
            Color.fromRGBO(255, 255, 255, arcA),
            Color.fromRGBO(255, 255, 255, arcA * 0.3),
            Colors.transparent,
            Colors.transparent,
            Color.fromRGBO(255, 255, 255, arcA),
          ],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      canvas.drawArc(rect, math.pi, math.pi, false, arc);
    }

    if (fog > 0.02) {
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withOpacity(0.30 * fog)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 3 * fog);
      canvas.drawCircle(c, r - 1, glow);
    }
  }

  @override
  bool shouldRepaint(_GlassRimPainter old) =>
      old.bright != bright || old.fog != fog;
}
