/// 书源校验器 —— 移植自 xin-verify-book-source/book/book.py。
/// 原理：检验书源的 bookSourceUrl 是否能打开（HTTP 200）。
/// 功能：自定义并发线程数、支持本地文件/直链 URL、重复书源去重、进度回调。
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

typedef ProgressCallback = void Function(double progress, int done, int total);
typedef LogCallback = void Function(String message);

class VerifyResult {
  final List<Map<String, dynamic>> good;
  final List<Map<String, dynamic>> error;
  final int total;
  final int duplicateCount;
  final Duration elapsed;

  VerifyResult({
    required this.good,
    required this.error,
    required this.total,
    required this.duplicateCount,
    required this.elapsed,
  });
}

class SourceVerifier {
  final String source;
  final LogCallback? onLog;

  SourceVerifier(this.source, {this.onLog});

  String? recogType(String file) {
    if (file.startsWith('http')) return 'url';
    if (File(file).existsSync()) {
      return file.substring(file.lastIndexOf('.'));
    }
    return null;
  }

  /// 读取书源列表：支持本地文件与直链 URL。
  Future<List<Map<String, dynamic>>> jsonToBooks() async {
    if (source.startsWith('http')) {
      final client = _insecureClient();
      try {
        final response = await client.get(Uri.parse(source));
        final body = response.body;
        final data = jsonDecode(body);
        return _normalize(data);
      } finally {
        client.close();
      }
    } else {
      final f = File(source);
      final data = jsonDecode(await f.readAsString());
      return _normalize(data);
    }
  }

  List<Map<String, dynamic>> _normalize(dynamic data) {
    if (data is List) {
      return data
          .map((e) => e is Map<String, dynamic>
              ? e
              : Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return [];
  }

  /// 校验单条书源：bookSourceUrl 返回 200 视为有效。
  Future<bool> check(Map<String, dynamic> book, {int timeout = 3}) async {
    final headers = {
      'user-agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.58'
    };
    final client = _insecureClient();
    try {
      final url = book['bookSourceUrl']?.toString() ?? '';
      if (url.isEmpty) return false;
      final response = await client
          .get(Uri.parse(url), headers: headers)
          .timeout(Duration(seconds: timeout));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// 并发校验全部书源，按 workers 控制并发度，实时回调进度。
  Future<VerifyResult> checkbooks({
    int workers = 16,
    bool dedupEnabled = false,
    ProgressCallback? onProgress,
  }) async {
    final books = await jsonToBooks();
    final total = books.length;
    final good = <Map<String, dynamic>>[];
    final error = <Map<String, dynamic>>[];
    var done = 0;
    final stopwatch = Stopwatch()..start();

    if (total == 0) {
      stopwatch.stop();
      return VerifyResult(
        good: good,
        error: error,
        total: total,
        duplicateCount: 0,
        elapsed: stopwatch.elapsed,
      );
    }

    final concurrency = workers < 1 ? 1 : (workers > total ? total : workers);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= total) break;
        final ok = await check(books[i]);
        if (ok) {
          good.add(books[i]);
        } else {
          error.add(books[i]);
        }
        done++;
        onProgress?.call(done / total, done, total);
      }
    }

    await Future.wait(
      List.generate(concurrency, (_) => worker()),
    );

    var duplicateCount = 0;
    final goodOut = dedupEnabled ? dedup(good) : good;
    if (dedupEnabled) {
      duplicateCount = good.length - goodOut.length;
    }

    stopwatch.stop();
    return VerifyResult(
      good: goodOut,
      error: error,
      total: total,
      duplicateCount: duplicateCount,
      elapsed: stopwatch.elapsed,
    );
  }

  /// 按 bookSourceUrl 去重，保留首次出现。
  List<Map<String, dynamic>> dedup(List<Map<String, dynamic>> books) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final b in books) {
      final url = b['bookSourceUrl']?.toString() ?? '';
      if (seen.add(url)) {
        out.add(b);
      }
    }
    return out;
  }

  /// 忽略 SSL 证书错误的 HttpClient（对应 Python requests verify=False）。
  http.Client _insecureClient() {
    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return IOClient(httpClient);
  }
}
