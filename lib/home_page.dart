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
          // 按钮下移留缝（15:23 修“箭头怎么在最上面”）：球顶离带底
          // 12px，内容上滑先从带底这条缝穿过、再滑到按钮后面 ——
          // 即 B 原意“内容从雾带和按钮之间穿过”。box 顶 = 球顶 - 20。
          Positioned(
            top: headerExtent - 8,
            right: 16,
            child: FogButton(
              scrollListenable: _fabPx,
              onTap: _toTop,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  /// 雾面带：恒定雾化 + ShaderMask(dstIn) 模糊/混色底部 44px 整体羽化；
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
                  ((rect.height - 44) / rect.height).clamp(0.0, 1.0),
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
                child: CustomPaint(
                  key: const Key('fog-band'),
                  painter: _BandTintPainter(0.651),
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

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: CapsuleButton(
              label: '搜索主题 / 字体 / 壁纸',
              icon: Icons.search,
              onTap: () {},
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

  Widget _chip(int i) {
    return AnimatedBuilder(
      animation: _tabC,
      builder: (context, _) {
        final t = (1 - (i - _tabC.value).abs()).clamp(0.0, 1.0).toDouble();
        final bg =
            Color.lerp(const Color(0xD9FFFFFF), const Color(0xD9000000), t);
        final fg = Color.lerp(const Color(0xE6000000), Colors.white, t);
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _tapTab(i),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(20),
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
                Text(
                  '查看更多',
                  style: TextStyle(
                    fontSize: 13,
                    color: const Color(0x8A000000),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Color(0x8A000000),
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x0F000000)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: const Color(0xF2FFFFFF),
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
                              fontWeight:
                                  i == _nav ? FontWeight.w700 : FontWeight.w400,
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

class _BandTintPainter extends CustomPainter {
  _BandTintPainter(this.alpha);

  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0.005 || size.isEmpty) return;
    const base = Color(0xFF6B6B6B);
    final paint = Paint()
      ..blendMode = BlendMode.softLight
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, 1],
        colors: [
          base.withValues(alpha: alpha),
          base.withValues(alpha: alpha),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_BandTintPainter old) => old.alpha != alpha;
}
