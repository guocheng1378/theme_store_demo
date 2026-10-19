import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'squircle.dart';

/// 单条弹簧时间基：全列表共用一个 Ticker，卡片按 index 错峰 60ms 弹入。
/// 对应首页 Staggered 进场；x(t) 会轻微过冲再落位（果冻感来源）。
class SpringEnter extends StatelessWidget {
  const SpringEnter({
    super.key,
    required this.elapsedMs,
    required this.index,
    required this.child,
  });

  final double elapsedMs;
  final int index;
  final Widget child;

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 400,
    damping: 26,
  );

  /// x(t) 是纯函数（无内部状态），全卡共享一个实例，避免每帧每卡重建。
  static final SpringSimulation _sim = SpringSimulation(_spring, 0, 1, 0);

  @override
  Widget build(BuildContext context) {
    final t = (elapsedMs - index * 60) / 1000.0;
    if (t <= 0) {
      return const Opacity(opacity: 0);
    }
    final x = _sim.x(t);
    if (x >= 0.999) {
      return child; // 已落位：短路掉包裹层，动画尾期不再 rebuild
    }
    return Opacity(
      opacity: (x * 1.6).clamp(0.0, 1.0).toDouble(),
      child: Transform.translate(offset: Offset(0, 30 * (1 - x)), child: child),
    );
  }
}

/// 渐变 Banner（squircle 圆角）。渐变只用于底图 —— 雾面本身不打斜。
class BannerCard extends StatelessWidget {
  const BannerCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const SquircleClipper(n: 5),
      child: SizedBox(
        height: 150,
        width: double.infinity,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF5B7CFA), Color(0xFF8E5BF0), Color(0xFFFF7BAC)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                Text(
                  '秋日限定 · 超质感新皮肤',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Folme 弹簧 · 雾面玻璃 · 超椭圆',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _cardGradients = [
  [Color(0xFFFFD3A5), Color(0xFFFD6585)],
  [Color(0xFFA1FFCE), Color(0xFFFAFFD1)],
  [Color(0xFF8EC5FC), Color(0xFFE0C3FC)],
  [Color(0xFFF6D365), Color(0xFFFDA085)],
  [Color(0xFFD4FC79), Color(0xFF96E6A1)],
  [Color(0xFFCD9CF2), Color(0xFFF6F3FF)],
];

/// 主题卡：squircle 预览图 + 标题 + 作者行（对应首页推荐卡片结构）。
class ThemeCard extends StatelessWidget {
  const ThemeCard({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final g = _cardGradients[index % _cardGradients.length];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipPath(
              clipper: const SquircleClipper(n: 5),
              child: SizedBox.expand(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: g,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '新',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFFFD5E5E),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '流光之境 ${index + 1}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Color(0xE6000000),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              CircleAvatar(radius: 8, backgroundColor: g[0]),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '设计师 · 小北',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0x8A000000),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
