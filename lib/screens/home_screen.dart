/// 主页：底部导航在「书源生成」与「书源校验」两个功能间切换。
library;

import 'package:flutter/material.dart';

import 'generator_screen.dart';
import 'verifier_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.auto_fix_high_outlined),
      selectedIcon: Icon(Icons.auto_fix_high),
      label: '书源生成',
    ),
    NavigationDestination(
      icon: Icon(Icons.fact_check_outlined),
      selectedIcon: Icon(Icons.fact_check),
      label: '书源校验',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读书源工具'),
        centerTitle: true,
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          GeneratorScreen(),
          VerifierScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
      ),
    );
  }
}
