/// Core grammar display widget — shows each grammar point with level badge.
library;

import 'package:flutter/material.dart';
import '../models/analysis_result.dart';
import 'jlpt_colors.dart';
import '../theme/font_styles.dart';

class CoreGrammarView extends StatelessWidget {
  final List<GrammarPoint> points;

  const CoreGrammarView({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('核心语法解析', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...points.asMap().entries.map((e) => _buildPoint(e.key + 1, e.value)),
      ],
    );
  }

  Widget _buildPoint(int index, GrammarPoint p) {
    final color = JlptColors.of(p.level);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        border: Border(left: BorderSide(color: color, width: 3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('($index) ',
                  style: TextStyle(color: Colors.grey[400], fontSize: 14)),
              Text(
                p.grammar,
                style: cjkTextStyle(
                  p.grammar,
                  const TextStyle(),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  p.level,
                  style: zhTextStyle(
                    const TextStyle(),
                    fontSize: 11,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          if (p.structure.isNotEmpty) ...[
            const SizedBox(height: 4),
            _row('结构', p.structure),
          ],
          if (p.function.isNotEmpty) ...[
            const SizedBox(height: 2),
            _row('功能', p.function),
          ],
          if (p.comparison.isNotEmpty) ...[
            const SizedBox(height: 2),
            _row('对比', p.comparison),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 75,
          child: Text('$label:',
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ),
        Expanded(
          child: Text(
            value,
            style: cjkTextStyle(value, const TextStyle(), fontSize: 13),
          ),
        ),
      ],
    );
  }
}
