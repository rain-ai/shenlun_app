import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/db_helper.dart';
import '../scorer/ai_scorer.dart';
import '../scorer/local_scorer.dart';
import '../services/file_text_extractor.dart';

class CustomQuestionReviewScreen extends StatefulWidget {
  const CustomQuestionReviewScreen({super.key});

  @override
  State<CustomQuestionReviewScreen> createState() =>
      _CustomQuestionReviewScreenState();
}

class _CustomQuestionReviewScreenState
    extends State<CustomQuestionReviewScreen> {
  final _db = DatabaseHelper();
  final _questionController = TextEditingController();
  final _answerController = TextEditingController();
  final _referenceController = TextEditingController();
  final _wordLimitController = TextEditingController();

  String _questionType = '概括归纳';
  String? _fileName;
  String? _warning;
  bool _extracting = false;
  bool _scoring = false;
  bool _historySaved = false;
  ScoreResult? _result;

  static const _questionTypes = <String, int>{
    '概括归纳': 10,
    '综合分析': 15,
    '提出对策': 20,
    '应用文写作': 25,
    '大作文写作': 35,
  };

  @override
  void dispose() {
    _questionController.dispose();
    _answerController.dispose();
    _referenceController.dispose();
    _wordLimitController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'doc', 'docx'],
      withData: false,
    );
    final file = picked?.files.single;
    final path = file?.path;
    if (file == null || path == null) return;

    setState(() {
      _extracting = true;
      _fileName = file.name;
      _warning = null;
      _result = null;
      _historySaved = false;
    });

    try {
      final apiKey = await _db.getSetting('deepseek_api_key');
      final extracted = await FileTextExtractor.extract(
        path: path,
        fileName: file.name,
        apiKey: apiKey,
      );
      if (!mounted) return;
      setState(() {
        _fileName = extracted.fileName;
        _warning = extracted.warning;
        if (extracted.text.isNotEmpty) {
          _questionController.text = extracted.text;
          _questionController.selection = TextSelection.collapsed(
            offset: extracted.text.length,
          );
        }
      });
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  Future<void> _scoreWithAI() async {
    final question = _questionController.text.trim();
    final answer = _answerController.text.trim();
    if (question.isEmpty) {
      _showMessage('请先上传或输入题目内容。');
      return;
    }
    if (answer.isEmpty) {
      _showMessage('请先填写你的作答内容。');
      return;
    }

    final apiKey = await _db.getSetting('deepseek_api_key');
    if (apiKey.isEmpty) {
      _showMessage('请先到“我的”页面配置 DeepSeek API Key。');
      return;
    }

    setState(() {
      _scoring = true;
      _result = null;
      _historySaved = false;
    });

    final totalScore = _questionTypes[_questionType] ?? 20;
    final wordLimit = int.tryParse(_wordLimitController.text.trim());
    final result = await AIScorer.score(
      apiKey: apiKey,
      userAnswer: answer,
      referenceAnswer: _referenceController.text.trim(),
      materialText: question,
      questionType: _questionType,
      scoreHint: '$totalScore分',
      wordLimit: wordLimit,
    );

    if (!mounted) return;
    setState(() {
      _result = result;
      _scoring = false;
    });

    if (result == null) {
      _showMessage('AI 批改失败，请检查网络或 API Key 后重试。');
      return;
    }

    await _saveToHistory(
      question: question,
      answer: answer,
      result: result,
    );
  }

  Future<void> _saveToHistory({
    required String question,
    required String answer,
    required ScoreResult result,
  }) async {
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();
    final title = _buildHistoryTitle(question);
    final analysis = _formatHistoryAnalysis(question, result);

    await _db.savePracticeRecord({
      'id': id,
      'question_id': 'custom_$id',
      'user_answer': answer,
      'score': result.score,
      'score_breakdown': result.details,
      'suggestions': result.suggestion.isNotEmpty ? result.suggestion : result.feedback,
      'scoring_mode': 'ai',
      'practice_mode': '自定义批改·$_questionType·$title',
      'ai_answer': _referenceController.text.trim().isNotEmpty
          ? _referenceController.text.trim()
          : null,
      'ai_analysis': analysis,
      'created_at': now.toIso8601String(),
    });
    await _db.updateUserStats(
      addPractice: 1,
      lastDate: now.toIso8601String().substring(0, 10),
    );

    if (!mounted) return;
    setState(() => _historySaved = true);
    _showMessage('已保存到历史习题。');
  }

  String _buildHistoryTitle(String question) {
    final normalized = question
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ');
    if (_fileName?.isNotEmpty == true) return _fileName!;
    if (normalized.isEmpty) return '自定义题目';
    return normalized.length > 32 ? '${normalized.substring(0, 32)}...' : normalized;
  }

  String _formatHistoryAnalysis(String question, ScoreResult result) {
    final buffer = StringBuffer();
    if (_fileName?.isNotEmpty == true) {
      buffer.writeln('上传文件：$_fileName');
      buffer.writeln();
    }
    buffer
      ..writeln('题目内容：')
      ..writeln(question)
      ..writeln()
      ..write(_formatResultForCopy(result));
    return buffer.toString().trim();
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('批改题目'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildUploadCard(),
              const SizedBox(height: 16),
              _buildQuestionForm(),
              const SizedBox(height: 16),
              _buildAnswerForm(),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _scoring ? null : _scoreWithAI,
                  icon:
                      _scoring
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(_scoring ? 'AI 批改中...' : '开始 AI 批改'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE94560),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              if (_result != null) ...[
                const SizedBox(height: 22),
                _buildResult(_result!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.upload_file_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '上传题目文件',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '支持图片、Word、PDF，抽取后可继续编辑题干',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_fileName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '当前文件：$_fileName',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          if (_warning != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _warning!,
                style: const TextStyle(
                  color: Color(0xFFFFD166),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: _extracting ? null : _pickFile,
              icon:
                  _extracting
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.folder_open_rounded, size: 18),
              label: Text(_extracting ? '正在读取文件...' : '选择文件'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white30),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionForm() {
    return _panel(
      title: '题目设置',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _questionType,
                  decoration: _inputDecoration('题型'),
                  items:
                      _questionTypes.keys
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _questionType = value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _wordLimitController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration('字数上限'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _questionController,
            minLines: 8,
            maxLines: 14,
            decoration: _inputDecoration('题干 / 材料 / 作答要求'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _referenceController,
            minLines: 3,
            maxLines: 6,
            decoration: _inputDecoration('参考答案（可选，没有也可以 AI 批改）'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerForm() {
    return _panel(
      title: '我的作答',
      child: TextField(
        controller: _answerController,
        minLines: 10,
        maxLines: 18,
        decoration: _inputDecoration('在这里输入或粘贴你的答案'),
      ),
    );
  }

  Widget _buildResult(ScoreResult result) {
    return _panel(
      title: 'AI 批改结果',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  '${result.score}/${result.totalScore}',
                  style: const TextStyle(
                    color: Color(0xFFE94560),
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  result.feedback,
                  style: const TextStyle(color: Colors.white70, height: 1.6),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (result.breakdown.isNotEmpty) ...[
            const Text(
              '维度得分',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  result.breakdown.entries
                      .map(
                        (entry) => Chip(
                          label: Text('${entry.key} ${entry.value}'),
                          backgroundColor: const Color(
                            0xFF4ECDC4,
                          ).withOpacity(0.12),
                          side: BorderSide.none,
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 16),
          ],
          if (result.details.isNotEmpty) _section('详细分析', result.details),
          if (result.weaknesses.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              '主要问题',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE94560),
              ),
            ),
            const SizedBox(height: 8),
            ...result.weaknesses.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '- ',
                      style: TextStyle(color: Color(0xFFE94560)),
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (result.analyses.values.any((value) => value.isNotEmpty)) ...[
            const SizedBox(height: 16),
            const Text(
              '名师点评',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...result.analyses.entries
                .where((entry) => entry.value.isNotEmpty)
                .map(_teacherAnalysis),
          ],
          if (result.suggestion.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section('综合建议', result.suggestion),
          ],
          const SizedBox(height: 12),
          if (_historySaved)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF00B894).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF00B894)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '已保存到历史习题，并同步更新总答题数量',
                      style: TextStyle(fontSize: 12, color: Color(0xFF00B894)),
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                final text = _formatResultForCopy(result);
                Clipboard.setData(ClipboardData(text: text));
                _showMessage('批改结果已复制。');
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('复制结果'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _teacherAnalysis(MapEntry<String, String> entry) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFA29BFE).withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: _teacherColor(entry.key), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.key,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _teacherColor(entry.key),
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            entry.value,
            style: const TextStyle(fontSize: 13, height: 1.7),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SelectableText(
          content,
          style: const TextStyle(fontSize: 13, height: 1.75),
        ),
      ],
    );
  }

  Widget _panel({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      alignLabelWithHint: true,
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE94560), width: 1.5),
      ),
    );
  }

  Color _teacherColor(String name) {
    switch (name) {
      case '袁东':
        return const Color(0xFFE94560);
      case '白鹭':
        return const Color(0xFF4ECDC4);
      case '飞扬':
        return const Color(0xFFA29BFE);
      case '小马哥':
        return const Color(0xFFFFB347);
      case '忠政':
        return const Color(0xFF1A5276);
      default:
        return const Color(0xFF6C5CE7);
    }
  }

  String _formatResultForCopy(ScoreResult result) {
    final buffer =
        StringBuffer()
          ..writeln('得分：${result.score}/${result.totalScore}')
          ..writeln('总评：${result.feedback}');
    if (result.details.isNotEmpty) buffer.writeln('\n详细分析：\n${result.details}');
    if (result.weaknesses.isNotEmpty)
      buffer.writeln('\n主要问题：\n${result.weaknesses.join('\n')}');
    if (result.suggestion.isNotEmpty)
      buffer.writeln('\n综合建议：\n${result.suggestion}');
    return buffer.toString().trim();
  }
}
