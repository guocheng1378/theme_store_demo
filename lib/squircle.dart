import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 超椭圆(squircle)路径 —— 对应包内 buttonCapsuleRadius / GL 几何体系。
/// n=2 是正圆，n=5 是 HyperOS 连续曲率观感（卡片 / Banner 圆角用它）。
Path squirclePath(Size size, {double n = 5}) {
  const steps = 96;
  final a = size.width / 2;
  final b = size.height / 2;
  final path = Path();
  for (var i = 0; i <= steps; i++) {
    final t = i / steps * 2 * math.pi;
    final c = math.cos(t);
    final s = math.sin(t);
    final x = a * (c < 0 ? -1 : 1) * math.pow(c.abs(), 2 / n).toDouble();
    final y = b * (s < 0 ? -1 : 1) * math.pow(s.abs(), 2 / n).toDouble();
    if (i == 0) {
      path.moveTo(a + x, b + y);
    } else {
      path.lineTo(a + x, b + y);
    }
  }
  return path..close();
}

class SquircleClipper extends CustomClipper<Path> {
  const SquircleClipper({this.n = 5});

  final double n;

  @override
  Path getClip(Size size) => squirclePath(size, n: n);

  @override
  bool shouldReclip(SquircleClipper old) => old.n != n;
}
