/// Grammar tree widget — displays hierarchical grammar relationships.
library;

import 'package:flutter/material.dart';
import '../models/analysis_result.dart';

class GrammarTree extends StatelessWidget {
  final List<GrammarTreeNode> nodes;

  const GrammarTree({super.key, required this.nodes});

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('语法层级关系', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...nodes.map((n) => _buildNode(n, 0)),
      ],
    );
  }

  Widget _buildNode(GrammarTreeNode node, int depth) {
    final indent = depth * 20.0;
    final prefix = depth == 0 ? '' : (depth == 1 ? '  ├─ ' : '     └─ ');
    final color = depth == 0
        ? Colors.amber
        : depth == 1
            ? Colors.lightBlueAccent
            : Colors.grey[400];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: indent, bottom: 2),
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: prefix,
                  style: TextStyle(color: Colors.grey[600], fontFamily: 'monospace'),
                ),
                TextSpan(
                  text: node.label,
                  style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (node.note.isNotEmpty)
                  TextSpan(
                    text: '  (${node.note})',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
        ...node.children.map((c) => _buildNode(c, depth + 1)),
      ],
    );
  }
}
