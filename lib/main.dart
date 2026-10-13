/// 阅读书源工具 —— Flutter Android 入口。
/// 整合 auto_source_generator（书源自动生成）与 xin-verify-book-source（书源校验）。
library;

import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YueduSourceApp());
}

class YueduSourceApp extends StatelessWidget {
  const YueduSourceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '阅读书源工具',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3F51B5),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF3F51B5),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}
