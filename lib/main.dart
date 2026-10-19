import 'package:flutter/material.dart';

import 'home_page.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ThemeStore Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3482FF)),
        scaffoldBackgroundColor: const Color(0xFFF4F4F6),
      ),
      home: const HomePage(),
    );
  }
}
