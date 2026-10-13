/// 阅读书源自动生成器 —— 移植自 auto_source_generator.py 的 AutoSourceGenerator。
/// 编排流程：分析首页搜索功能 → 获取搜索结果 → 详情/目录页 → 正文页 → 规则提取 → 生成书源 JSON。
/// 通过回调向上层 UI 报告日志与状态，部分步骤失败时仍尝试生成部分书源。
library;

import 'dart:convert';

import 'package:html/parser.dart' as dom_parser;

import '../models/book_source.dart';
import 'html_rule_extractor.dart';
import 'http_service.dart';

typedef LogCallback = void Function(String message, {String? step});
typedef StatusCallback = void Function(String status);

class GenerateResult {
  final bool success;
  final String? sourceJson;
  final String error;

  GenerateResult({
    this.success = false,
    this.sourceJson,
    this.error = '',
  });
}

class SourceGenerator {
  final HttpService http = HttpService();
  final LogCallback? onLog;
  final StatusCallback? onStatus;

  SourceGenerator({this.onLog, this.onStatus});

  void log(String message, {String? step}) {
    final prefix = step != null && step.isNotEmpty ? '[$step] ' : '';
    onLog?.call('$prefix$message', step: step);
  }

  void step(String name) {
    log('');
    log('=' * 50);
    log('步骤: $name');
    log('=' * 50);
  }

  void logParams(String title, Map<String, dynamic> params) {
    log('${'=' * 20} $title ${'=' * 20}');
    params.forEach((k, v) => log('  $k: $v'));
  }

  String extractSiteName(String html, String url) {
    final m = RegExp(r'<title>(.*?)</title>',
            caseSensitive: false, dotAll: true)
        .firstMatch(html);
    if (m != null) {
      final title = m.group(1)!.trim();
      for (final sep in ['-', '_', '|', '—']) {
        if (title.contains(sep)) {
          return title.split(sep).first.trim();
        }
      }
      return title;
    }
    final host = Uri.tryParse(url)?.host ?? '';
    return host.replaceAll('www.', '').replaceAll('m.', '');
  }

  /// 分析首页搜索功能，生成阅读书源格式的搜索 URL。
  Future<Map<String, dynamic>> analyzeSearchFunction(String baseUrl,
      {String keyword = '我的'}) async {
    step('分析首页搜索功能');
    onStatus?.call('正在分析搜索功能...');

    final result = await http.fetchPage(baseUrl);
    if (!result.success) {
      return {'success': false, 'error': '获取首页失败: ${result.error}'};
    }

    final html = result.html;
    final charset = http.detectCharset(html, {});

    log('首页HTML长度: ${html.length} 字符');

    final doc = dom_parser.parse(html);

    // 查找包含搜索输入框的表单。
    String? formAction;
    String formMethod = 'GET';
    String paramName = 'keyword';
    final hiddenParams = <String, String>{};
    bool hasSearchInput = false;

    for (final form in doc.querySelectorAll('form')) {
      final action = form.attributes['action'] ?? '';
      final method = (form.attributes['method'] ?? 'GET').toUpperCase();
      final localHidden = <String, String>{};
      String? localInputName;
      bool localHasSearch = false;

      for (final input in form.querySelectorAll('input')) {
        final type = (input.attributes['type'] ?? 'text').toLowerCase();
        final name = input.attributes['name'] ?? '';
        final value = input.attributes['value'] ?? '';

        if (type == 'hidden' && name.isNotEmpty) {
          localHidden[name] = value;
        }
        if (type == 'text' &&
            ['search', 'key', 'q', 'keyword', 'searchkey', 'searchword', 'wd']
                .any(name.toLowerCase().contains)) {
          localInputName = name;
          localHasSearch = true;
        }
      }

      if (localHasSearch) {
        formAction = action;
        formMethod = method;
        if (localInputName != null) paramName = localInputName;
        hiddenParams.addAll(localHidden);
        hasSearchInput = true;
        break;
      }
    }

    if (!hasSearchInput || formAction == null) {
      return {'success': false, 'error': '未找到搜索表单'};
    }
    final actionUrl = formAction;

    final String searchUrlBase;
    if (actionUrl.startsWith('http')) {
      searchUrlBase = actionUrl;
    } else if (actionUrl.startsWith('/')) {
      final u = Uri.parse(baseUrl);
      searchUrlBase = '${u.scheme}://${u.host}$actionUrl';
    } else {
      searchUrlBase = baseUrl;
    }

    final searchUrl = _buildYueduSearchUrl(
        searchUrlBase, paramName, formMethod, hiddenParams, charset);

    final siteName = extractSiteName(html, baseUrl);

    logParams('搜索功能分析结果', {
      '网站名称': siteName,
      '编码': charset,
      '搜索URL': searchUrl,
      '搜索类型': formMethod,
      '参数名': paramName,
      '隐藏参数': hiddenParams,
    });

    return {
      'success': true,
      'site_name': siteName,
      'charset': charset,
      'search_url': searchUrl,
      'method': formMethod,
      'param_name': paramName,
      'hidden_params': hiddenParams,
      'full_html': html,
    };
  }

