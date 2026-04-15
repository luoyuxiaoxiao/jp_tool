/// Grammar highlight widget — displays original text with N1-N5 colored underlines.
library;

import 'package:flutter/material.dart';
import '../models/analysis_result.dart';
import 'jlpt_colors.dart';
import '../theme/font_styles.dart';

class GrammarHighlight extends StatelessWidget {
  final String text;
  final List<GrammarMatch> matches;
  final List<LevelAnnotation> annotations;
  final List<Token> tokens;

  const GrammarHighlight({
    super.key,
    required this.text,
    this.matches = const [],
    this.annotations = const [],
    this.tokens = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    // Build a list of character-level level assignments (prefer annotations over matches)
    final charLevels = List<String?>.filled(text.length, null);

    for (final a in annotations) {
      final end = a.end.clamp(0, text.length);
      final start = a.start.clamp(0, end);
      for (int i = start; i < end; i++) {
        charLevels[i] = a.level;
      }
    }
    for (final m in matches) {
      final end = m.end.clamp(0, text.length);
      final start = m.start.clamp(0, end);
      for (int i = start; i < end; i++) {
        charLevels[i] ??= m.level;
      }
    }

    final richTextFallback = _buildRichTextFallback(charLevels);
    final rubyText = _buildRubyText(charLevels);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        rubyText ?? richTextFallback,
        const SizedBox(height: 8),
        _buildLegend(),
      ],
    );
  }

  Widget _buildRichTextFallback(List<String?> charLevels) {
    final spans = <TextSpan>[];
    int i = 0;
    while (i < text.length) {
      final lvl = charLevels[i];
      int j = i + 1;
      while (j < text.length && charLevels[j] == lvl) {
        j++;
      }
      final segment = text.substring(i, j);
      spans.add(
        TextSpan(
          text: segment,
          style: cjkTextStyle(
            segment,
            const TextStyle(),
            fontSize: 22,
            color: Colors.white,
            decoration:
                lvl != null ? TextDecoration.underline : TextDecoration.none,
            decorationColor: lvl != null ? JlptColors.of(lvl) : null,
            decorationThickness: 3,
          ),
        ),
      );
      i = j;
    }
    return RichText(text: TextSpan(children: spans));
  }

  Widget? _buildRubyText(List<String?> charLevels) {
    if (tokens.isEmpty) {
      return null;
    }

    final items = <Widget>[];
    var cursor = 0;

    for (final token in tokens) {
      final surface = token.surface;
      if (surface.isEmpty) {
        continue;
      }

      var start = text.indexOf(surface, cursor);
      if (start < 0) {
        start = cursor;
      }
      final end = (start + surface.length).clamp(0, text.length);

      if (start > cursor) {
        _appendPlainSegments(items, cursor, start, charLevels);
      }

      final level = _firstLevel(charLevels, start, end);
      final reading = _normalizeReading(token.reading);
      if (_hasKanji(surface) && reading.isNotEmpty) {
        items.add(
          Padding(
            padding: const EdgeInsets.only(right: 3, bottom: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reading,
                  style: jaTextStyle(
                    const TextStyle(),
                    fontSize: 11,
                    color: const Color(0xFFA6ADC8),
                    height: 1.0,
                  ),
                ),
                Text(
                  surface,
                  style: cjkTextStyle(
                    surface,
                    const TextStyle(),
                    fontSize: 22,
                    color: Colors.white,
                    decoration: level != null
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    decorationColor:
                        level != null ? JlptColors.of(level) : null,
                    decorationThickness: 3,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        _appendPlainSegments(items, start, end, charLevels);
      }

      cursor = end;
    }

    if (cursor < text.length) {
      _appendPlainSegments(items, cursor, text.length, charLevels);
    }

    if (items.isEmpty) {
      return null;
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      children: items,
    );
  }

  void _appendPlainSegments(
    List<Widget> items,
    int start,
    int end,
    List<String?> charLevels,
  ) {
    if (start >= end) return;

    var i = start;
    while (i < end) {
      final level = charLevels[i];
      var j = i + 1;
      while (j < end && charLevels[j] == level) {
        j++;
      }

      final segment = text.substring(i, j);
      if (segment.isNotEmpty) {
        items.add(
          Padding(
            padding: const EdgeInsets.only(right: 1, bottom: 4),
            child: Text(
              segment,
              style: cjkTextStyle(
                segment,
                const TextStyle(),
                fontSize: 22,
                color: Colors.white,
                decoration: level != null
                    ? TextDecoration.underline
                    : TextDecoration.none,
                decorationColor: level != null ? JlptColors.of(level) : null,
                decorationThickness: 3,
              ),
            ),
          ),
        );
      }

      i = j;
    }
  }

  String? _firstLevel(List<String?> charLevels, int start, int end) {
    for (var i = start; i < end && i < charLevels.length; i++) {
      if (charLevels[i] != null) {
        return charLevels[i];
      }
    }
    return null;
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

  bool _hasKanji(String value) {
    return RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF]').hasMatch(value);
  }

  Widget _buildLegend() {
    final used = <String>{};
    for (final m in matches) {
      used.add(m.level);
    }
    for (final a in annotations) {
      used.add(a.level);
    }
    final hasUsed = used.isNotEmpty;

    return Wrap(
      spacing: 12,
      children: JlptColors.levelOrder.map((l) {
        final active = !hasUsed || used.contains(l);
        return Opacity(
          opacity: active ? 1.0 : 0.4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: JlptColors.of(l),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                l,
                style: zhTextStyle(
                  const TextStyle(),
                  fontSize: 12,
                  color: const Color(0xFFA6ADC8),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
