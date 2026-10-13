/// 网络请求模块 —— 对应 auto_source_generator 中的 fetch_page / post_page / detect_charset 等。
/// 负责模拟移动端请求、自动检测编码（UTF-8/GBK/GB2312）、检测 JS 重定向、自动重试。
library;

import 'dart:convert';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:http/http.dart' as http;

class PageResult {
  final bool success;
  final String html;
  final String charset;
  final String url;
  final String error;

  PageResult({
    this.success = false,
    this.html = '',
    this.charset = 'UTF-8',
    this.url = '',
    this.error = '',
  });
}

class HttpService {
  /// 移动端 UA，降低被识别为爬虫的概率。
  Map<String, String> getHeaders(String? url) {
    final headers = {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Accept-Encoding': 'gzip, deflate, br',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
    };
    if (url != null) {
      final host = Uri.tryParse(url)?.host;
      if (host != null && host.isNotEmpty) headers['Host'] = host;
    }
    return headers;
  }

  /// 检测 JavaScript 重定向（window.location = ...）。
  String? checkJsRedirect(String html, String baseUrl) {
    if (html.length < 500) {
      final m = RegExp(
        r'''window\.location(?:\.href)?\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(html);
      if (m != null) {
        final path = m.group(1)!;
        if (path.startsWith('http')) {
          return path;
        } else if (path.startsWith('/')) {
          final u = Uri.parse(baseUrl);
          return '${u.scheme}://${u.host}$path';
        } else {
          return '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/$path';
        }
      }
    }
    return null;
  }

  /// 编码检测：优先 Content-Type 响应头，其次 HTML meta 标签，统一返回 GB2312 或 UTF-8。
  String detectCharset(String html, Map<String, String> headers) {
    String? detected;
    final contentType = headers['content-type'] ?? headers['Content-Type'] ?? '';
    final ctMatch = RegExp(r'charset=([^\s;]+)', caseSensitive: false)
        .firstMatch(contentType);
    if (ctMatch != null) detected = ctMatch.group(1)!.trim().toLowerCase();

    if (detected == null) {
      final metaMatch = RegExp(
        r'''<meta[^>]+charset=["']?([^"'\s >]+)''',
        caseSensitive: false,
      ).firstMatch(html);
      if (metaMatch != null) detected = metaMatch.group(1)!.trim().toLowerCase();
    }

    if (detected != null && (detected.contains('gbk') || detected.contains('gb2312'))) {
      return 'GB2312';
    }
    return 'UTF-8';
  }

  /// 按 charset 解码字节流，GBK 系列使用 gbk_codec，失败回退容错 UTF-8。
  String decodeBytes(List<int> bytes, String charset) {
    final cs = charset.toUpperCase();
    if (cs == 'GB2312' || cs == 'GBK') {
      try {
        return gbk_bytes.decode(bytes);
      } catch (_) {
        return utf8.decode(bytes, allowMalformed: true);
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// GET 请求页面，支持自动重试、JS 重定向跟随。
  Future<PageResult> fetchPage(String url, {String? charset, int maxRetries = 3}) async {
    var currentUrl = url;
    for (var retry = 0; retry < maxRetries; retry++) {
      try {
        final response = await http
            .get(Uri.parse(currentUrl), headers: getHeaders(currentUrl))
            .timeout(const Duration(seconds: 15));

        // 先用容错 UTF-8 预解码，便于读取 meta 标签中的 charset。
        final prelim = utf8.decode(response.bodyBytes, allowMalformed: true);
        final detected = charset ?? detectCharset(prelim, response.headers);
        // 若为 GBK 系，按正确编码重新解码；否则直接使用预解码结果。
        final html = (detected.toUpperCase() == 'GB2312' ||
                detected.toUpperCase() == 'GBK')
            ? decodeBytes(response.bodyBytes, detected)
            : prelim;

        final redirectUrl = checkJsRedirect(html, currentUrl);
        if (redirectUrl != null) {
          currentUrl = redirectUrl;
          continue;
        }

        if (html.length < 500) {
          // 异常响应，重试。
          continue;
        }

        return PageResult(
          success: true,
          html: html,
          charset: detected,
          url: currentUrl,
        );
      } catch (e) {
        if (retry == maxRetries - 1) {
          return PageResult(success: false, error: e.toString());
        }
      }
    }
    return PageResult(success: false, error: '重试次数过多');
  }

  /// POST 请求，按 charset 编码表单（GBK 站点也能正确提交搜索关键词）。
  Future<PageResult> postPage(String url, Map<String, String> data,
      {String charset = 'UTF-8'}) async {
    try {
      final headers = getHeaders(url);
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
      final origin = Uri.parse(url);
      headers['Origin'] = '${origin.scheme}://${origin.host}';
      headers['Referer'] = url;

      final cs = charset.toUpperCase();
      http.Response response;
      if (cs == 'GBK' || cs == 'GB2312') {
        // 手动构建 GBK 编码的表单字节，避免默认 latin1 截断中文。
        final body = <int>[];
        var first = true;
        data.forEach((k, v) {
          if (!first) body.add(0x26); // '&'
          first = false;
          body.addAll(gbk_bytes.encode(k));
          body.add(0x3D); // '='
          body.addAll(gbk_bytes.encode(v));
        });
        response = await http
            .post(Uri.parse(url), headers: headers, body: body)
            .timeout(const Duration(seconds: 15));
      } else {
        response = await http
            .post(Uri.parse(url), headers: headers, body: data)
            .timeout(const Duration(seconds: 15));
      }

      final detected = charset;
      final html = decodeBytes(response.bodyBytes, detected);
      return PageResult(
        success: true,
        html: html,
        charset: detected,
        url: url,
      );
    } catch (e) {
      return PageResult(success: false, error: e.toString());
    }
  }
}
