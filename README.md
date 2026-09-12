# 练申论 — 公务员考试申论练习 App

一款专为公考申论备考打造的 Flutter 应用，集题库练习、时政积累、AI 批改、素材库于一体。

**免责声明：本软件仅用于免费学习交流，切勿用于牟利。**

---

## 项目来源 / Project Origin

本项目基于开源项目二次开发，在此向原作者致以诚挚谢意。

| 项目 | 仓库地址 |
|------|----------|
| 原项目（上游） | [https://github.com/se651/shenlun_app](https://github.com/se651/shenlun_app) |
| 本仓库 | [https://github.com/rain-ai/shenlun_app](https://github.com/rain-ai/shenlun_app) |

> 本仓库在原项目基础上进行了功能增强与体验优化，所有改动均遵循原项目的开源精神，仅用于学习交流。如需了解项目最初的设计与实现，请访问上游仓库。

---

## 本分支修改与新增内容 / Changes & Additions

相较于上游原项目，本分支主要进行了以下修改与新增：

### ✨ 新增功能

#### 1. 自定义题目批改（Custom Question Review）
- **新增页面**：`lib/screens/custom_question_review_screen.dart`
- 支持用户上传**自定义题目**进行 AI 批改，不再局限于内置题库
- 支持多种文件格式上传：`jpg / jpeg / png / webp / pdf / doc / docx`
- 图片题目通过 DeepSeek API 进行 OCR 文字识别
- PDF / Word 文档自动解析提取题干文本
- 支持手动设置题型（概括归纳 / 综合分析 / 提出对策 / 应用文写作 / 大作文写作）与字数限制
- 批改结果自动保存到历史记录

#### 2. 文件文本提取服务（File Text Extractor）
- **新增服务**：`lib/services/file_text_extractor.dart`
- 统一封装多类型文件的文本提取逻辑
- 图片：调用 `OcrService` 进行 OCR 识别
- PDF：提取纯文本内容
- DOCX：通过 `archive` 包解析 `word/document.xml` 提取正文
- 提取失败时给出友好的提示信息

#### 3. 首页入口
- 在首页新增「自定义题目批改」功能入口，方便用户快速访问

### 🔧 优化与重构

#### 4. 组织人事页面重构（`zuzhirenshi_screen.dart`）
- 将「党建 / 干部 / 人才 / 人社」四个栏目的抓取由串行改为**并行**（`Future.wait`），显著提升加载速度
- 抽取公共请求头 `_headers`，减少重复代码
- **移除了不安全的 `badCertificateCallback`（跳过 SSL 证书校验）**，改用标准 HTTP 客户端，提升安全性
- Tab 数量与栏目配置统一由 `_tabs` / `_sectionUrls` 常量管理

#### 5. 历史记录适配自定义题目（`history_screen.dart`）
- 历史记录支持展示自定义题目批改记录
- 当题目无标题时，自动回退到 `practice_mode` 中提取的标题，否则显示「自定义题目」
- 题型同理回退，否则显示「自定义批改」
- 自定义题目组显示专属提示条（绿色），而非「查看题目详情」按钮

#### 6. Android 构建配置升级
- NDK 版本升级至 `28.2.13676358`
- 新增 `androidx.appcompat:appcompat:1.7.1` 依赖
- 新增 Flutter 官方 Maven 仓库 `https://storage.googleapis.com/download.flutter.io`
- 新增 Kotlin 编译器配置（`kotlin.compiler.execution.strategy=in-process`、`kotlin.daemon.enabled=false`）
- 由 Flutter 迁移工具自动添加 `android.builtInKotlin=false` 与 `android.newDsl=false`

#### 7. 应用图标更新
- 更新 Android 各分辨率启动器图标（`mipmap-mdpi` ~ `mipmap-xxxhdpi`）
- 新增 `assets/app_icon.jpg` 应用图标资源

#### 8. 代码格式化
- 对 `lib/main.dart` 等文件执行 `dart format`，统一代码风格，提升可读性

### 🗑️ 移除内容
- 删除废弃文件 `old_scraper.dart`（旧版新闻抓取器）

---

## 功能特性

### 📝 题库练习
- **海量真题**：收录历年国考、省考申论真题，支持按题型、关键词搜索
- **模拟考试**：AI 自动组卷，模拟真实考试环境
- **AI 智能批改**：接入 DeepSeek API，五位 AI 老师多维度评分，提供参考范文
- **自定义题目批改**：支持上传图片 / PDF / Word 题目，进行 AI 智能批改

### 📰 时政积累
- **人民日报评论**：精选人民时评文章，支持 AI 要点提炼
- **重要讲话**：收录重要讲话原文及解读
- **重要会议**：跟踪最新会议精神与政策方向
- **组织人事**：关注干部动态与人事调整
- **求是杂志 / 红旗文稿**：理论文章阅读
- **新闻周刊**：每周时政热点汇总

### 📚 素材库
- **政府文档**：历年政府工作报告、重要政策文件
- **人物素材**：典型人物事迹，适用于申论论证
- **党史学习**：党史知识题库与学习材料
- **新兴概念**：最新政策热词与概念解析
- **聚焦重点**：高频考点与重点知识梳理

### 📖 规范词库
- **申论规范词**：1000+ 申论常用规范表达
- **政治词典**：政治术语详细解释
- **习语词典**：经典用语汇编
- **新年贺词**：历年新年贺词汇总

### 🎯 专项练习
- **概括练习**：材料概括能力训练
- **评论练习**：评论性文章写作训练
- **弱项攻克**：针对薄弱题型定向突破
- **错题本**：自动收录错题，反复练习
- **收藏夹**：收藏重点题目与文章

### 🎨 视觉体验
- **三种主题模式**：浅色 / 深色 / 护眼模式
- **字体缩放**：自由调节字号大小
- **每日推送**：AI 生成的每日时政卡片

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.x (Dart SDK ^3.7.2) |
| 本地存储 | SQLite (sqflite) |
| 状态管理 | StatefulWidget + setState |
| HTTP | http |
| HTML 解析 | html |
| 文件操作 | path_provider, file_picker, share_plus |
| PDF | pdf (生成答题卡) |
| WebView | flutter_inappwebview |
| 音频 | audioplayers |
| 动画 | confetti (撒花效果) |
| OCR | DeepSeek API (图片文字识别) |
| 文档解析 | archive (DOCX 解压解析) |
| 平台支持 | Android / iOS / Windows / Linux / macOS / Web |

## 快速开始

### 环境要求

- Flutter SDK >= 3.7.2
- Dart SDK >= 3.7.2
- Android Studio 或 VS Code

### 安装运行

```bash
# 克隆本仓库
git clone https://github.com/rain-ai/shenlun_app.git
cd shenlun_app

# 安装依赖
flutter pub get

# 运行应用
flutter run
```

### 构建 APK

```bash
flutter build apk --release
```

APK 输出路径：`build/app/outputs/flutter-apk/app-release.apk`

### AI 批改配置

在应用「我的 → 设置」中填入你的 DeepSeek API Key 即可启用 AI 批改功能。不配置则只能查看题目，无法使用 AI 批改及图片 OCR 识别。

## 项目结构

```
lib/
├── main.dart                    # 应用入口，主题配置，启动页
├── data/                        # 数据模型
│   ├── important_meetings.dart  # 重要会议数据
│   ├── new_concepts.dart        # 新兴概念数据
│   ├── party_history.dart       # 党史数据
│   ├── person_data.dart         # 人物素材
│   ├── political_dict.dart      # 政治词典
│   ├── xinnian_heci.dart        # 新年贺词
│   └── xiyu_dict.dart           # 习语词典
├── database/
│   └── db_helper.dart           # SQLite 数据库操作
├── scorer/
│   ├── ai_scorer.dart           # AI 评分引擎
│   └── local_scorer.dart        # 本地评分引擎
├── screens/                     # 页面（50+ 页面）
│   ├── home_screen.dart         # 首页
│   ├── question_screen.dart     # 题库
│   ├── news_screen.dart         # 时政
│   ├── words_screen.dart        # 规范词
│   ├── material_library_screen.dart  # 素材库
│   ├── profile_screen.dart      # 我的
│   ├── custom_question_review_screen.dart  # 自定义题目批改（新增）
│   ├── mock_exam_*.dart         # 模拟考试
│   ├── summary_*.dart           # 概括练习
│   └── ...                      # 更多功能页面
├── services/                    # 业务逻辑层
│   ├── achievement_service.dart # 成就系统
│   ├── daily_push.dart          # 每日推送
│   ├── export_service.dart      # 导出服务
│   ├── file_text_extractor.dart # 文件文本提取（新增）
│   ├── mock_exam_generator.dart # 模拟考试生成
│   ├── news_scraper.dart        # 新闻抓取
│   ├── ocr_service.dart         # OCR 识别
│   └── ...                      # 更多服务
└── widgets/                     # 可复用组件
    ├── achievement_overlay.dart # 成就弹窗
    └── shiny_medal.dart         # 闪光勋章
```

## 版本

当前版本：**1.0.0-alpha.58**

## 许可证

本项目仅用于学习交流目的。题库内容版权归原作者所有。

---

> **恰同学少年，风华正茂；书生意气，挥斥方遒。**