  String _buildYueduSearchUrl(String baseUrl, String paramName, String method,
      Map<String, String> hiddenParams, String charset) {
    if (method == 'POST') {
      final bodyParts = <String>['$paramName={{key}}'];
      hiddenParams.forEach((k, v) => bodyParts.add('$k=$v'));
      final bodyStr = bodyParts.join('&');
      final config = <String, dynamic>{'method': 'POST', 'body': bodyStr};
      if (charset.toUpperCase() == 'GBK' || charset.toUpperCase() == 'GB2312') {
        config['charset'] = 'gbk';
      }
      return '$baseUrl,${jsonEncode(config)}';
    } else {
      final params = <String>['$paramName={{key}}'];
      hiddenParams.forEach((k, v) => params.add('$k=$v'));
      final paramStr = params.join('&');
      if (baseUrl.contains('?')) {
        return '$baseUrl&$paramStr';
      }
      return '$baseUrl?$paramStr';
    }
  }

  /// 获取搜索结果并提取第一本书。
  Future<Map<String, dynamic>> fetchSearchResults(
    String searchUrl,
    String paramName, {
    String method = 'GET',
    String? charset,
    String keyword = '我的',
    Map<String, String>? hiddenParams,
  }) async {
    step('获取搜索结果并提取第一本书');
    onStatus?.call('正在获取搜索结果...');

    var actualUrl = searchUrl;
    var actualParamName = paramName;
    if (searchUrl.contains(',')) {
      final parts = searchUrl.split(',');
      actualUrl = parts.first;
      try {
        final config = jsonDecode(parts.sublist(1).join(',')) as Map<String, dynamic>;
        final body = config['body']?.toString() ?? '';
        final m = RegExp(r'(\w+)=\{\{key\}\}').firstMatch(body);
        if (m != null) actualParamName = m.group(1)!;
      } catch (_) {}
    }

    PageResult result;
    if (method == 'POST') {
      final postBody = {actualParamName: keyword};
      if (hiddenParams != null) postBody.addAll(hiddenParams);
      result = await http.postPage(actualUrl, postBody, charset: charset ?? 'UTF-8');
    } else {
      final params = <String>['$actualParamName=$keyword'];
      hiddenParams?.forEach((k, v) => params.add('$k=$v'));
      final paramStr = params.join('&');
      final url = actualUrl.contains('?')
          ? '$actualUrl&$paramStr'
          : '$actualUrl?$paramStr';
      result = await http.fetchPage(url, charset: charset);
    }

    if (!result.success) {
      return {'success': false, 'error': '搜索请求失败: ${result.error}'};
    }

    final html = result.html;
    log('搜索页HTML长度: ${html.length} 字符');

    final doc = dom_parser.parse(html);
    final links = <Map<String, String>>[];
    for (final a in doc.querySelectorAll('a')) {
      final href = (a.attributes['href'] ?? '').trim();
      final text = a.text.trim();
      links.add({'href': href, 'text': text});
    }
    log('找到 ${links.length} 个链接');

    final baseForAbs = result.url.isNotEmpty ? result.url : actualUrl;

    // 第一遍：优先选择文本包含关键词且非导航类链接。
    const navWords = ['书架', 'bookcase', '首页', '搜索', '排行', '最新', '书库', '求书'];
    for (final link in links) {
      final href = link['href']!.replaceAll(RegExp(r',+$'), '');
      final text = link['text']!;
      if (text.contains(keyword) &&
          !navWords.any(text.contains) &&
          href.isNotEmpty &&
          !href.toLowerCase().contains('javascript')) {
        final detailUrl = _toAbsoluteUrl(href, baseForAbs);
        logParams('搜索结果分析', {'书名': text, '详情页URL': detailUrl});
        return {
          'success': true,
          'book_name': text,
          'book_url': detailUrl,
          'detail_url': detailUrl,
          'html': html,
        };
      }
    }

    // 第二遍：备用——任意有效书籍链接。
    const exclude = ['首页', '搜索', '排行', '最新', '书库', '求书', '书架', '登录', '注册'];
    for (final link in links) {
      final href = link['href']!.replaceAll(RegExp(r',+$'), '');
      final text = link['text']!;
      if (text.length > 2 &&
          !exclude.any(text.contains) &&
          href.isNotEmpty &&
          !href.toLowerCase().contains('javascript') &&
          !href.toLowerCase().contains('bookcase')) {
        final detailUrl = _toAbsoluteUrl(href, baseForAbs);
        logParams('搜索结果分析（备用）', {'书名': text, '详情页URL': detailUrl});
        return {
          'success': true,
          'book_name': text,
          'book_url': detailUrl,
          'detail_url': detailUrl,
          'html': html,
        };
      }
    }
    return {'success': false, 'error': '未找到书籍链接'};
  }

