import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package/flutter/physics.dart';

/// 雾面按钮 —— 小米柔光玻璃（2026-10-20 15:31 评审
/// “还是黑的没有雾，能把箭头去掉吗”）：
/// · **箭头（图标）已移除**：按钮就是一颗素玻璃球，点击仍回顶部。
/// · **雾改为常驻**：静止态就有奶白雾纱 0x66（40%），滚动再加浓
///   +0x1A（→50% 封顶）—— 之前雾挂在 40px 后才起，静止态无雾，
///   深色内容一透就成“黑的”。现在任何状态都是奶白雾面，
///   深色底上也柔（柔光玻璃），滚动只做微调不改变基调。
/// · **投影已全部移除**（2026-10-20 21:06 评审“按键的阴影要去掉，
///   雾化感觉没了”）：球底两层黑投影 0x52/0x2E 会在奶白雾面下压出
///   黑环，雾感被阴影吃掉；去掉后球体只剩雾纱+柔光+细白亮边，
///   纯雾化悬浮，无任何黑色投影层。
/// · **磨砂颗粒层**（2026-10-20 21:10 评审“按钮没有磨砂感”）：
///   雾纱里叠一层固定种子的程序噪声（白/黑细点 @0x1A/@0x14，320 点，
///   点位不随帧变不闪烁），奶白雾底同时 0x66→0x7F（40%→50%，
///   滚动加浓 +0x14 封顶 ~58%）—— 纯色/浅色背景后也能读出
///   砂面颗粒，不再是一颗光滑圆点；点层在外层 ShaderMask 内，
///   随雾纱一同羽化到边。
/// · 亮 = 拎起 × (0.6 + 0.4×接近度)：一滚就 60% 亮，50px 拉满；
///   拎起 = px>4 立即弹 -16px（~0.3s 微回弹）；慢雾弹簧 40-130px
///   只调浓淡。
/// · 模糊羽化/三级阶梯/骑缝位置（带底 12px 缝）不变。
class FogButton extends StatefulWidget {
  const FogButton({
    super.key,
    required this.scrollListenable,
    this.onTap,
    this.size = 58,
  });

  /// 滚动像素（非负）。px>4 触发拎起；fog（浓淡）= clamp((px-40)/90)。
  final ValueListenable<double> scrollListenable;
  final VoidCallback? onTap;
  final double size;

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
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_c, _liftC, widget.scrollListenable]),
        builder: (context, _) {
          final double lift = _liftC.value;
          final double prox =
              (widget.scrollListenable.value / 50).clamp(0.0, 1.0).toDouble();
          final double bright =
              (lift * (0.6 + 0.4 * prox)).clamp(0.0, 1.0).toDouble();
          final double fog = _c.value.clamp(0.0, 1.0).toDouble();
          final double glow = bright * (1 - 0.5 * fog);
          // 常驻奶白雾 0x7F（50%），滚动加浓 +0x14（→ ~58% 封顶）
          final double milk = 0.50 + 0.08 * fog;

          return SizedBox(
            width: s + 40,
            height: s + 40,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
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
                // 黑投影层已移除（21:06 评审：阴影去掉，雾化感觉没了）——
                // 从前这里压着 0x52/0x2E 两层黑色 BoxShadow，
                // 球底黑环把奶白雾面衬得发硬；现在雾纱直接浮在柔光上。
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
                                                        // **常驻奶白雾纱**
                                                        // （静止也是雾面）
                                                        ColoredBox(
                                                          color: Colors.white
                                                              .withOpacity(
                                                            milk,
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
                                                        // 磨砂砂点：固定种子
                                                        // 程序噪声，画进雾纱层
                                                        // 随 ShaderMask 羽化。
                                                        const Positioned.fill(
                                                          child: CustomPaint(
                                                            painter:
                                                                _GrainPainter(),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                // 箭头已移除（15:31 要求），
                                                // 按钮为素玻璃球，点击回顶部
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

/// 柔光玻璃边：常驻 1px 细白亮边 + 反光弧 + 雾态辉光圈（无图标）。
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

/// 磨砂砂点（21:10 评审“按钮没有磨砂感”）：
/// 固定种子随机点位（点列表只生成一次，不会逐帧闪），
/// 白点 0x1A + 黑点 0x14 各半，近圆边丢弃，
/// 画在雾纱层里由 ShaderMask 羽化到边——平色背景也能读出颗粒。
class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  /// 归一化点位（[-1,1]²，单位圆内使用）；固定种子，与尺寸无关。
  static final List<Offset> _specks = () {
    final rnd = math.Random(20261020);
    return List.generate(320, (_) {
      return Offset(rnd.nextDouble() * 2 - 1, rnd.nextDouble() * 2 - 1);
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final lit = Paint()..color = const Color(0x1AFFFFFF);
    final dark = Paint()..color = const Color(0x14000000);
    for (var i = 0; i < _specks.length; i++) {
      final p = _specks[i];
      if (p.dx * p.dx + p.dy * p.dy > 0.94) continue;
      final off = Offset(c.dx + p.dx * r, c.dy + p.dy * r);
      if (i.isEven) {
        canvas.drawCircle(off, 1.2, lit);
      } else {
        canvas.drawCircle(off, 0.8, dark);
      }
    }
  }

  @override
  bool shouldRepaint(_GrainPainter old) => false;
}
