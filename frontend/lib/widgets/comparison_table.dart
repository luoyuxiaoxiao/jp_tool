/// Comparison table widget — shows near-synonym expression comparisons.
library;

import 'package:flutter/material.dart';
import '../models/analysis_result.dart';

class ComparisonTable extends StatelessWidget {
  final List<ComparisonGroup> groups;

  const ComparisonTable({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('近义表达对比', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...groups.map(_buildGroup),
      ],
    );
  }

  Widget _buildGroup(ComparisonGroup group) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withAlpha(60),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(_categoryZh(group.category),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(height: 6),
          Table(
            border: TableBorder.all(color: Colors.grey.shade700, width: 0.5),
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(3),
              2: FlexColumnWidth(2),
            },
            children: [
              const TableRow(
                decoration: BoxDecoration(color: Colors.white10),
                children: [
                  _Cell('表达', header: true),
                  _Cell('例句', header: true),
                  _Cell('特征', header: true),
                ],
              ),
              ...group.items.map((item) => TableRow(children: [
                    _Cell(item.expression),
                    _Cell(item.example),
                    _Cell(item.score.isNotEmpty ? item.score : item.note),
                  ])),
            ],
          ),
        ],
      ),
    );
  }

  String _categoryZh(String category) {
    final c = category.toLowerCase();
    if (c.contains('culture')) return '文化语境';
    if (c.contains('condition')) return '条件表达差异';
    if (c.contains('emotion') || c.contains('psycholog')) return '心理变化表达';
    if (c.contains('honorific') || c.contains('polite')) return '敬语与礼貌表达';
    return category;
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final bool header;

  const _Cell(this.text, {this.header = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SelectableText(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: header ? FontWeight.bold : FontWeight.normal,
          color: header ? Colors.amber : null,
        ),
      ),
    );
  }
}
