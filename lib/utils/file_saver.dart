/// 文件保存/分享工具：将 JSON 写入应用文档目录并通过系统分享面板导出。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileSaver {
  /// 保存 [content] 到 [fileName]，返回文件路径；失败返回 null。
  static Future<String?> saveString(String fileName, String content) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/$fileName';
      final file = File(path);
      await file.writeAsString(content, encoding: utf8);
      return path;
    } catch (_) {
      return null;
    }
  }

  /// 保存并通过系统分享面板分享文件。
  static Future<void> shareString(String fileName, String content,
      {String? subject}) async {
    final path = await saveString(fileName, content);
    if (path == null) return;
    await Share.shareXFiles(
      [XFile(path)],
      subject: subject ?? fileName,
    );
  }

  /// 保存 JSON 对象（缩进2空格，中文不转义）并分享。
  static Future<void> shareJson(String fileName, List<Map<String, dynamic>> data,
      {String? subject}) async {
    const encoder = JsonEncoder.withIndent('  ');
    await shareString(fileName, encoder.convert(data), subject: subject);
  }
}