  String _toAbsoluteUrl(String url, String baseUrl) {
    if (url.startsWith('http')) return url;
    try {
      final parsed = Uri.parse(baseUrl);
      if (url.startsWith('/')) {
        return '${parsed.scheme}://${parsed.host}$url';
      } else {
        final pathParts =
            parsed.path.split('/').where((p) => p.isNotEmpty).toList();
        if (pathParts.isNotEmpty) pathParts.removeLast();
        final path = pathParts.join('/');
        if (path.isNotEmpty) {
          return '${parsed.scheme}://${parsed.host}/$path/$url';
        }
        return '${parsed.scheme}://${parsed.host}/$url';
      }
    } catch (_) {
      return url;
    }
  }

  /// 获取详情页/目录页，必要时跳转到完整目录页。
  Future<Map<String, dynamic>> fetchTocPage(
      String baseUrl, String detailUrl, String charset) async {
    step('获取详情页/目录页');
    onStatus?.call('正在分析详情页/目录页...');

    log('获取详情页: $detailUrl');
    final result = await http.fetchPage(detailUrl, charset: charset);
    if (!result.success) {
      return {'success': false, 'error': '获取详情页失败: ${result.error}'};
    }
    final html = result.html;
    log('详情页HTML长度: ${html.length} 字符');

    try {
      final doc = dom_parser.parse(html);
      String? tocUrl;

      // 查找"查看完整目录"等链接。
      for (final a in doc.querySelectorAll('a')) {
        final href = (a.attributes['href'] ?? '').trim();
        final text = a.text.trim();
        if (text.contains('查看完整目录') ||
            text.contains('完整目录') ||
            text.contains('全部目录') ||
            text.contains('章节目录') ||
            (text.contains('目录') && text.length < 10) ||
            text.contains('点击阅读') ||
            text.contains('开始阅读')) {
          if (href.isNotEmpty && !href.toLowerCase().contains('javascript')) {
            tocUrl = href;
            log('找到目录链接: "$text" -> $href');
            break;
          }
        }
      }

      if (tocUrl == null) {
        final hasPagination = [
          'class="pagination"',
          'class="page-link"',
          'class="page"',
          'aria-label="Next"',
          'class="next"'
        ].any(html.contains);

        var chapterCount = 0;
        for (final a in doc.querySelectorAll('a')) {
          final text = a.text.trim();
          if (text.contains('章') || text.contains('第') || text.contains('话')) {
            chapterCount++;
          }
        }

        logParams('分页目录页检测', {'有分页导航': hasPagination, '章节链接数': chapterCount});

        if (hasPagination || chapterCount > 10) {
          log('判断当前页为目录页，无需跳转');
          return {
            'success': true,
            'html': html,
            'toc_url': detailUrl,
            'charset': result.charset.isNotEmpty ? result.charset : charset,
          };
        }
      }

      if (tocUrl != null) {
        String fullUrl;
        if (tocUrl.startsWith('http')) {
          fullUrl = tocUrl;
        } else if (tocUrl.startsWith('/')) {
          final u = Uri.parse(baseUrl);
          fullUrl = '${u.scheme}://${u.host}$tocUrl';
        } else {
          final base = detailUrl.substring(0, detailUrl.lastIndexOf('/') + 1);
          fullUrl = '$base$tocUrl';
        }
        log('从详情页跳转获取目录页: $fullUrl');
        final tocResult = await http.fetchPage(fullUrl, charset: charset);
        if (tocResult.success) {
          log('目录页获取成功，HTML长度: ${tocResult.html.length}');
          return {
            'success': true,
            'html': tocResult.html,
            'toc_url': fullUrl,
            'charset': tocResult.charset.isNotEmpty ? tocResult.charset : charset,
          };
        }
      }
      return {'success': false, 'error': '未找到目录页'};
    } catch (e) {
      return {'success': false, 'error': '获取目录页失败: $e'};
    }
  }

