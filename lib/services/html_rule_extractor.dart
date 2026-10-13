/// JSOUP 规则提取器 —— 移植自 auto_source_generator.py 的 JSOUPRuleExtractor。
/// 通过分析 HTML 结构特征，自动生成符合阅读3.0规范的 JSOUP 规则字符串。
/// 规则语法：类型.名称.位置@获取内容（如 class.bookname@tag.a@text）。
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as dom_parser;

/// 解析后的扁平元素记录，模拟 Python HTMLParser 收集的元素结构。
class HtmlEl {
  final String tag;
  final String classStr; // 完整 class 属性（用于 substring 匹配，与 Python 行为一致）
  final String id;
  final String href;
  final String src;
  final String dataSrc;
  String text; // 累积的文本内容
  final int depth;

  HtmlEl({
    required this.tag,
    required this.classStr,
    required this.id,
    required this.href,
    required this.src,
    required this.dataSrc,
    required this.text,
    required this.depth,
  });

  /// class 的第一个 token（Python: el['class'].split()[0]）。
  String get firstClass {
    final t = classStr.trim().split(RegExp(r'\s+'));
    return t.isEmpty || t.first.isEmpty ? '' : t.first;
  }
}

/// 一组规则匹配模式：(类型, 值)，类型为 'class' | 'id' | 'tag'。
typedef RulePattern = (String, String);

class JsoupRuleExtractor {
  final String html;
  final String baseUrl;
  late final List<HtmlEl> elements;

  JsoupRuleExtractor(this.html, {this.baseUrl = ''}) {
    elements = _parseElements();
  }

  /// 解析 HTML 元素结构：前序遍历 DOM，模拟 SAX 的 start/end/data 回调，
  /// 使 text 字段累积行为与 Python html.parser 完全一致。
  List<HtmlEl> _parseElements() {
    final result = <HtmlEl>[];
    final doc = dom_parser.parse(html);
    final stack = <HtmlEl>[];

    void walk(dom.Node node, int depth) {
      if (node is dom.Element) {
        final tag = (node.localName ?? '').toLowerCase();
        final el = HtmlEl(
          tag: tag,
          classStr: node.attributes['class'] ?? '',
          id: node.attributes['id'] ?? '',
          href: node.attributes['href'] ?? '',
          src: node.attributes['src'] ?? '',
          dataSrc: node.attributes['data-src'] ?? '',
          text: '',
          depth: depth,
        );
        result.add(el);
        stack.add(el);
        for (final child in node.nodes) {
          walk(child, depth + 1);
        }
        stack.removeLast();
      } else if (node is dom.Text) {
        final data = node.text.trim();
        if (data.isNotEmpty && stack.isNotEmpty) {
          stack.last.text += ' $data';
        }
      }
    }

    for (final node in doc.nodes) {
      walk(node, 0);
    }
    return result;
  }

  String _buildJsoupRule(HtmlEl el) {
    if (el.id.isNotEmpty) {
      return 'id.${el.id}';
    } else if (el.classStr.isNotEmpty) {
      return 'class.${el.firstClass}';
    } else {
      return 'tag.${el.tag}';
    }
  }

  // ===================== 搜索页规则 =====================

  String findBookListContainer() {
    final containers = <List<String>>[
      ['ul', 'txt-list'],
      ['div', 'result-list'],
      ['div', 'book-list'],
      ['ul', 'book-list'],
      ['div', 'list'],
      ['ul', 'list'],
      ['table', ''],
      ['div', 'item-list'],
      ['div', 'search-result'],
    ];

    for (final c in containers) {
      final tag = c[0];
      final cls = c[1];
      for (final el in elements) {
        if (el.tag != tag) continue;
        if (cls.isNotEmpty && el.classStr.contains(cls)) {
          return _buildJsoupRule(el);
        } else if (cls.isEmpty && tag == 'table') {
          return 'table@tag.tr';
        }
      }
    }
    return 'tag.li';
  }

  Map<String, dynamic> extractSearchRules() {
    return {
      'bookList': findBookListContainer(),
      'name': _findNameRule(),
      'author': _findAuthorRule(),
      'coverUrl': _findCoverRule(),
      'bookUrl': _findBookUrlRule(),
      'lastChapter': _findLastChapterRule(),
      'kind': _findKindRule(),
      'intro': _findIntroRule(),
      'wordCount': '',
    };
  }

