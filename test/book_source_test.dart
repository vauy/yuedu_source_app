// 阅读书源工具 - 单元测试（无需网络，验证核心模型与规则提取）。
import 'package:flutter_test/flutter_test.dart';
import 'package:yuedu_source_app/models/book_source.dart';
import 'package:yuedu_source_app/services/html_rule_extractor.dart';

void main() {
  group('BookSource', () {
    test('toJson 包含阅读3.0标准字段且中文不转义', () {
      final src = BookSource(
        bookSourceName: '测试书源',
        bookSourceUrl: 'https://example.com',
        searchUrl: 'https://example.com/search?q={{key}}',
        ruleSearch: {'bookList': 'tag.li', 'name': 'class.bookname@text'},
      );
      final json = src.toPrettyJson();
      expect(json, contains('测试书源'));
      expect(json, contains('bookSourceName'));
      expect(json, contains('ruleSearch'));
      expect(json, contains('https://example.com/search?q={{key}}'));
    });
  });

  group('JsoupRuleExtractor', () {
    test('提取搜索页书名/作者/书籍URL规则', () {
      const html = '''
      <html><body>
        <ul class="result-list">
          <li>
            <a href="/book/123"><span class="bookname">我的小说</span></a>
            <span class="author">作者：张三</span>
            <img src="/cover/123.jpg" />
          </li>
        </ul>
      </body></html>
      ''';
      final rules = JsoupRuleExtractor(html).extractSearchRules();
      expect(rules['bookUrl'], equals('tag.a@href'));
      expect(rules['name'].toString().contains('bookname'), isTrue);
      expect(rules['coverUrl'], equals('img@src'));
    });

    test('正文规则默认回退 id.content@textNodes', () {
      const html = '<html><body><div id="content">正文</div></body></html>';
      final rules = JsoupRuleExtractor(html).extractContentRules();
      expect(rules['content'], equals('id.content@textNodes'));
    });
  });
}