  /// 获取正文页（第一章）。
  Future<Map<String, dynamic>> fetchContentPage(
      String baseUrl, String tocHtml, String tocUrl, String charset) async {
    step('获取正文页（第一章）');
    onStatus?.call('正在获取第一章...');

    try {
      final doc = dom_parser.parse(tocHtml);
      for (final a in doc.querySelectorAll('a')) {
        final href = (a.attributes['href'] ?? '').trim();
        final text = a.text.trim();
        if (text.contains('第') &&
            (text.contains('章') || text.length < 30) &&
            href.isNotEmpty &&
            !href.toLowerCase().contains('javascript')) {
          final chapterUrl = _toAbsoluteUrl(href, tocUrl);
          logParams('正文页获取结果', {'章节名': text, '正文页URL': chapterUrl});

          final result = await http.fetchPage(chapterUrl, charset: charset);
          if (result.success) {
            log('正文页HTML长度: ${result.html.length} 字符');
            return {
              'success': true,
              'chapter_name': text,
              'content_url': chapterUrl,
              'first_chapter_url': chapterUrl,
              'html': result.html,
            };
          }
        }
      }
      return {'success': false, 'error': '未找到章节列表'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 生成阅读书源 JSON（中文不转义，2空格缩进）。
  String generateSource({
    required String siteName,
    required String baseUrl,
    required String charset,
    required String searchUrl,
    required Map<String, dynamic> searchRules,
    required Map<String, dynamic> bookInfoRules,
    required Map<String, dynamic> tocRules,
    required Map<String, dynamic> contentRules,
  }) {
    step('生成阅读书源JSON');
    final source = BookSource(
      bookSourceName: siteName,
      bookSourceUrl: baseUrl,
      searchUrl: searchUrl,
      ruleBookInfo: bookInfoRules,
      ruleContent: contentRules,
      ruleSearch: searchRules,
      ruleToc: tocRules,
    );
    return source.toPrettyJson();
  }

  /// 主流程：从网站 URL 自动生成阅读书源。
  Future<GenerateResult> generate(String url, {String keyword = '我的'}) async {
    log('=' * 50);
    log('开始阅读书源自动生成任务');
    logParams('输入参数', {'网站URL': url, '搜索关键词': keyword});

    final searchResult = await analyzeSearchFunction(url, keyword: keyword);
    if (!(searchResult['success'] as bool)) {
      final err = searchResult['error']?.toString() ?? '未知错误';
      onStatus?.call('搜索分析失败: $err');
      return GenerateResult(success: false, error: err);
    }

    final siteName = searchResult['site_name'] as String;
    final charset = searchResult['charset'] as String;
    final searchUrl = searchResult['search_url'] as String;
    final searchMethod = searchResult['method'] as String;
    final hiddenParams =
        Map<String, String>.from(searchResult['hidden_params'] as Map? ?? {});
    final paramName = searchResult['param_name'] as String;

    onStatus?.call('✓ 搜索功能分析完成，正在获取搜索结果...');

    final detailResult = await fetchSearchResults(
      searchUrl,
      paramName,
      method: searchMethod,
      charset: charset,
      keyword: keyword,
      hiddenParams: hiddenParams,
    );
    if (!(detailResult['success'] as bool)) {
      final err = detailResult['error']?.toString() ?? '未知错误';
      onStatus?.call('获取详情页失败: $err');
      final partial = _generatePartialSource(
        siteName: siteName,
        baseUrl: url,
        charset: charset,
        searchUrl: searchUrl,
        searchHtml: detailResult['html'] as String?,
      );
      return GenerateResult(success: true, sourceJson: partial, error: err);
    }

    final detailUrl = detailResult['book_url'] as String;
    final searchHtml = detailResult['html'] as String;
    onStatus?.call('✓ 找到书籍: ${detailResult["book_name"]}，正在分析详情页...');

    final tocResult = await fetchTocPage(url, detailUrl, charset);
    if (!(tocResult['success'] as bool)) {
      final err = tocResult['error']?.toString() ?? '未知错误';
      onStatus?.call('获取目录页失败: $err');
      final partial = _generatePartialSource(
        siteName: siteName,
        baseUrl: url,
        charset: charset,
        searchUrl: searchUrl,
        searchHtml: searchHtml,
        detailHtml: detailResult['html'] as String?,
      );
      return GenerateResult(success: true, sourceJson: partial, error: err);
    }

    final tocUrl = tocResult['toc_url'] as String;
    final tocHtml = tocResult['html'] as String;
    onStatus?.call('✓ 目录页获取完成，正在获取第一章...');

    final contentResult = await fetchContentPage(url, tocHtml, tocUrl, charset);
    if (!(contentResult['success'] as bool)) {
      final err = contentResult['error']?.toString() ?? '未知错误';
      onStatus?.call('获取正文页失败: $err');
      final partial = _generatePartialSource(
        siteName: siteName,
        baseUrl: url,
        charset: charset,
        searchUrl: searchUrl,
        searchHtml: searchHtml,
        tocHtml: tocHtml,
      );
      return GenerateResult(success: true, sourceJson: partial, error: err);
    }

    final contentHtml = contentResult['html'] as String;
    onStatus?.call('✓ 正文页获取完成: ${contentResult["chapter_name"]}，正在分析规则...');

    step('分析各页面规则');

    final searchRules =
        JsoupRuleExtractor(searchHtml, baseUrl: url).extractSearchRules();
    log('搜索页规则: ${jsonEncode(searchRules)}');

    final bookInfoRules = JsoupRuleExtractor(
            detailResult['html'] as String? ?? tocHtml, baseUrl: url)
        .extractBookInfoRules();
    log('详情页规则: ${jsonEncode(bookInfoRules)}');

    final tocPair =
        JsoupRuleExtractor(tocHtml, baseUrl: url).extractTocRules();
    final tocRules = tocPair.$1;
    final isReverse = tocPair.$2;
    log('目录页规则: ${jsonEncode(tocRules)}');
    log('章节顺序: ${isReverse ? '倒序' : '正序'}');

    final contentRules =
        JsoupRuleExtractor(contentHtml, baseUrl: url).extractContentRules();
    log('正文页规则: ${jsonEncode(contentRules)}');

    onStatus?.call('✓ 规则分析完成，正在生成书源...');

    final source = generateSource(
      siteName: siteName,
      baseUrl: url,
      charset: charset,
      searchUrl: searchUrl,
      searchRules: searchRules,
      bookInfoRules: bookInfoRules,
      tocRules: tocRules,
      contentRules: contentRules,
    );

    onStatus?.call('✓ 书源生成完成！');
    log('');
    log('=' * 50);
    log('阅读书源自动生成任务完成！');
    log('=' * 50);

    return GenerateResult(success: true, sourceJson: source);
  }

  /// 生成部分书源——即使某些步骤失败也能输出可用结果。
  String _generatePartialSource({
    required String siteName,
    required String baseUrl,
    required String charset,
    required String searchUrl,
    String? searchHtml,
    String? detailHtml,
    String? tocHtml,
  }) {
    Map<String, dynamic> searchRules = {};
    Map<String, dynamic> bookInfoRules = {
      'init': '', 'name': '', 'author': '', 'coverUrl': '', 'intro': '',
      'kind': '', 'lastChapter': '', 'wordCount': '', 'tocUrl': '',
    };
    Map<String, dynamic> tocRules = {
      'chapterList': '', 'chapterName': '', 'chapterUrl': '',
      'nextTocUrl': '', 'preUpdateJs': '',
    };
    Map<String, dynamic> contentRules = {
      'content': '', 'nextContentUrl': '', 'replaceRegex': '', 'webJs': '', 'sourceRegex': '',
    };

    if (searchHtml != null && searchHtml.isNotEmpty) {
      searchRules =
          JsoupRuleExtractor(searchHtml, baseUrl: baseUrl).extractSearchRules();
    }
    if (detailHtml != null && detailHtml.isNotEmpty) {
      bookInfoRules =
          JsoupRuleExtractor(detailHtml, baseUrl: baseUrl).extractBookInfoRules();
    }
    if (tocHtml != null && tocHtml.isNotEmpty) {
      final pair = JsoupRuleExtractor(tocHtml, baseUrl: baseUrl).extractTocRules();
      tocRules = pair.$1;
    }

    return generateSource(
      siteName: siteName,
      baseUrl: baseUrl,
      charset: charset,
      searchUrl: searchUrl,
      searchRules: searchRules,
      bookInfoRules: bookInfoRules,
      tocRules: tocRules,
      contentRules: contentRules,
    );
  }
}
