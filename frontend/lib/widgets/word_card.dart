/// Word card widget — displays token details (reading, POS, base form).
library;

import 'package:flutter/material.dart';
import '../models/analysis_result.dart';

class WordCard extends StatelessWidget {
  final List<Token> tokens;

  const WordCard({super.key, required this.tokens});

  @override
  Widget build(BuildContext context) {
    if (tokens.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('分词详情', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: tokens
              .where((t) => t.surface.trim().isNotEmpty)
              .map((t) => _buildCard(t))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildCard(Token t) {
    final posColor = _posColor(t.pos);
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
          if (t.reading.isNotEmpty)
            Text(t.reading, style: TextStyle(fontSize: 10, color: Colors.grey[400])),
          Text(t.surface, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text(
            t.pos,
            style: TextStyle(fontSize: 10, color: posColor),
          ),
          if (t.base.isNotEmpty && t.base != t.surface)
            Text('(${t.base})', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Color _posColor(String pos) {
    if (pos.contains('動詞')) return Colors.blue;
    if (pos.contains('名詞')) return Colors.green;
    if (pos.contains('形容詞')) return Colors.orange;
    if (pos.contains('副詞')) return Colors.purple;
    if (pos.contains('助詞')) return Colors.teal;
    if (pos.contains('助動詞')) return Colors.pink;
    if (pos.contains('接続詞')) return Colors.cyan;
    return Colors.grey;
  }
}
