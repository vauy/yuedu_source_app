/// 可复用的滚动日志控制台：自动滚动到底部，等宽字体，带时间戳。
library;

import 'package:flutter/material.dart';

class LogConsole extends StatefulWidget {
  final List<String> lines;
  final String? title;

  const LogConsole({super.key, required this.lines, this.title});

  @override
  State<LogConsole> createState() => _LogConsoleState();
}

class _LogConsoleState extends State<LogConsole> {
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(covariant LogConsole oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines.length != oldWidget.lines.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  void _scrollToEnd() {
    if (_controller.hasClients) {
      _controller.animateTo(
        _controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final view = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: widget.lines.isEmpty
          ? Center(
              child: Text(
                '暂无日志',
                style: TextStyle(color: Colors.grey.shade500, fontFamily: 'monospace'),
              ),
            )
          : ListView.builder(
              controller: _controller,
              padding: const EdgeInsets.all(8),
              itemCount: widget.lines.length,
              itemBuilder: (context, index) {
                final line = widget.lines[index];
                return SelectableText(
                  line,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.35,
                    color: Color(0xFFD6D6D6),
                  ),
                );
              },
            ),
    );

    if (widget.title == null) return view;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(widget.title!,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
        Expanded(child: view),
      ],
    );
  }
}
