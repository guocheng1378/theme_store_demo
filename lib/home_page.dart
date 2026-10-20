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
  final _sc = ScrollController();
  // 雾面带浮现进度 0..1（8px 起步、48px 满 —— 晚于按钮，不抢戏）。
  final _band = ValueNotifier<double>(0);
  // 按钮用滚动像素自行拆 lift/bright（0-40px）与 fog（40-130px）。
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
                // 时序：内容先走 → 按钮 0-40px 拖起变亮 → 40-130px 慢雾
                // → 顶带 8-48px 晚跟（不能读成“整块蒙版被拖上来”）。
                onNotification: (n) {
                  final px = n.metrics.pixels;
                  // 顶带进度：8px 起步、48px 满；负过冲（下拉）钳 0。
                  _band.value =
                      ((px - 8) / 40).clamp(0.0, 1.0).toDouble();
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
          // 雾面带：状态栏 → chip 栏底，随滚动晚跟渐入（顶部透明）。
          Positioned(top: 0, left: 0, right: 0, child: _fogHeader()),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
      floatingActionButton: FogButton(
        scrollListenable: _fabPx,
        onTap: _toTop,
      ),
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

  /// 搜索：全宽单胶囊、图标+文字左对齐（对照 2026-10-20 官方截图，
  /// 官方顶栏无「签到」副钮，搜索横贯整行）。
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

  /// 内容区（2026-10-20 对照官方截图重构）：
  /// ① 推荐 = 一行 3 张锁屏高卡（9:16 预览 + 大时钟，标题在卡下）；
  /// ② 分区头「精选小部件 + 查看更多」；
  /// ③ 小部件 = 3 列×2 行方卡（迷你组件拼贴，标题在卡下）。
  Widget _feed(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 20) / 3; // 3 列，间距 10
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
            // ① 推荐：3 列锁屏高卡
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
            // ② 分区头
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
            // ③ 小部件：3 列 × 2 行
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

/// 卡片素材：标题 + 渐变 + 迷你组件文案（官方截图取值）。
class _ThemeArt {
  const _ThemeArt(this.title, this.colors, this.chips);

  final String title;
  final List<Color> colors;
  final List<String> chips;
}

/// 推荐：3 张锁屏高卡（9:16 构图）。
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

/// 小部件：3×2 方卡（前 3 个照抄官方截图标题）。
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

/// 锁屏高卡：渐变 + 顶部状态胶囊 + 大时钟（上 1/3 构图）+ 底部快捷圆，
/// 标题在卡下。
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
              // 顶部状态胶囊
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
              // 大时钟区（上 1/3，锁屏构图）
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
              // 底部快捷圆
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

/// 小部件方卡：渐变底 + 2×2 迷你组件拼贴，标题在卡下。
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
