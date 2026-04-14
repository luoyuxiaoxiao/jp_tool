/// Grammar highlight widget — displays original text with N1-N5 colored underlines.
library;

import 'package:flutter/material.dart';
import '../models/analysis_result.dart';
import 'jlpt_colors.dart';

class GrammarHighlight extends StatelessWidget {
  final String text;
  final List<GrammarMatch> matches;
  final List<LevelAnnotation> annotations;

  const GrammarHighlight({
    super.key,
    required this.text,
    this.matches = const [],
    this.annotations = const [],
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

    // Build TextSpans grouped by level
    final spans = <TextSpan>[];
    int i = 0;
    while (i < text.length) {
      final lvl = charLevels[i];
      int j = i + 1;
      while (j < text.length && charLevels[j] == lvl) {
        j++;
      }
      final segment = text.substring(i, j);
      spans.add(TextSpan(
        text: segment,
        style: TextStyle(
          fontSize: 22,
          color: Colors.white,
          decoration: lvl != null ? TextDecoration.underline : TextDecoration.none,
          decorationColor: lvl != null ? JlptColors.of(lvl) : null,
          decorationThickness: 3,
          decorationStyle: TextDecorationStyle.solid,
        ),
      ));
      i = j;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(text: TextSpan(children: spans)),
        const SizedBox(height: 8),
        _buildLegend(),
      ],
    );
  }

  Widget _buildLegend() {
    // Collect levels actually used
    final used = <String>{};
    for (final m in matches) {
      used.add(m.level);
    }
    for (final a in annotations) {
      used.add(a.level);
    }
    if (used.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 12,
      children: JlptColors.levelOrder
          .where((l) => used.contains(l))
          .map((l) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 14, height: 14, color: JlptColors.of(l)),
                  const SizedBox(width: 4),
                  Text(l, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                ],
              ))
          .toList(),
    );
  }
}