  String _findNameRule() {
    final patterns = <RulePattern>[
      ('class', 'bookname'),
      ('class', 'name'),
      ('class', 'title'),
      ('class', 's2'),
      ('class', 'book-name'),
      ('tag', 'h3'),
      ('tag', 'h4'),
    ];
    for (final (type_, value) in patterns) {
      for (final el in elements) {
        if (type_ == 'class' && el.classStr.contains(value)) {
          if (el.tag == 'a') {
            return 'class.$value@text';
          } else {
            return 'class.$value@tag.a@text';
          }
        } else if (type_ == 'tag' && el.tag == value) {
          if (el.text.isNotEmpty && el.text.trim().length < 50) {
            return 'tag.$value@tag.a@text';
          }
        }
      }
    }
    return '';
  }

  String _findAuthorRule() {
    final patterns = <RulePattern>[
      ('class', 'author'),
      ('class', 's4'),
      ('class', 'au'),
      ('class', 'writer'),
      ('class', 'zz'),
    ];
    for (final (type_, value) in patterns) {
      for (final el in elements) {
        if (type_ == 'class' && el.classStr.contains(value)) {
          final text = el.text.trim();
          if (text.contains('作者') || text.length < 20) {
            var rule = 'class.$value@text';
            if (text.contains('作者')) {
              rule += '##作者：##';
            }
            return rule;
          }
        }
      }
    }
    return '';
  }

  String _findCoverRule() {
    for (final el in elements) {
      if (el.tag == 'img') {
        if (el.src.isNotEmpty &&
            (el.classStr.contains('cover') || el.src.contains('cover'))) {
          return 'img@src';
        } else if (el.dataSrc.isNotEmpty) {
          return 'img@data-src';
        }
      }
    }
    for (final el in elements) {
      if (el.tag == 'img' && el.src.isNotEmpty) {
        return 'img@src';
      }
    }
    return '';
  }

  String _findBookUrlRule() {
    for (final el in elements) {
      if (el.tag == 'a' && el.href.isNotEmpty) {
        final text = el.text.trim();
        if (text.isNotEmpty &&
            text.length < 50 &&
            !el.href.toLowerCase().contains('javascript')) {
          if (el.href.contains('/book/') ||
              el.href.contains('/novel/') ||
              el.href.contains('/xiaoshuo/')) {
            return 'tag.a@href';
          }
        }
      }
    }
    return 'tag.a@href';
  }

  String _findLastChapterRule() {
    final patterns = <RulePattern>[
      ('class', 's3'),
      ('class', 'last'),
      ('class', 'chapter'),
      ('class', 'new'),
      ('class', 'update'),
    ];
    for (final (type_, value) in patterns) {
      for (final el in elements) {
        if (type_ == 'class' && el.classStr.contains(value)) {
          if (el.tag == 'a') {
            return 'class.$value@tag.a@text';
          } else {
            final text = el.text.trim();
            if (text.contains('章') || text.contains('节')) {
              return 'class.$value@text';
            }
          }
        }
      }
    }
    return '';
  }

  String _findKindRule() {
    final patterns = <RulePattern>[
      ('class', 's1'),
      ('class', 'kind'),
      ('class', 'category'),
      ('class', 'type'),
      ('class', 'sort'),
    ];
    for (final (type_, value) in patterns) {
      for (final el in elements) {
        if (type_ == 'class' && el.classStr.contains(value)) {
          final text = el.text.trim();
          if (text.isNotEmpty && text.length < 20) {
            var rule = 'class.$value@text';
            if (text.contains('[') || text.contains('【')) {
              rule += r'##[\[\]【】]##';
            }
            return rule;
          }
        }
      }
    }
    return '';
  }

  String _findIntroRule() {
    final patterns = <RulePattern>[
      ('class', 'intro'),
      ('class', 'desc'),
      ('class', 'summary'),
      ('class', 'jianjie'),
      ('class', 'jj'),
    ];
    for (final (type_, value) in patterns) {
      for (final el in elements) {
        if (type_ == 'class' && el.classStr.contains(value)) {
          if (el.text.isNotEmpty && el.text.trim().length > 20) {
            return 'class.$value@text';
          }
        }
      }
    }
    return '';
  }

  // ===================== 详情页规则 =====================

  Map<String, dynamic> extractBookInfoRules() {
    return {
      'init': '',
      'name': _findDetailNameRule(),
      'author': _findDetailAuthorRule(),
      'coverUrl': _findDetailCoverRule(),
      'intro': _findDetailIntroRule(),
      'kind': _findDetailKindRule(),
      'lastChapter': _findDetailLastChapterRule(),
      'wordCount': _findWordCountRule(),
      'tocUrl': _findTocUrlRule(),
    };
  }

