/// Common mistakes widget.
library;

import 'package:flutter/material.dart';
import '../models/analysis_result.dart';

class CommonMistakesView extends StatelessWidget {
  final List<CommonMistake> mistakes;

  const CommonMistakesView({super.key, required this.mistakes});

  @override
  Widget build(BuildContext context) {
    if (mistakes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('常见错误', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...mistakes.map(_buildMistake),
      ],
    );
  }

  Widget _buildMistake(CommonMistake m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(15),
        border: Border.all(color: Colors.red.withAlpha(60)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.close, color: Colors.redAccent, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(m.wrong,
                    style: const TextStyle(
                        color: Colors.redAccent,
                        decoration: TextDecoration.lineThrough,
                        fontSize: 14)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 2),
            child: Text('问题：${m.problem}',
                style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          ),
          Row(
            children: [
              const Icon(Icons.check, color: Colors.greenAccent, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(m.correct,
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 14)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
