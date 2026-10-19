import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'cards.dart';
import 'capsule_button.dart';
import 'fog_button.dart';
import 'refresh_capsule.dart';

/// 1:1 真页 chip 组：推荐 / 背屏 / 小部件 / 主题（黑胶囊选中态）
const _tabs = ['推荐', '背屏', '小部件', '主题'];

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    // 两个 AnimationController（_tabC/_enterC），必须多 ticker
    with TickerProviderStateMixin {
  final _latch = ScrollLatch();
  final _lit = ValueNotifier<bool>(false);
  final _sc = ScrollController();
  // 雾面带浮现进度 0..1：滚动 0→24px 线性映射（顶部 0，深滚 1）。
  final _band = ValueNotifier<double>(0);

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

  /// 雾面带内高度（不含状态栏）：顶栏 54（10+40+4）+ chip 栏 46（6+40）。
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
    _band.dispose();
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
    // 雾面带总高 = 状态栏 + 顶栏 + chip 栏
    final headerExtent = topInset + _kHeaderExtent;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F6),
      body: Stack(
        children: [
          // 内容层：全屏滚动，从雾面带下方穿过被实时模糊
          Positioned.fill(
            child: RefreshCapsule(
              topOffset: headerExtent + 6,
              onRefresh: () async {
                await Future<void>.delayed(const Duration(milliseconds: 1200));
              },
              child: NotificationListener<ScrollNotification>(
                // 迟滞锁存：上滑 >16px 点亮雾面按钮，下滑 <-16px 熄灭
                onNotification: (n) {
                  // 雾面带进度：0→24px 线性爬升，负过冲（下拉刷新）钳 0。
                  _band.value =
                      (n.metrics.pixels / 24).clamp(0.0, 1.0).toDouble();
                  _latch.update(n.metrics.pixels, (b) => _lit.value = b);
                  return false;
                },
                child: CustomScrollView(
                  controller: _sc,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    SliverPadding(
                      // 内容顶距：头部 + 14dp 呼吸位（静止时 Banner 完整
                      // 露在 chip 栏下方；滚动时内容照常从带下穿过）。
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
          // 雾面带：状态栏 → chip 栏底，随滚动浮现（顶部透明）。
          Positioned(top: 0, left: 0, right: 0, child: _fogHeader()),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
      floatingActionButton: FogButton(litListenable: _lit, onTap: _toTop),
    );
  }

  /// 雾面带：σ30 跟手渐入 + blurbgmix 混色。
  /// 真值口径（对照参考包资产核过）：`miuixappcompatblurbgmix_color`
  /// #6B6B6B alpha 0.651×t 是「往模糊里混色」（blendMode.softLight 直绘
  /// framebuffer），不是透明度平涂盖一层——之前按普通 alpha 叠，浅色
  /// 页面上就是一块灰板，一眼一条痕迹。混进模糊后：浅底几乎无感、深色
  /// 内容自然显影，即「看不出痕迹」；底部 32px 渐隐收边双保险。
  Widget _fogHeader() {
    return ValueListenableBuilder<double>(
      valueListenable: _band,
      builder: (context, t, _) {
        // 顶部零合成：跳过 BackdropFilter，搜索/chip 直接浮于页面底色
        if (t <= 0.005) {
          return SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [_searchBar(), _tabBar()],
            ),
          );
        }
        return ClipRect(
          child: BackdropFilter(
            key: const Key('fog-band-blur'),
            filter: ImageFilter.blur(sigmaX: 30 * t, sigmaY: 30 * t),
            child: Stack(
              children: [
                // 混色层：softLight + 渐隐 shader，单次 drawRect 直绘。
                // 不包 ShaderMask（saveLayer 会让 blend 打空、且会破坏
                // BackdropFilter 采样），渐隐和混色在同一个 Paint 里完成。
                Positioned.fill(
                  child: CustomPaint(
                    key: const Key('fog-band'),
                    painter: _BandTintPainter(0.651 * t, 32),
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
          ),
        );
      },
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
          const SizedBox(width: 10),
          CapsuleButton(
            label: '签到',
            icon: Icons.card_giftcard,
            dense: true,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  /// chip 组（1:1）：选中黑胶囊 / 未选白胶囊，背景色随同一根弹簧在 chip
  /// 间过渡；高度沿用原分组栏 40，雾面带高度账（100dp）不变。
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
        final w = (c.maxWidth - 12) / 2;
        final children = <Widget>[];
        for (var i = 0; i < 10; i++) {
          children.add(
            SizedBox(
              width: w,
              height: 168.0 + (i % 3) * 26, // 高度错落 → 双列错位观感
              child: AnimatedBuilder(
                animation: _enterC,
                builder: (_, __) => SpringEnter(
                  elapsedMs: _enterC.value * 1800,
                  index: i,
                  child: ThemeCard(index: i),
                ),
              ),
            ),
          );
        }
        return Column(
          children: [
            const BannerCard(),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: children),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  /// 底栏（1:1）：首页 / 分类 / 每日精选 / 我的，浮起圆角玻璃面板。
  /// 真值：nav_height 61.3dp、nav_parent_margin_top 8dp。
  /// 图标照参考包 SVG 真值（stroke #000 纯黑系）：选中纯黑、未选 80%
  /// 黑（原来 54% 发灰 = "不亮"）。Material 承载 ink，水波纹在底色之上。
  Widget _bottomBar() {
    const icons = [
      Icons.format_paint, // 首页
      Icons.dashboard, // 分类
      Icons.shield, // 每日精选
      Icons.person_rounded, // 我的
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

/// blurbgmix 混色层：#6B6B6B（平涂）以 softLight 混进模糊后的背景，
/// alpha = 0.651×t 跟手爬升；底部 feather px 用 shader alpha 渐隐收边。
/// 整个效果在一次 drawRect 里完成——不开 saveLayer，不破坏 BackdropFilter
/// 对页面的采样，也不触发 blend 打空。
class _BandTintPainter extends CustomPainter {
  _BandTintPainter(this.alpha, this.feather);

  final double alpha; // 0..1，调用方已乘滚动进度 t
  final double feather; // 底部渐隐像素

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0.005 || size.isEmpty) return;
    const base = Color(0xFF6B6B6B);
    final h = size.height;
    final stop =
        ((h - feather) / h).clamp(0.0, 1.0).toDouble();
    final paint = Paint()
      ..blendMode = BlendMode.softLight // 混进模糊，不是盖一层
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0, stop, 1],
        colors: [
          base.withValues(alpha: alpha),
          base.withValues(alpha: alpha),
          base.withValues(alpha: 0), // 底部收边：与下方内容无缝
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_BandTintPainter old) =>
      old.alpha != alpha || old.feather != feather;
}
