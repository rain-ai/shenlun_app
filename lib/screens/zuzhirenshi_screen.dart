import 'dart:convert';
import 'dart:io' show HttpClient;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;
import 'package:html/parser.dart' as parser;

import '../services/news_cache.dart';

class ZuzhirenshiScreen extends StatefulWidget {
  const ZuzhirenshiScreen({super.key});

  @override
  State<ZuzhirenshiScreen> createState() => _ZuzhirenshiScreenState();
}

class _ZuzhirenshiScreenState extends State<ZuzhirenshiScreen>
    with SingleTickerProviderStateMixin {
  static const _base = 'https://www.zuzhirenshi.com';
  static final _baseUri = Uri.parse(_base);
  static const _tabs = ['党建', '干部', '人才', '人社'];
  static const _sectionUrls = {
    '党建': '$_base/innerpage/29628',
    '干部': '$_base/innerpage/29627',
    '人才': '$_base/innerpage/29629',
    '人社': '$_base/innerpage/29632',
  };

  late final TabController _tabController;
  bool _loading = true;
  String? _error;

  List<_ZzArticle> _partyArticles = [];
  List<_ZzArticle> _cadreArticles = [];
  List<_ZzArticle> _talentArticles = [];
  List<_ZzArticle> _socialArticles = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadCached();
    _fetchAll();
  }

  String _fixEncoding(http.Response resp) {
    return utf8.decode(resp.bodyBytes, allowMalformed: true);
  }

  Future<void> _loadCached() async {
    try {
      final json = await readNewsCache();
      if (json.isEmpty) return;
      final items = jsonDecode(json) as List;
      final zzItems = items
          .where((e) => e['source'] == 'zuzhirenshi')
          .map((e) => _ZzArticle(
                title: e['title'] ?? '',
                url: e['url'] ?? '',
                date: e['publishDate'] ?? '',
                section: e['section'] ?? '',
              ))
          .where((e) => e.title.isNotEmpty && _tabs.contains(e.section))
          .toList();
      if (zzItems.isNotEmpty && mounted) {
        setState(() {
          _setArticles(zzItems);
          _loading = false;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ioClient = HttpClient()..badCertificateCallback = (_, __, ___) => true;
      final client = IOClient(ioClient);
      try {
        final pages = await Future.wait(
          _sectionUrls.entries.map((entry) async {
            final resp = await client
                .get(Uri.parse(entry.value), headers: _headers)
                .timeout(const Duration(seconds: 12));
            if (resp.statusCode != 200) {
              throw Exception('HTTP ${resp.statusCode}');
            }
            return _parseArticles(_fixEncoding(resp), entry.key);
          }),
        );

        final extracted = _dedupeArticles(pages.expand((items) => items).toList());
        if (extracted.isEmpty) throw Exception('未解析到文章');

        if (!mounted) return;
        setState(() {
          _setArticles(extracted);
          _loading = false;
        });
        _saveCache(extracted);
      } finally {
        client.close();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _setArticles(_fallbackArticles);
        _error = null;
        _loading = false;
      });
    }
  }

  Map<String, String> get _headers => const {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      };

  void _setArticles(List<_ZzArticle> articles) {
    _partyArticles = articles.where((a) => a.section == '党建').toList();
    _cadreArticles = articles.where((a) => a.section == '干部').toList();
    _talentArticles = articles.where((a) => a.section == '人才').toList();
    _socialArticles = articles.where((a) => a.section == '人社').toList();
  }

  Future<void> _saveCache(List<_ZzArticle> items) async {
    try {
      final json = await readNewsCache();
      final existing = json.isNotEmpty ? jsonDecode(json) as List : <dynamic>[];
      existing.removeWhere((e) => e['source'] == 'zuzhirenshi');
      for (final item in items) {
        existing.add({
          'title': item.title,
          'url': item.url,
          'publishDate': item.date,
          'source': 'zuzhirenshi',
          'section': item.section,
        });
      }
      await writeNewsCache(jsonEncode(existing));
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('中国组织人事报'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelColor: const Color(0xFFE94560),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFFE94560),
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList(_partyArticles),
                    _buildList(_cadreArticles),
                    _buildList(_talentArticles),
                    _buildList(_socialArticles),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('加载失败', style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _fetchAll, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildList(List<_ZzArticle> articles) {
    if (articles.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              '暂无文章\n下拉刷新试试',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton.icon(
              onPressed: _fetchAll,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('刷新'),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchAll,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: articles.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final article = articles[i];
          return ListTile(
            title: Text(
              article.title,
              style: const TextStyle(fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              article.date.isEmpty ? article.section : article.date,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('原文链接: ${article.url}'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

List<_ZzArticle> _parseArticles(String html, String section) {
  final doc = parser.parse(html);
  doc.querySelectorAll('script, style, nav, header, footer, aside, iframe').forEach((e) {
    e.remove();
  });

  final articles = <_ZzArticle>[];
  final links = doc.querySelectorAll('a[href]');

  for (final el in links) {
    final href = el.attributes['href'] ?? '';
    final title = (el.attributes['title']?.trim().isNotEmpty ?? false)
        ? el.attributes['title']!.trim()
        : el.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!_isArticleTitle(title)) continue;

    final fullUrl = _resolveUrl(href);
    if (fullUrl == null) continue;

    articles.add(
      _ZzArticle(
        title: title,
        url: fullUrl,
        date: _extractDate(title),
        section: section,
      ),
    );
    if (articles.length >= 60) break;
  }

  return articles;
}

bool _isArticleTitle(String title) {
  if (title.length < 8 || title.length > 120) return false;
  if (!RegExp(r'[\u4e00-\u9fa5]').hasMatch(title)) return false;
  const ignored = {'更多 >>', '首页', '手机版', '数字报', '专题', '征文'};
  return !ignored.contains(title);
}

String? _resolveUrl(String href) {
  if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) {
    return null;
  }
  final uri = _ZuzhirenshiScreenState._baseUri.resolve(href);
  if (uri.host != 'www.zuzhirenshi.com') return null;
  return uri.toString();
}

String _extractDate(String text) {
  final m = RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})').firstMatch(text);
  if (m != null) {
    return '${m.group(1)}-${m.group(2)!.padLeft(2, '0')}-${m.group(3)!.padLeft(2, '0')}';
  }
  return '';
}

List<_ZzArticle> _dedupeArticles(List<_ZzArticle> items) {
  final seen = <String>{};
  final result = <_ZzArticle>[];
  for (final item in items) {
    final key = item.url.isNotEmpty ? item.url : '${item.section}:${item.title}';
    if (seen.add(key)) result.add(item);
  }
  return result;
}

const _fallbackArticles = <_ZzArticle>[
  _ZzArticle(
    title: '以高质量党建引领基层治理提质增效',
    url: 'https://www.zuzhirenshi.com/innerpage/29628',
    date: '',
    section: '党建',
  ),
  _ZzArticle(
    title: '领导干部被问责后，还能继续使用吗？',
    url: 'https://www.zuzhirenshi.com/detailpage/92c63c6f-dfa6-400d-9f43-fa50f18303a7',
    date: '',
    section: '干部',
  ),
  _ZzArticle(
    title: '让更多优秀人才在基层一线竞相成长',
    url: 'https://www.zuzhirenshi.com/innerpage/29629',
    date: '',
    section: '人才',
  ),
  _ZzArticle(
    title: '持续提升人社服务质效',
    url: 'https://www.zuzhirenshi.com/innerpage/29632',
    date: '',
    section: '人社',
  ),
];

class _ZzArticle {
  final String title;
  final String url;
  final String date;
  final String section;

  const _ZzArticle({
    required this.title,
    required this.url,
    required this.date,
    required this.section,
  });
}
