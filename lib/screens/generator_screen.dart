/// 书源生成页：输入网站 URL 与关键词，自动分析并生成阅读3.0书源 JSON。
library;

import 'package:flutter/material.dart';

import '../services/source_generator.dart';
import '../utils/file_saver.dart';
import '../widgets/log_console.dart';

class GeneratorScreen extends StatefulWidget {
  const GeneratorScreen({super.key});

  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen> {
  final _urlController = TextEditingController();
  final _keywordController = TextEditingController(text: '我的');
  final _logLines = <String>[];
  String _status = '就绪';
  String _resultJson = '';
  bool _running = false;

  @override
  void dispose() {
    _urlController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }

  void _log(String message, {String? step}) {
    final prefix = step != null && step.isNotEmpty ? '[$step] ' : '';
    setState(() {
      _logLines.add('[$_timestamp()] [YueduSource] $prefix$message');
    });
  }

  void _clearLog() {
    setState(() {
      _logLines.clear();
      _status = '就绪';
    });
  }

  void _setRunning(bool v) {
    if (!mounted) return;
    setState(() => _running = v);
  }

  Future<void> _startGenerate() async {
    final url = _urlController.text.trim();
    final keyword = _keywordController.text.trim().isEmpty
        ? '我的'
        : _keywordController.text.trim();

    if (url.isEmpty) {
      _showSnack('请输入网站URL');
      return;
    }

    setState(() {
      _logLines.clear();
      _resultJson = '';
      _status = '开始生成...';
    });
    _setRunning(true);

    final generator = SourceGenerator(
      onLog: _log,
      onStatus: (s) {
        if (mounted) setState(() => _status = s);
      },
    );

    try {
      final result = await generator.generate(url, keyword: keyword);
      if (mounted) {
        setState(() {
          if (result.sourceJson != null && result.sourceJson!.isNotEmpty) {
            _resultJson = result.sourceJson!;
            _status = result.success ? '✓ 书源生成完成！' : '⚠ 已生成部分书源：${result.error}';
          } else {
            _status = '✗ 生成失败：${result.error}';
          }
        });
      }
    } catch (e) {
      _log('发生错误: $e');
      if (mounted) setState(() => _status = '✗ 发生错误: $e');
    } finally {
      _setRunning(false);
    }
  }

  Future<void> _saveSource() async {
    if (_resultJson.isEmpty) return;
    final name = _sourceName() ;
    await FileSaver.shareString('$name.json', _resultJson, subject: '$name 书源');
  }

  String _sourceName() {
    final m = RegExp(r'"bookSourceName"\s*:\s*"([^"]*)"').firstMatch(_resultJson);
    final n = m?.group(1) ?? 'booksource';
    return n.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 输入区
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: '网站URL',
                      hintText: '输入小说网站首页URL',
                      prefixIcon: Icon(Icons.public),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _keywordController,
                    decoration: const InputDecoration(
                      labelText: '搜索关键词',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 按钮区
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _running ? null : _startGenerate,
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: const Text('开始生成'),
              ),
              OutlinedButton.icon(
                onPressed: _clearLog,
                icon: const Icon(Icons.delete_outline),
                label: const Text('清空日志'),
              ),
              OutlinedButton.icon(
                onPressed: (_resultJson.isEmpty || _running)
                    ? null
                    : _saveSource,
                icon: const Icon(Icons.save_alt),
                label: const Text('保存书源'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 状态
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _status,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          // 日志 + 结果
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _resultJson.isEmpty
                  ? LogConsole(
                      key: const ValueKey('log'),
                      title: '运行日志',
                      lines: _logLines,
                    )
                  : Column(
                      key: const ValueKey('result'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 4,
                          child: LogConsole(lines: _logLines, title: '运行日志'),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          flex: 5,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text('生成的阅读书源JSON',
                                      style: TextStyle(
                                        color: Colors.grey.shade300,
                                        fontWeight: FontWeight.bold,
                                      )),
                                ),
                                const Divider(height: 1, color: Colors.white12),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: SelectableText(
                                        _resultJson,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          color: Color(0xFFD6D6D6),
                                        ),
                                      ),
                                    ),
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
        ],
      ),
    );
  }
}
