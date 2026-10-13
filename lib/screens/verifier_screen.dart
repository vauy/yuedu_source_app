/// 书源校验页：输入书源文件路径/直链 URL，并发校验可访问性，去重，导出有效/无效书源。
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/source_verifier.dart';
import '../utils/file_saver.dart';
import '../widgets/log_console.dart';

class VerifierScreen extends StatefulWidget {
  const VerifierScreen({super.key});

  @override
  State<VerifierScreen> createState() => _VerifierScreenState();
}

class _VerifierScreenState extends State<VerifierScreen> {
  final _sourceController = TextEditingController();
  final _workersController = TextEditingController(text: '16');
  final _timeoutController = TextEditingController(text: '3');
  final _logLines = <String>[];
  double _progress = 0;
  String _progressText = '';
  bool _dedup = true;
  bool _running = false;
  VerifyResult? _result;

  @override
  void dispose() {
    _sourceController.dispose();
    _workersController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  void _log(String message) {
    if (!mounted) return;
    setState(() => _logLines.add(message));
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
      );
      if (res != null && res.files.single.path != null) {
        setState(() => _sourceController.text = res.files.single.path!);
      }
    } catch (e) {
      _showSnack('选择文件失败: $e');
    }
  }

  Future<void> _startVerify() async {
    final src = _sourceController.text.trim();
    if (src.isEmpty) {
      _showSnack('请输入书源文件路径或直链URL');
      return;
    }
    final workers = int.tryParse(_workersController.text.trim()) ?? 16;
    final timeout = int.tryParse(_timeoutController.text.trim()) ?? 3;

    setState(() {
      _logLines.clear();
      _progress = 0;
      _progressText = '';
      _result = null;
      _running = true;
    });

    _log('欢迎使用书源校验工具（VerifyBookSource v2.0 · Flutter版）');
    _log('源: $src');
    _log('并发线程: $workers | 超时: ${timeout}s | 去重: $_dedup');
    _log('-' * 16);

    final verifier = SourceVerifier(src, onLog: _log);

    try {
      final res = await verifier.checkbooks(
        workers: workers,
        dedupEnabled: _dedup,
        onProgress: (progress, done, total) {
          if (!mounted) return;
          setState(() {
            _progress = progress;
            _progressText = '$done / $total';
          });
        },
      );

      _log('-' * 16);
      _log('成果报表');
      _log('书源总数：${res.total}');
      _log('有效书源数：${res.good.length}');
      _log('无效书源数：${res.error.length}');
      _log('重复书源数：${res.duplicateCount}');
      _log('耗时：${(res.elapsed.inMilliseconds / 1000.0).toStringAsFixed(2)}秒');

      if (mounted) {
        setState(() => _result = res);
      }
    } catch (e) {
      _log('发生错误: $e');
      _showSnack('校验失败: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
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
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _sourceController,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: '书源：本地文件路径 / 直链URL',
                      prefixIcon: const Icon(Icons.source_outlined),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: '选择本地文件',
                        icon: const Icon(Icons.folder_open),
                        onPressed: _pickFile,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _workersController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '并发线程',
                            prefixIcon: Icon(Icons.speed),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _timeoutController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '超时(秒)',
                            prefixIcon: Icon(Icons.timer),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('重复书源去重'),
                    value: _dedup,
                    onChanged: _running
                        ? null
                        : (v) => setState(() => _dedup = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _running ? null : _startVerify,
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.playlist_add_check),
                label: const Text('开始校验'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 进度条
          if (_running || _progress > 0) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 18,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: Text(
                    '${(_progress * 100).toStringAsFixed(2)}%\n$_progressText',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          // 报表
          if (_result != null) _buildReport(theme),
          const SizedBox(height: 8),
          Expanded(
            child: LogConsole(
              title: '运行日志',
              lines: _logLines,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReport(ThemeData theme) {
    final r = _result!;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('成果报表',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _reportRow('书源总数', r.total),
            _reportRow('有效书源', r.good.length, color: Colors.green),
            _reportRow('无效书源', r.error.length, color: Colors.red),
            _reportRow('重复书源', r.duplicateCount),
            _reportRow('耗时',
                '${(r.elapsed.inMilliseconds / 1000.0).toStringAsFixed(2)}秒'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: r.good.isEmpty
                      ? null
                      : () => FileSaver.shareJson(
                          'good.json', r.good,
                          subject: '有效书源 ${r.good.length} 条'),
                  icon: const Icon(Icons.download),
                  label: const Text('导出有效书源'),
                ),
                OutlinedButton.icon(
                  onPressed: r.error.isEmpty
                      ? null
                      : () => FileSaver.shareJson(
                          'error.json', r.error,
                          subject: '无效书源 ${r.error.length} 条'),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('导出无效书源'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportRow(String label, dynamic value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text('$value',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