  String _findDetailNameRule() {
    final patterns = <RulePattern>[
      ('class', 'bookname'),
      ('class', 'name'),
      ('class', 'title'),
      ('id', 'info'),
      ('tag', 'h1'),
    ];
    for (final (type_, value) in patterns) {
      for (final el in elements) {
        if (type_ == 'class' && el.classStr.contains(value)) {
          return 'class.$value@text';
        } else if (type_ == 'id' && el.id == value) {
          return 'id.$value@tag.h1@text';
        } else if (type_ == 'tag' && el.tag == value) {
          final text = el.text.trim();
          if (text.isNotEmpty && text.length < 50) {
            return 'tag.$value@text';
          }
        }
      }
    }
    return '';
  }

  String _findDetailAuthorRule() {
    for (final el in elements) {
      final text = el.text.trim();
      if (text.contains('作者') && text.length < 50) {
        if (el.classStr.isNotEmpty) {
          var rule = 'class.${el.firstClass}@text';
          rule += '##作者：##';
          return rule;
        } else if (el.tag == 'p' || el.tag == 'span') {
          return 'tag.${el.tag}@text##作者：##';
        }
      }
    }
    return '';
  }

  String _findDetailCoverRule() {
    for (final el in elements) {
      if (el.tag == 'img') {
        if (el.src.isNotEmpty &&
            (el.classStr.contains('cover') ||
                el.src.contains('cover') ||
                el.src.contains('book'))) {
          return 'img@src';
        } else if (el.dataSrc.isNotEmpty) {
          return 'img@data-src';
        }
      }
    }
    for (final el in elements) {
      if (el.tag == 'img' && el.id.isNotEmpty && el.id.contains('cover')) {
        return 'id.${el.id}@src';
      }
    }
    return '';
  }

  String _findDetailIntroRule() {
    final patterns = <RulePattern>[
      ('class', 'intro'),
      ('class', 'desc'),
      ('class', 'summary'),
      ('class', 'jianjie'),
      ('id', 'intro'),
      ('id', 'desc'),
    ];
    for (final (type_, value) in patterns) {
      for (final el in elements) {
        if (type_ == 'class' && el.classStr.contains(value)) {
          if (el.text.isNotEmpty && el.text.trim().length > 20) {
            return 'class.$value@text';
          }
        } else if (type_ == 'id' && el.id == value) {
          if (el.text.isNotEmpty && el.text.trim().length > 20) {
            return 'id.$value@text';
          }
        }
      }
    }
    return '';
  }

  String _findDetailKindRule() {
    for (final el in elements) {
      final text = el.text.trim();
      if ((text.contains('分类') || text.contains('类型')) && text.length < 30) {
        if (el.classStr.isNotEmpty) {
          return 'class.${el.firstClass}@text##分类：|类型：##';
        }
      }
    }
    return '';
  }

  String _findDetailLastChapterRule() {
    for (final el in elements) {
      final text = el.text.trim();
      if ((text.contains('最新') || text.contains('更新')) &&
          (text.contains('章') || text.contains('节'))) {
        if (el.tag == 'a') {
          if (el.classStr.isNotEmpty) {
            return 'class.${el.firstClass}@tag.a@text';
          }
          return 'tag.a@text';
        } else if (el.classStr.isNotEmpty) {
          return 'class.${el.firstClass}@text##最新：|更新：##';
        }
      }
    }
    return '';
  }

  String _findWordCountRule() {
    for (final el in elements) {
      final text = el.text.trim();
      if (text.contains('字') &&
          (text.contains('万') || text.length < 20)) {
        if (el.classStr.isNotEmpty) {
          return 'class.${el.firstClass}@text';
        }
      }
    }
    return '';
  }

  String _findTocUrlRule() {
    for (final el in elements) {
      final text = el.text.trim();
      if (el.tag == 'a' && el.href.isNotEmpty) {
        if (['点击阅读', '开始阅读', '查看目录', '全部目录', '章节目录', '阅读']
            .any(text.contains)) {
          if (el.classStr.isNotEmpty) {
            return 'class.${el.firstClass}@href';
          }
          return 'tag.a@href';
        }
      }
    }
    return '';
  }

  // ===================== 目录页规则 =====================

  (Map<String, dynamic>, bool) extractTocRules() {
    var chapterListRule = _findChapterListRule();
    final isReverse = _checkChapterOrder();
    if (isReverse) {
      chapterListRule = '-$chapterListRule';
    }
    final nextTocUrlRule = _findNextTocUrlRule();
    return ({
      'chapterList': chapterListRule,
      'chapterName': '@text',
      'chapterUrl': '@href',
      'nextTocUrl': nextTocUrlRule,
      'preUpdateJs': '',
    }, isReverse);
  }

