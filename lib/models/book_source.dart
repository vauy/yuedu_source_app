/// 阅读3.0 书源数据模型，对应 auto_source_generator 生成的 JSON 结构。
library;

import 'dart:convert';

/// 单条阅读书源。规则子对象以 Map 保留，便于灵活序列化为阅读3.0格式。
class BookSource {
  String bookSourceComment;
  String bookSourceGroup;
  String bookSourceName;
  int bookSourceType;
  String bookSourceUrl;
  int customOrder;
  bool enabled;
  bool enabledCookieJar;
  bool enabledExplore;
  String exploreUrl;
  int respondTime;
  Map<String, dynamic> ruleBookInfo;
  Map<String, dynamic> ruleContent;
  Map<String, dynamic> ruleExplore;
  Map<String, dynamic> ruleSearch;
  Map<String, dynamic> ruleToc;
  String searchUrl;
  int weight;

  BookSource({
    this.bookSourceComment = '',
    this.bookSourceGroup = '',
    required this.bookSourceName,
    this.bookSourceType = 0,
    required this.bookSourceUrl,
    this.customOrder = 0,
    this.enabled = true,
    this.enabledCookieJar = true,
    this.enabledExplore = false,
    this.exploreUrl = '',
    this.respondTime = 180000,
    Map<String, dynamic>? ruleBookInfo,
    Map<String, dynamic>? ruleContent,
    Map<String, dynamic>? ruleExplore,
    Map<String, dynamic>? ruleSearch,
    Map<String, dynamic>? ruleToc,
    required this.searchUrl,
    this.weight = 0,
  })  : ruleBookInfo = ruleBookInfo ?? {},
        ruleContent = ruleContent ?? {},
        ruleExplore = ruleExplore ?? {'bookList': ''},
        ruleSearch = ruleSearch ?? {},
        ruleToc = ruleToc ?? {};

  /// 序列化为阅读3.0标准书源 JSON（中文不转义，2空格缩进）。
  String toPrettyJson() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson());
  }

  Map<String, dynamic> toJson() => {
        'bookSourceComment': bookSourceComment,
        'bookSourceGroup': bookSourceGroup,
        'bookSourceName': bookSourceName,
        'bookSourceType': bookSourceType,
        'bookSourceUrl': bookSourceUrl,
        'customOrder': customOrder,
        'enabled': enabled,
        'enabledCookieJar': enabledCookieJar,
        'enabledExplore': enabledExplore,
        'exploreUrl': exploreUrl,
        'respondTime': respondTime,
        'ruleBookInfo': ruleBookInfo,
        'ruleContent': ruleContent,
        'ruleExplore': ruleExplore,
        'ruleSearch': ruleSearch,
        'ruleToc': ruleToc,
        'searchUrl': searchUrl,
        'weight': weight,
      };

  factory BookSource.fromJson(Map<String, dynamic> json) {
    return BookSource(
      bookSourceName: json['bookSourceName']?.toString() ?? '',
      bookSourceUrl: json['bookSourceUrl']?.toString() ?? '',
      searchUrl: json['searchUrl']?.toString() ?? '',
      bookSourceType: _asInt(json['bookSourceType']),
      customOrder: _asInt(json['customOrder']),
      enabled: json['enabled'] == true,
      enabledCookieJar: json['enabledCookieJar'] == true,
      enabledExplore: json['enabledExplore'] == true,
      respondTime: _asInt(json['respondTime'], fallback: 180000),
      weight: _asInt(json['weight']),
      ruleBookInfo: Map<String, dynamic>.from(json['ruleBookInfo'] ?? {}),
      ruleContent: Map<String, dynamic>.from(json['ruleContent'] ?? {}),
      ruleExplore: Map<String, dynamic>.from(json['ruleExplore'] ?? {'bookList': ''}),
      ruleSearch: Map<String, dynamic>.from(json['ruleSearch'] ?? {}),
      ruleToc: Map<String, dynamic>.from(json['ruleToc'] ?? {}),
    );
  }

  static int _asInt(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }
}
