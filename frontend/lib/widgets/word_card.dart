/// Word card widget — displays token details (reading, POS, base form).
library;

import 'package:flutter/material.dart';
import '../models/analysis_result.dart';
import '../theme/font_styles.dart';

class WordCard extends StatelessWidget {
  final List<Token> tokens;
  final Map<String, String> wordMeanings;

  static const Map<String, String> _posZhMap = {
    '動詞': '动词',
    '名詞': '名词',
    '形容詞': '形容词',
    '副詞': '副词',
    '助詞': '助词',
    '助動詞': '助动词',
    '接続詞': '接续词',
    '記号': '符号',
    '感動詞': '感叹词',
    '連体詞': '连体词',
    '接頭辞': '接头辞',
    '接尾辞': '接尾辞',
  };

  const WordCard({
    super.key,
    required this.tokens,
    this.wordMeanings = const {},
  });

  @override
  Widget build(BuildContext context) {
    final displayTokens = _filteredTokens(tokens);
    if (displayTokens.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('分词详情', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: displayTokens
              .map((t) => _buildCard(t, _resolveMeaning(t)))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildCard(Token t, String? meaningZh) {
    final posColor = _posColor(t.pos);
    final posLabel = _toZhPos(t.pos);
    final reading = _normalizeReading(t.reading);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: posColor.withAlpha(30),
        border: Border.all(color: posColor.withAlpha(100)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (reading.isNotEmpty)
            Text(
              reading,
              style: jaTextStyle(
                const TextStyle(),
                fontSize: 10,
                color: const Color(0xFFA6ADC8),
              ),
            ),
          Text(
            t.surface,
            style: cjkTextStyle(
              t.surface,
              const TextStyle(),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            posLabel,
            style: zhTextStyle(
              const TextStyle(),
              fontSize: 10,
              color: posColor,
            ),
          ),
          if (meaningZh != null && meaningZh.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                meaningZh,
                style: zhTextStyle(
                  const TextStyle(),
                  fontSize: 11,
                  color: const Color(0xFFBAC2DE),
                ),
              ),
            ),
          if (t.base.isNotEmpty && t.base != t.surface)
            Text(
              '(${t.base})',
              style: cjkTextStyle(
                t.base,
                const TextStyle(),
                fontSize: 10,
                color: const Color(0xFFA6ADC8),
              ),
            ),
        ],
      ),
    );
  }

  List<Token> _filteredTokens(List<Token> source) {
    final out = <Token>[];
    for (var i = 0; i < source.length; i++) {
      if (_shouldShowToken(source, i)) {
        out.add(source[i]);
      }
    }
    return out;
  }

  bool _shouldShowToken(List<Token> source, int index) {
    final t = source[index];
    final surface = t.surface.trim();
    if (surface.isEmpty) return false;

    if (_isPunctuationToken(t, surface)) return false;
    if (!_containsJapanese(surface)) return false;
    if (_isJlptMarkerToken(source, index)) return false;
    if (_isUnknownAsciiToken(t, surface)) return false;

    return true;
  }

  bool _isPunctuationToken(Token t, String surface) {
    if (t.pos.contains('補助記号')) return true;
    return RegExp(r'^[、。！？，．,.!?;:：；「」『』（）()［］【】《》〈〉…・ー]+$').hasMatch(surface);
  }

  bool _isJlptMarkerToken(List<Token> source, int index) {
    final current = source[index].surface.trim();
    if (RegExp(r'^[Nn][1-5]$').hasMatch(current)) {
      return true;
    }

    if (RegExp(r'^[Nn]$').hasMatch(current)) {
      if (index + 1 < source.length &&
          RegExp(r'^[1-5]$').hasMatch(source[index + 1].surface.trim())) {
        return true;
      }
    }

    if (RegExp(r'^[1-5]$').hasMatch(current)) {
      if (index - 1 >= 0 &&
          RegExp(r'^[Nn]$').hasMatch(source[index - 1].surface.trim())) {
        return true;
      }
    }

    return false;
  }

  bool _isUnknownAsciiToken(Token t, String surface) {
    final hasNoneMeta = [t.reading, t.base, t.posDetail]
        .map((s) => s.trim().toLowerCase())
        .any((s) => s == 'none' || s == '(none)');
    return hasNoneMeta && RegExp(r'^[A-Za-z0-9]+$').hasMatch(surface);
  }

  String _normalizeReading(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final lower = value.toLowerCase();
    if (lower == 'none' || lower == '(none)' || value == '(None)') {
      return '';
    }
    return kataToHira(value);
  }

  bool _containsJapanese(String value) {
    return RegExp(r'[\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF々〆ヶ]')
        .hasMatch(value);
  }

  String _toZhPos(String pos) {
    final raw = pos.trim();
    if (raw.isEmpty) return '';
    for (final entry in _posZhMap.entries) {
      if (raw.contains(entry.key)) {
        return entry.value;
      }
    }
    return raw;
  }

  String? _resolveMeaning(Token t) {
    final surface = t.surface.trim();
    final base = t.base.trim();
    if (surface.isNotEmpty && wordMeanings.containsKey(surface)) {
      return wordMeanings[surface]?.trim();
    }
    if (base.isNotEmpty && wordMeanings.containsKey(base)) {
      return wordMeanings[base]?.trim();
    }
    return null;
  }

  Color _posColor(String pos) {
    if (pos.contains('動詞')) return const Color(0xFF89B4FA);
    if (pos.contains('名詞')) return const Color(0xFFA6E3A1);
    if (pos.contains('形容詞')) return const Color(0xFFFAB387);
    if (pos.contains('副詞')) return const Color(0xFFCBA6F7);
    if (pos.contains('助詞')) return const Color(0xFF94E2D5);
    if (pos.contains('助動詞')) return const Color(0xFFF5C2E7);
    if (pos.contains('接続詞')) return const Color(0xFF89DCEB);
    return const Color(0xFF585B70);
  }
}
