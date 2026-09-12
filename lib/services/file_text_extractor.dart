import 'dart:convert' show latin1, utf8;
import 'dart:io';

import 'package:archive/archive.dart';

import 'ocr_service.dart';

class ExtractedFileText {
  final String fileName;
  final String extension;
  final String text;
  final String? warning;

  const ExtractedFileText({
    required this.fileName,
    required this.extension,
    required this.text,
    this.warning,
  });
}

class FileTextExtractor {
  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  static Future<ExtractedFileText> extract({
    required String path,
    required String fileName,
    required String apiKey,
  }) async {
    final extension = _extensionOf(fileName.isNotEmpty ? fileName : path);
    final file = File(path);
    if (!await file.exists()) {
      return ExtractedFileText(
        fileName: fileName,
        extension: extension,
        text: '',
        warning: '文件不存在，请重新选择。',
      );
    }

    if (_imageExtensions.contains(extension)) {
      if (apiKey.isEmpty) {
        return ExtractedFileText(
          fileName: fileName,
          extension: extension,
          text: '',
          warning: '图片题目需要先在“我的-DeepSeek API Key”中配置 API Key，才能进行 OCR 识别。',
        );
      }
      final text = await OcrService.extractText(
        imagePath: path,
        apiKey: apiKey,
      );
      return ExtractedFileText(
        fileName: fileName,
        extension: extension,
        text: text ?? '',
        warning: text == null ? '图片文字识别失败，请手动粘贴或输入题干。' : null,
      );
    }

    if (extension == 'docx') {
      return ExtractedFileText(
        fileName: fileName,
        extension: extension,
        text: await _extractDocx(file),
      );
    }

    if (extension == 'doc') {
      return ExtractedFileText(
        fileName: fileName,
        extension: extension,
        text: '',
        warning: '暂不支持解析旧版 .doc 二进制正文，请另存为 .docx 后上传，或直接粘贴题干。',
      );
    }

    if (extension == 'pdf') {
      final text = await _extractPdf(file);
      return ExtractedFileText(
        fileName: fileName,
        extension: extension,
        text: text,
        warning:
            text.isEmpty ? '未能从 PDF 中提取到可用文字。扫描版 PDF 请先转图片 OCR，或手动粘贴题干。' : null,
      );
    }

    return ExtractedFileText(
      fileName: fileName,
      extension: extension,
      text: '',
      warning: '暂不支持 .$extension 文件，请选择图片、Word 或 PDF。',
    );
  }

  static String _extensionOf(String name) {
    final index = name.lastIndexOf('.');
    if (index < 0 || index == name.length - 1) return '';
    return name.substring(index + 1).toLowerCase();
  }

  static Future<String> _extractDocx(File file) async {
    try {
      final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
      final parts = <String>[];
      for (final name in [
        'word/document.xml',
        'word/header1.xml',
        'word/footer1.xml',
      ]) {
        final entry = archive.findFile(name);
        if (entry == null) continue;
        parts.add(
          _docxXmlToText(utf8.decode(entry.content, allowMalformed: true)),
        );
      }
      return _cleanText(parts.join('\n'));
    } catch (_) {
      return '';
    }
  }

  static String _docxXmlToText(String xml) {
    final buffer = StringBuffer();
    final paragraphBlocks = RegExp(r'<w:p[\s\S]*?</w:p>').allMatches(xml);
    for (final paragraph in paragraphBlocks) {
      final paragraphXml = paragraph.group(0) ?? '';
      for (final textNode in RegExp(
        r'<w:t[^>]*>([\s\S]*?)</w:t>',
      ).allMatches(paragraphXml)) {
        buffer.write(_decodeXml(textNode.group(1) ?? ''));
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  static String _decodeXml(String text) {
    return text
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }

  static Future<String> _extractPdf(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final raw = latin1.decode(bytes, allowInvalid: true);
      final chunks = <String>[raw, ..._decodePdfStreams(raw)];
      final buffer = StringBuffer();
      for (final chunk in chunks) {
        buffer.writeln(_extractPdfTextOperators(chunk));
      }
      return _cleanText(buffer.toString());
    } catch (_) {
      return '';
    }
  }

  static List<String> _decodePdfStreams(String raw) {
    final decoded = <String>[];
    final streamPattern = RegExp(r'stream\r?\n([\s\S]*?)\r?\nendstream');
    for (final match in streamPattern.allMatches(raw)) {
      final stream = match.group(1);
      if (stream == null || stream.isEmpty) continue;
      try {
        final bytes = latin1.encode(stream);
        decoded.add(
          latin1.decode(ZLibDecoder().decodeBytes(bytes), allowInvalid: true),
        );
      } catch (_) {
        // Some PDF streams are encrypted or use filters other than FlateDecode.
      }
    }
    return decoded;
  }

  static String _extractPdfTextOperators(String chunk) {
    final buffer = StringBuffer();

    for (final match in RegExp(r'\((?:\\.|[^\\)])*\)').allMatches(chunk)) {
      final literal = match.group(0);
      if (literal == null || literal.length < 2) continue;
      buffer.write(_decodePdfLiteral(literal.substring(1, literal.length - 1)));
      buffer.write(' ');
    }

    for (final match in RegExp(r'<([0-9A-Fa-f\s]{4,})>').allMatches(chunk)) {
      final hex = match.group(1);
      if (hex == null) continue;
      final text = _decodePdfHex(hex);
      if (text.trim().isNotEmpty) {
        buffer.write(text);
        buffer.write(' ');
      }
    }

    return buffer.toString();
  }

  static String _decodePdfLiteral(String value) {
    return value
        .replaceAll(r'\(', '(')
        .replaceAll(r'\)', ')')
        .replaceAll(r'\\', r'\')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\n')
        .replaceAll(r'\t', '\t');
  }

  static String _decodePdfHex(String hex) {
    final cleaned = hex.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.length < 4 || cleaned.length.isOdd) return '';
    final bytes = <int>[];
    for (var i = 0; i < cleaned.length; i += 2) {
      final byte = int.tryParse(cleaned.substring(i, i + 2), radix: 16);
      if (byte != null) bytes.add(byte);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final units = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        units.add((bytes[i] << 8) + bytes[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    return latin1.decode(bytes, allowInvalid: true);
  }

  static String _cleanText(String text) {
    return text
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