  String _findChapterListRule() {
    final patterns = <RulePattern>[
      ('class', 'chapter'),
      ('class', 'list'),
      ('class', 'catalog'),
      ('id', 'list'),
      ('id', 'chapter'),
      ('tag', 'dd'),
    ];
    for (final (type_, value) in patterns) {
      for (final el in elements) {
        if (type_ == 'class' && el.classStr.contains(value)) {
          if (el.tag == 'div' || el.tag == 'ul') {
            return 'class.${el.firstClass}@tag.a';
          } else if (el.tag == 'dl') {
            return 'class.${el.firstClass}@tag.dd@tag.a';
          }
        } else if (type_ == 'id' && el.id.contains(value)) {
          return 'id.${el.id}@tag.a';
        } else if (type_ == 'tag' && el.tag == value) {
          return 'tag.$value@tag.a';
        }
      }
    }
    return 'tag.dd@tag.a';
  }

  bool _checkChapterOrder() {
    final chapterTexts = <String>[];
    for (final el in elements) {
      final text = el.text.trim();
      if (text.contains('第') &&
          (text.contains('章') || text.contains('节')) &&
          text.length < 50) {
        chapterTexts.add(text);
      }
    }
    if (chapterTexts.length >= 2) {
      final first = chapterTexts.first;
      final last = chapterTexts.last;
      final firstNum = _extractChapterNumber(first);
      final lastNum = _extractChapterNumber(last);
      if (firstNum != null && lastNum != null && firstNum > lastNum) {
        return true;
      }
    }
    return false;
  }

  int? _extractChapterNumber(String text) {
    final m = RegExp(r'第(\d+)').firstMatch(text);
    if (m != null) return int.tryParse(m.group(1)!);

    const chineseNums = {
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
      '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
      '百': 100, '千': 1000,
    };
    final cm = RegExp(r'第([一二三四五六七八九十百千]+)').firstMatch(text);
    if (cm != null) {
      var num = 0;
      for (final ch in cm.group(1)!.split('')) {
        if (chineseNums.containsKey(ch)) {
          num += chineseNums[ch]!;
        }
      }
      return num;
    }
    return null;
  }

  String _findNextTocUrlRule() {
    for (final el in elements) {
      final text = el.text.trim();
      if (el.tag == 'a' && el.href.isNotEmpty) {
        if (text.contains('下一页') || text.toLowerCase().contains('next')) {
          if (el.classStr.isNotEmpty) {
            return 'class.${el.firstClass}@href';
          }
          return 'tag.a@href';
        }
      }
    }
    return '';
  }

  // ===================== 正文页规则 =====================

  Map<String, dynamic> extractContentRules() {
    return {
      'content': _findContentRule(),
      'nextContentUrl': _findNextContentUrlRule(),
      'replaceRegex': _findAdsPattern(),
      'webJs': '',
      'sourceRegex': '',
    };
  }

  String _findContentRule() {
    final patterns = <RulePattern>[
      ('id', 'content'),
      ('id', 'chaptercontent'),
      ('class', 'content'),
      ('class', 'chapter-content'),
      ('class', 'read-content'),
      ('class', 'txt'),
    ];
    for (final (type_, value) in patterns) {
      for (final el in elements) {
        if (type_ == 'id' && el.id == value) {
          return 'id.$value@textNodes';
        } else if (type_ == 'class' && el.classStr.contains(value)) {
          return 'class.${el.firstClass}@textNodes';
        }
      }
    }
    return 'id.content@textNodes';
  }

  String _findNextContentUrlRule() {
    for (final el in elements) {
      final text = el.text.trim();
      if (el.tag == 'a' && el.href.isNotEmpty) {
        if (text.contains('下一页') ||
            text.contains('下一章') ||
            text.toLowerCase().contains('next')) {
          if (el.classStr.isNotEmpty) {
            return 'class.${el.firstClass}@href';
          }
          return 'tag.a@href';
        }
      }
    }
    return '';
  }

  String _findAdsPattern() {
    const adsKeywords = [
      '本章未完',
      '点击下一页',
      '手机阅读',
      '最新网址',
      '请记住',
      '首发域名',
      '笔趣阁',
      '阅读更多',
    ];
    final found = <String>[];
    for (final kw in adsKeywords) {
      if (html.contains(kw)) found.add(kw);
    }
    if (found.isNotEmpty) {
      return '##${found.join('|')}.*?##';
    }
    return '';
  }
}
