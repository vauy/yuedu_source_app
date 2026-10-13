# 阅读书源工具 (Yuedu Source App)

一个用 **Flutter** 构建的 **原生 Android APP**，整合了两个上游 Python 工具的核心能力：

- **书源自动生成** —— 移植自 [auto_source_generator](https://github.com/vauy/auto_source_generator)
- **书源校验** —— 移植自 [xin-verify-book-source](https://github.com/vauy/xin-verify-book-source)

## 功能

### 书源生成
输入小说网站首页 URL，APP 会自动完成：
1. 分析首页搜索功能（GET/POST、表单参数、隐藏字段、编码 UTF-8/GBK）
2. 用关键词发起搜索，定位第一本书的详情页
3. 从详情页跳转到完整目录页
4. 抓取第一章正文页
5. 对四个页面分别用 JSOUP 规则提取器自动生成阅读3.0规则
6. 组装成标准阅读3.0书源 JSON，可直接导入「阅读」APP

部分步骤失败时仍会生成「部分书源」并标注，保证可用性。

### 书源校验
- 支持本地书源文件路径或直链 URL
- 并发校验（自定义线程数）每条书源的 `bookSourceUrl` 是否返回 200
- 忽略 SSL 证书错误（对应 `verify=False`）
- 重复书源去重
- 实时进度条 + 成果报表
- 一键导出有效/无效书源 JSON

## 构建产物

原生 Android APK 通过 Flutter 构建：

```bash
flutter pub get
flutter build apk --release
```

产物位于 `build/app/outputs/flutter-apk/app-release.apk`。

## 技术栈

| 能力 | 实现 |
| --- | --- |
| UI 框架 | Flutter (Material 3) |
| HTTP | `package:http` + 忽略 SSL 的 `IOClient` |
| HTML 解析 | `package:html`（前序遍历模拟 SAX，行为对齐 Python `html.parser`） |
| GBK 编码 | `package:gbk_codec`（解码页面 + 编码 POST 表单） |
| 文件选择/分享 | `package:file_picker` / `package:share_plus` |
| 应用 ID | `com.yuedu.sourceapp` |

## 项目结构

```
lib/
├── main.dart                          # 入口
├── models/
│   └── book_source.dart               # 阅读3.0书源数据模型
├── services/
│   ├── http_service.dart              # 抓取/编解码/JS重定向/重试
│   ├── html_rule_extractor.dart       # JSOUPRuleExtractor (移植)
│   ├── source_generator.dart          # AutoSourceGenerator (移植编排)
│   └── source_verifier.dart           # 书源并发校验 (移植 book.py)
├── screens/
│   ├── home_screen.dart               # 底部导航
│   ├── generator_screen.dart          # 书源生成页
│   └── verifier_screen.dart          # 书源校验页
├── widgets/
│   └── log_console.dart               # 滚动日志组件
└── utils/
    └── file_saver.dart                # 保存/分享文件
```

## 致谢

- [vauy/auto_source_generator](https://github.com/vauy/auto_source_generator)
- [vauy/xin-verify-book-source](https://github.com/vauy/xin-verify-book-source)
