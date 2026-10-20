import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

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
  void dispose() {
    _tabC.dispose();
    _enterC.dispose();
    _sc.dispose();
    _fabPx.dispose();
    _prox.dispose();
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

  /// 雾面带：恒定雾化 + 模糊/混色底部 24px 整体羽化。
  /// 羽化历史：44px（模糊被吃在 Tab 区，内容硬穿）→ 16px（21:30，
  /// Tab 底下有糊有雾，但 21:51 截图“雾化没做好”：过渡太急 +
  /// 奶白太淡、Banner 颜色穿透成色板）→ 24px（本笔：chip 已自带
  /// 玻璃不怕羽化落在胶囊区，底缘过渡更柔）；奶白 0.55→0.80→0.90、
  /// 带 alpha 0.651→0.75→0.92（有效白雾 0.36→0.60→0.83，
  /// 00:20 评审“雾不够密”：加浓一档）。
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
                stops: [
                  0.0,
                  ((rect.height - 24) / rect.height).clamp(0.0, 1.0),
                  1.0,
                ],
                colors: [
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
              ).createShader(rect),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                // 不包 Stack：Stack 默认 fit=loose 会放开非定位子级约束，
                // CustomPaint(无子级) size 被收成 0×0——tint（奶白+软光）
                // 整层不画，只剩模糊，Banner 紫色直接穿透（23:29 截图）。
                // 单 CustomPaint 直吃 BackdropFilter 紧约束（可用版结构）；
                // 砂点颗粒已按 00:15 评审要求移除，只留雾面 tint。
                child: CustomPaint(
                  key: const Key('fog-band'),
                  painter: _BandTintPainter(0.92),
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

  /// 搜索胶囊（磨砂玻璃）：内容穿过时白描边增亮（接近度驱动）；
  /// 光晕/投影层已删（21:30 评审：阴影要去掉）。
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
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(
                        (0.10 + 0.55 * h).clamp(0.0, 1.0),
                      ),
                      width: 1,
                    ),
                  ),
                  child: child,
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
// 雾带只保留 _BandTintPainter 奶白雾面。

class _BandTintPainter extends CustomPainter {
  _BandTintPainter(this.alpha);

  final double alpha;

  /// 雾面着色：奶白提亮层 + 极轻灰软光层。
  /// 奶白 0.55→0.80→0.90、带 alpha 0.651→0.75→0.92
  /// （21:51 评审“雾化没做好”→00:20 评审“雾不够密”：
  /// 有效白雾 0.36→0.60→0.83，顶栏读作奶白雾面玻璃）；
  /// 灰 softLight 强度保持 0.30 保留玻璃深度。
  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0.005 || size.isEmpty) return;
    final rect = Offset.zero & size;
    // 1) 奶白雾：normal 白层，浅色底上不再发黑
    final milk = Paint()
      ..color = Colors.white.withValues(alpha: 0.90 * alpha);
    canvas.drawRect(rect, milk);
    // 2) 玻璃深度：极轻灰 softLight（强度 0.30）
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
  bool shouldRepaint(_BandTintPainter old) => old.alpha != alpha;
}
