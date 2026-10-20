import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

import 'cards.dart';
import 'capsule_button.dart';
import 'fog_button.dart';
import 'refresh_capsule.dart';

const _tabs = ['推荐', '背屏', '小部件', '主题'];

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin {
  final _sc = ScrollController();
  final _fabPx = ValueNotifier<double>(0);
  // 全按钮统一高亮信号：界面内容快穿过谁，谁就高亮
  // （接近度 clamp(px/50) 驱动搜索/chips/查看更多/导航条/悬浮球，回顶熄灭）。
  final _prox = ValueNotifier<double>(0);

  // —— 雾色动态取色（06:43 评审“雾色应该用动态取色的方法”）——
  final _contentKey = GlobalKey(); // 抓帧边界（内容区 RepaintBoundary）
  final _fogTint = // 采样平滑后的雾色
      ValueNotifier<Color>(const Color(0xFFE4E7EB));
  Timer? _fogTick; // 采样节拍 160ms
  bool _sampling = false; // 抓帧防重入

  late final AnimationController _tabC = AnimationController(
    vsync: this,
    value: 0,
  );
  late final AnimationController _enterC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..forward();

  int _tab = 0;
  int _nav = 0;

  static const _kHeaderExtent = 100.0;

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 400,
    damping: 26,
  );

  @override
  void initState() {
    super.initState();
    // 动态取色节拍：_sampleFog 内部有 _sampling 防重入，
    // 抓帧/解码失败静默（catch），不影响正常渲染。
    _fogTick = Timer.periodic(const Duration(milliseconds: 160), (_) {
      unawaited(_sampleFog());
    });
  }

  @override
  void dispose() {
    _fogTick?.cancel();
    _tabC.dispose();
    _enterC.dispose();
    _sc.dispose();
    _fabPx.dispose();
    _prox.dispose();
    _fogTint.dispose();
    super.dispose();
  }

  void _tapTab(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
    _tabC.animateWith(
      SpringSimulation(_spring, _tabC.value, i.toDouble(), _tabC.velocity),
    );
  }

  void _toTop() => _sc.animateTo(
    0,
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOutCubic,
  );

  /// 雾色动态取色（06:43 评审“雾色应该用动态取色的方法”）：
  /// 每 160ms 把内容区抓成 ~0.12 倍小图，只统计雾带覆盖的顶部区域
  /// （0 .. topInset+136 逻辑像素），网格取平均色 → 彩度判断：
  /// 近灰（页面底色）→ 中性雾 #E4E7EB；有彩 → 提亮成“雾色”
  /// （lerp 白 0.42，亮度不足再补到 luma≥175）→ 以 0.30 步长平滑
  /// 插值喂 _fogTint。雾面着色层的主色层改用该值——静止是中性薄雾，
  /// 内容滑过时雾面被染成穿过内容的色（不再靠固定奶白+饱和透色）。
  Future<void> _sampleFog() async {
    if (_sampling || !mounted) return;
    final boundary =
        _contentKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    _sampling = true;
    try {
      final topInset = MediaQuery.paddingOf(context).top;
      final img = await boundary.toImage(pixelRatio: 0.12);
      final w = img.width;
      final h = img.height;
      final bd = await img.toByteData(format: ImageByteFormat.rawRgba);
      img.dispose();
      if (bd == null || !mounted || w <= 0 || h <= 0) return;
      final bytes = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      final yMax =
          ((topInset + _kHeaderExtent + 36) * 0.12).floor().clamp(0, h - 1);
      var r = 0, g = 0, b = 0, n = 0;
      for (var y = 0; y <= yMax; y += 2) {
        for (var x = 0; x < w; x += 2) {
          final i = (y * w + x) * 4;
          if (i + 2 >= bytes.length) break;
          r += bytes[i];
          g += bytes[i + 1];
          b += bytes[i + 2];
          n++;
        }
      }
      if (n == 0) return;
      r ~/= n;
      g ~/= n;
      b ~/= n;
      final mx = math.max(r, math.max(g, b));
      final mn = math.min(r, math.min(g, b));
      Color target;
      if ((mx - mn) < 13) {
        // 近灰（页面底色主导）→ 中性薄雾，不引入色偏
        target = const Color(0xFFE4E7EB);
      } else {
        var c = Color.fromARGB(255, r, g, b);
        c = Color.lerp(c, Colors.white, 0.42)!; // 压到雾色亮度
        final argb = c.toARGB32();
        final luma = 0.299 * ((argb >> 16) & 0xFF) +
            0.587 * ((argb >> 8) & 0xFF) +
            0.114 * (argb & 0xFF);
        if (luma < 175) {
          c = Color.lerp(
            c,
            Colors.white,
            ((175 - luma) / 255).clamp(0.0, 1.0).toDouble(),
          )!;
        }
        target = c;
      }
      final cur = _fogTint.value;
      final next = Color.lerp(cur, target, 0.30)!;
      if (next.toARGB32() != cur.toARGB32()) _fogTint.value = next;
    } catch (_) {
      // 首帧/尺寸竞争等抓帧失败：静默，下个周期再试
    } finally {
      _sampling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final headerExtent = topInset + _kHeaderExtent;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F6),
      body: Stack(
        children: [
          Positioned.fill(
            child: RefreshCapsule(
              topOffset: headerExtent + 6,
              onRefresh: () async {
                await Future<void>.delayed(const Duration(milliseconds: 1200));
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  final px = n.metrics.pixels;
                  _fabPx.value = px < 0 ? 0.0 : px;
                  _prox.value = (px / 50).clamp(0.0, 1.0).toDouble();
                  return false;
                },
                // RepaintBoundary：动态取色的抓帧边界（只含内容，
                // 不含雾带/搜索/chips 这些浮层——采到的是“穿过的内容”本色）
                child: RepaintBoundary(
                  key: _contentKey,
                  child: CustomScrollView(
                    controller: _sc,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          headerExtent + 14,
                          16,
                          16,
                        ),
                        sliver: SliverToBoxAdapter(child: _feed(context)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: _fogHeader()),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
      // 回顶部按钮：右下角（导航栏上方，系统 endFloat 标准位）。
      // 素玻璃球（箭头已删）+ 常驻奶白雾 + 接近度高亮 + 拎起时序。
      floatingActionButton: FogButton(
        scrollListenable: _fabPx,
        onTap: _toTop,
      ),
    );
  }

  /// 雾面带：恒定雾化 + 模糊/混色底部 56px 整体羽化。
  /// 雾色着色主层已改**动态取色**（06:43 评审“雾色应该用动态取色的
  /// 方法”）：_sampleFog 160ms 采样穿过的内容主色，平滑插值后由
  /// AnimatedBuilder 喂给 _BandTintPainter——静止中性雾，内容滑过
  /// 染成内容色；固定奶白只退为底色参考（被 tint 层替代）。
  /// 羽化 56（≥模糊 sigma 46）与模糊 46 + 饱和 1.75 保持
  /// （01:01 评审“雾没变色/边界可见”结论）。
  /// 搜索/chips 在羽化层之上保持清晰；Stack 高度由 chips 列定义（有界）。
  Widget _fogHeader() {
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            key: const Key('fog-band-blur'),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // 羽化 24→56：必须 ≥ 模糊 sigma 46，否则模糊层底缘被裁出
                // 一条糊/清接缝（01:01 评审“还能看到边界”）
                stops: [
                  0.0,
                  ((rect.height - 56) / rect.height).clamp(0.0, 1.0),
                  1.0,
                ],
                colors: [
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
              ).createShader(rect),
              child: BackdropFilter(
                // 模糊 46 化形为色雾 + 饱和度矩阵 1.45→1.75（01:01 评审
                // “雾没变色”）：色相源头更浓，雾面跟着穿过的内容变色
                filter: ImageFilter.compose(
                  outer: const ColorFilter.matrix(<double>[
                    1.59025, -0.53625, -0.054, 0, 0,
                    -0.15975, 1.21375, -0.054, 0, 0,
                    -0.15975, -0.53625, 1.696, 0, 0,
                    0, 0, 0, 1, 0,
                  ]),
                  inner: ImageFilter.blur(sigmaX: 46, sigmaY: 46),
                ),
                // 不包 Stack：Stack 默认 fit=loose 会放开非定位子级约束，
                // CustomPaint(无子级) size 被收成 0×0——tint 整层不画。
                // AnimatedBuilder 每帧给最新动态雾色（_fogTint）。
                child: AnimatedBuilder(
                  animation: _fogTint,
                  builder: (context, _) => CustomPaint(
                    key: const Key('fog-band'),
                    painter: _BandTintPainter(0.92, _fogTint.value),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [_searchBar(), _tabBar()],
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索胶囊（磨砂玻璃）：内容穿过时高亮（01:07 修复“搜索不亮”）：
  /// 描边提至子级之上 + 外白光晕 + 托起暗影，接近度驱动。
  /// 材质本体真值见 capsule_button（#0A000000 底 + 模糊 18）。
  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _prox,
              builder: (context, child) {
                final h = _prox.value;
                // 01:07 评审“搜索为什么不亮”：原白描边画在内层胶囊之下，
                // 被胶囊自带投影+白底盖死（白叠白也无对比）→ 高亮改三件：
                // 描边提至子级之上（Stack 覆盖层）+ 外白光晕 + 托起暗影。
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      if (h > 0.01) ...[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18 * h),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Colors.white.withOpacity(0.55 * h),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                      ],
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      child!,
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(
                                  (0.15 + 0.70 * h).clamp(0.0, 1.0),
                                ),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              child: CapsuleButton(
                label: '搜索主题 / 字体 / 壁纸',
                icon: Icons.search,
                onTap: () {},
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++) _chip(i),
        ],
      ),
    );
  }

  /// chip（磨砂玻璃，21:30 评审改）：每颗自带 BackdropFilter 真磨砂，
  /// 实心色改半透玻璃、光晕投影整层删除——未选中=半透白玻璃透雾底，
  /// 选中=深色玻璃（仍是小米深色选中态，但不再实心死黑）；
  /// 内容穿过时白描边增亮（与搜索/查看更多/导航条/悬浮球同源信号）。
  Widget _chip(int i) {
    return AnimatedBuilder(
      animation: Listenable.merge([_tabC, _prox]),
      builder: (context, _) {
        final t = (1 - (i - _tabC.value).abs()).clamp(0.0, 1.0).toDouble();
        final h = _prox.value;
        final bg =
            Color.lerp(const Color(0x7AFFFFFF), const Color(0xA6000000), t);
        final fg = Color.lerp(const Color(0xE6000000), Colors.white, t);
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _tapTab(i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.25 + 0.55 * h),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _tabs[i],
                    style: TextStyle(
                      fontSize: 15,
                      color: fg,
                      fontWeight: t >= 0.5 ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _feed(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 20) / 3;
        Widget enter(int i, Widget child) => AnimatedBuilder(
          animation: _enterC,
          builder: (_, __) => SpringEnter(
            elapsedMs: _enterC.value * 1800,
            index: i,
            child: child,
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BannerCard(),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < _locks.length; i++)
                  SizedBox(
                    width: w,
                    child: enter(i, _LockCard(_locks[i], w)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text(
                  '精选小部件',
                  style: TextStyle(
                    fontSize: 17.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xE6000000),
                  ),
                ),
                const Spacer(),
                // 查看更多（磨砂玻璃胶囊）：内容穿过时提亮
                AnimatedBuilder(
                  animation: _prox,
                  builder: (context, child) {
                    final h = _prox.value;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.60 + 0.30 * h),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.35 + 0.45 * h),
                          ),
                          boxShadow: [
                            if (h > 0.01)
                              BoxShadow(
                                color: Colors.white.withOpacity(0.40 * h),
                                blurRadius: 9,
                              ),
                          ],
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '查看更多',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xE6000000),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Color(0x8A000000),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < _widgets.length; i++)
                  SizedBox(
                    width: w,
                    child: enter(_locks.length + i, _WidgetCard(_widgets[i], w)),
                  ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  /// 底部导航（磨砂玻璃条）：真背景模糊 + 半透明白玻璃；
  /// 内容穿过时整条提亮（白填充/描边随 _prox 增亮 + 白柔光）。
  Widget _bottomBar() {
    const icons = [
      Icons.format_paint,
      Icons.dashboard,
      Icons.shield,
      Icons.person_rounded,
    ];
    const labels = ['首页', '分类', '每日精选', '我的'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: AnimatedBuilder(
        animation: _prox,
        builder: (context, _) {
          final h = _prox.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.30 + 0.50 * h),
              ),
              boxShadow: [
                const BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
                if (h > 0.01)
                  BoxShadow(
                    color: Colors.white.withOpacity(0.50 * h),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Material(
                  color: Colors.white.withOpacity(0.60 + 0.30 * h),
                  borderRadius: BorderRadius.circular(24),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    height: 61.3,
                    child: Row(
                      children: [
                        for (var i = 0; i < labels.length; i++)
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _nav = i),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    icons[i],
                                    size: 22,
                                    color: i == _nav
                                        ? const Color(0xFF000000)
                                        : const Color(0xCC000000),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    labels[i],
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: i == _nav
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: i == _nav
                                          ? const Color(0xFF000000)
                                          : const Color(0xCC000000),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ThemeArt {
  const _ThemeArt(this.title, this.colors, this.chips);

  final String title;
  final List<Color> colors;
  final List<String> chips;
}

const _locks = <_ThemeArt>[
  _ThemeArt(
    '罗小黑 清凉泳池',
    [Color(0xFF9AD8F0), Color(0xFF3E8FD0)],
    ['02:36', '10月14日'],
  ),
  _ThemeArt(
    '爱你时有风',
    [Color(0xFF7D8F70), Color(0xFF2E3A2C)],
    ['02:36', '10月14日'],
  ),
  _ThemeArt(
    'AP26 超级玻璃',
    [Color(0xFFCFE3FA), Color(0xFF4A78C0)],
    ['02:36', '10月14日'],
  ),
];

const _widgets = <_ThemeArt>[
  _ThemeArt(
    '蜘蛛侠 酷感雨雾',
    [Color(0xFF4A4A4E), Color(0xFFB03030)],
    ['12:37', '55 步', '22°', '08:08'],
  ),
  _ThemeArt(
    'MyCar',
    [Color(0xFF1C1C1E), Color(0xFF4A4A4E)],
    ['22:34', '12:37', '56%', '120km'],
  ),
  _ThemeArt(
    '线条小狗 春日…',
    [Color(0xFFF7E8F2), Color(0xFFBFE5CE)],
    ['08:08', '12:37', '55 步', '晚安'],
  ),
  _ThemeArt(
    '组件合集',
    [Color(0xFFDCEBFB), Color(0xFF7FA8E0)],
    ['24', '12:37', '85%', '晴'],
  ),
  _ThemeArt(
    '日历美化',
    [Color(0xFFFDEDEC), Color(0xFFE07060)],
    ['新增', '周五', '10:00', '会议'],
  ),
  _ThemeArt(
    '考勤打卡',
    [Color(0xFFFFF3E0), Color(0xFFF0A030)],
    ['75%', '考勤打卡', '18:00', '下班'],
  ),
];

class _LockCard extends StatelessWidget {
  const _LockCard(this.art, this.w);

  final _ThemeArt art;
  final double w;

  @override
  Widget build(BuildContext context) {
    final h = w * 1.78;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: art.colors,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 9,
                left: 9,
                right: 9,
                child: Row(
                  children: [
                    Container(
                      width: w * 0.22,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: w * 0.16,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: h * 0.28,
                left: 6,
                right: 6,
                child: Column(
                  children: [
                    Text(
                      art.chips[1],
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: Color(0xB3FFFFFF),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      art.chips[0],
                      style: TextStyle(
                        fontSize: w * 0.30,
                        fontWeight: FontWeight.w300,
                        color: Colors.white,
                        letterSpacing: -1,
                        height: 1.05,
                        shadows: const [
                          Shadow(color: Color(0x40000000), blurRadius: 8),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final ic in [
                      Icons.flash_on,
                      Icons.camera_alt_outlined,
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(
                            color: Color(0x33FFFFFF),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(ic, size: 14, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          art.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: Color(0xE6000000),
          ),
        ),
      ],
    );
  }
}

class _WidgetCard extends StatelessWidget {
  const _WidgetCard(this.art, this.w);

  final _ThemeArt art;
  final double w;

  @override
  Widget build(BuildContext context) {
    final h = w * 1.25;
    final tw = (w - 16 - 6) / 2;
    final th = (h - 16 - 6) / 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: w,
          height: h,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: art.colors,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < art.chips.length; i++)
                Container(
                  width: tw,
                  height: th,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i.isEven
                        ? const Color(0xB3FFFFFF)
                        : const Color(0x59000000),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    art.chips[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: i.isEven
                          ? const Color(0xE6000000)
                          : Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          art.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: Color(0xE6000000),
          ),
        ),
      ],
    );
  }
}

// 砂点颗粒层 _BandGrainPainter 已按 00:15 评审要求移除（点点去掉），
// 雾带只保留 _BandTintPainter；主色层已改动态取色（06:43 评审）。

class _BandTintPainter extends CustomPainter {
  _BandTintPainter(this.alpha, this.tint);

  final double alpha;

  /// 动态雾色（_sampleFog 160ms 采样 + 0.30 平滑插值后的值）：
  /// 内容彩 → 染成内容色的雾；内容灰/静止 → 中性薄雾 #E4E7EB。
  final Color tint;

  /// 雾面着色三层：①动态雾色（主色层，替代固定奶白）
  /// ②白 softLight 提密保色 ③灰 softLight 玻璃深度。
  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0.005 || size.isEmpty) return;
    final rect = Offset.zero & size;
    // 1) 动态雾色主层（06:43“雾色应该用动态取色的方法”）：
    //    采样得到的穿过内容主色，压成雾色亮度后 0.42 上雾面
    final wash = Paint()
      ..color = tint.withValues(alpha: 0.42 * alpha);
    canvas.drawRect(rect, wash);
    // 2) 增密提亮 0.58：白 softLight 保密度但不把色刷白
    final lift = Paint()
      ..blendMode = BlendMode.softLight
      ..color = Colors.white.withValues(alpha: 0.58 * alpha);
    canvas.drawRect(rect, lift);
    // 3) 玻璃深度：极轻灰 softLight（强度 0.30）
    const base = Color(0xFF6B6B6B);
    final depth = Paint()
      ..blendMode = BlendMode.softLight
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, 1],
        colors: [
          base.withValues(alpha: 0.30 * alpha),
          base.withValues(alpha: 0.30 * alpha),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, depth);
  }

  @override
  bool shouldRepaint(_BandTintPainter old) =>
      old.alpha != alpha || old.tint != tint;
}
