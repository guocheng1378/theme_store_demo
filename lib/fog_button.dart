import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 雾面按钮 —— 小米柔光玻璃（2026-10-20 15:31 评审
/// “还是黑的没有雾，能把箭头去掉吗”）：
/// · **箭头（图标）已移除**：按钮就是一颗素玻璃球，点击仍回顶部。
/// · **雾改为常驻**：静止态就有奶白雾纱，滚动再加浓。
/// · **投影已全部移除**（21:06 评审“阴影去掉，雾化感觉没了”）。
/// · **磨砂颗粒层**（21:10 评审“按钮没有磨砂感”）：固定种子程序噪声。
/// · 亮 = 拎起 × (0.6 + 0.4×接近度)；拎起 = px>4 弹 -16px；慢雾 40-130px。
/// · **材质回主题真值**（06:43 评审“按钮和胶囊的材质跟主题还是有差距”）：
///   雾纱里叠 ColorBlendToken.l 手机档三层【字节码 SPECS §五】
///   （0x1A000000×PLUS_DARKER / 0x996C6C6C×LUMINOSITY /
///   0x99060606×SOFT_LIGHT，alpha 随亮/雾 0.45→1.0 爬升）——
///   这才是真机主题商店组件雾面的真实混色；奶白雾纱 0x7F→0x38
///   只留薄纱、白提升层 0.30→0.18，不再用白底盖住混色层
///   （之前的差距：整颗发“白塑料”，真机是随底色走的玻璃）。
///   ⚠ 层1 PLUS_DARKER：Flutter BlendMode 无此枚举（07:01 CI 编译报错
///   member not found），按 SPECS 注释约定降级 **darken**（视觉等效
///   渐进压暗）；真值字节码保留在注释里。
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
          // 奶白薄纱 0x7F→0x38（白退纱，真值混色层主导观感）
          final double milk = 0.22 + 0.06 * fog;
          // ColorBlendToken.l 混合强度：静止 0.45 → 亮起 +0.35 → 起雾 +0.20
          final double mix =
              (0.45 + 0.35 * bright + 0.20 * fog).clamp(0.0, 1.0).toDouble();

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
                // 黑投影层已移除（21:06 评审：阴影去掉，雾化感觉没了）。
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
                                      ImageFilter.blur(sigmaX: 11, sigmaY: 11),
                                  child: SizedBox(
                                    width: s + 12,
                                    height: s + 12,
                                    child: Center(
                                      child: ClipOval(
                                        child: BackdropFilter(
                                          filter: ImageFilter.blur(
                                              sigmaX: 22, sigmaY: 22),
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
                                                        // 常驻奶白薄纱
                                                        // （0x7F→0x38，
                                                        // 只留纱不盖玻璃）
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
                                                        // **主题真值三层混色**
                                                        // ColorBlendToken.l，
                                                        // SPECS §五【字节码】
                                                        Positioned.fill(
                                                          child: CustomPaint(
                                                            painter:
                                                                _ThemeMixPainter(
                                                              mix,
                                                            ),
                                                          ),
                                                        ),
                                                        ColoredBox(
                                                          color: Colors.white
                                                              .withOpacity(
                                                            0.18 * bright,
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

/// ColorBlendToken.l 手机档三层混色（SPECS §五【字节码】）——真机
/// 主题商店组件雾面（FAB/HyperCard 等）的真实玻璃配方：
/// 层1 0x1A000000 × PLUS_DARKER / 层2 0x996C6C6C × LUMINOSITY /
/// 层3 0x99060606 × SOFT_LIGHT；alpha 随 v（亮/雾）爬升。
/// ⚠ 层1：Flutter BlendMode 无 plusDarker 枚举（07:01 CI member not
/// found），按 SPECS 注释约定降级 darken——同为“渐进压暗”，
/// 真值字节码保留在注释里；层2/3 枚举存在，按真值走。
/// 绘制发生在 BackdropFilter 之后的同一帧缓冲上，与模糊后的背景相混。
class _ThemeMixPainter extends CustomPainter {
  _ThemeMixPainter(this.v);

  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    if (v <= 0.01) return;
    final rect = Offset.zero & size;

    // 层1 0x1A000000 × PLUS_DARKER（降级 darken，无 plusDarker 枚举）
    canvas.drawRect(
      rect,
      Paint()
        ..color = Color.fromARGB((0x1A * v).round(), 0, 0, 0)
        ..blendMode = BlendMode.darken,
    );
    // 层2 0x996C6C6C × LUMINOSITY
    canvas.drawRect(
      rect,
      Paint()
        ..color = Color.fromARGB((0x99 * v).round(), 0x6C, 0x6C, 0x6C)
        ..blendMode = BlendMode.luminosity,
    );
    // 层3 0x99060606 × SOFT_LIGHT
    canvas.drawRect(
      rect,
      Paint()
        ..color = Color.fromARGB((0x99 * v).round(), 0x06, 0x06, 0x06)
        ..blendMode = BlendMode.softLight,
    );
  }

  @override
  bool shouldRepaint(_ThemeMixPainter old) => old.v != v;
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
