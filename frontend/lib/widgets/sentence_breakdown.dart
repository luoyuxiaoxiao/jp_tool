/// Sentence breakdown widget — shows each fragment with its grammatical role.
library;

import 'package:flutter/material.dart';
import '../models/analysis_result.dart';

class SentenceBreakdown extends StatelessWidget {
  final List<SentenceComponent> components;

  const SentenceBreakdown({super.key, required this.components});

  @override
  Widget build(BuildContext context) {
    if (components.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('句子结构分解', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...components.asMap().entries.map((entry) {
          final i = entry.key;
          final c = entry.value;
          final isLast = i == components.length - 1;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isLast) const Text('+ ', style: TextStyle(color: Colors.grey, fontSize: 16)),
                if (isLast) const Text('= ', style: TextStyle(color: Colors.amber, fontSize: 16)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    c.fragment,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    c.role,
                    style: TextStyle(fontSize: 13, color: Colors.grey[300]),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
