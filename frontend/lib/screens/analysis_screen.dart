/// Main analysis screen — assembles all widgets and handles user input.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../widgets/grammar_highlight.dart';
import '../widgets/word_card.dart';
import '../widgets/core_grammar_view.dart';
import '../widgets/sentence_breakdown.dart';
import '../widgets/grammar_tree.dart';
import '../widgets/comparison_table.dart';
import '../widgets/common_mistakes_view.dart';
import 'settings_screen.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submit(WebSocketService ws) {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      ws.sendText(text);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日语语法解析器'),
        actions: [
          // Connection indicator
          Consumer<WebSocketService>(
            builder: (_, ws, __) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: ws.connected ? Colors.greenAccent : Colors.redAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    ws.connected ? '已连接' : '未连接',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          // Left panel: history
          SizedBox(
            width: 200,
            child: _buildHistory(),
          ),
          const VerticalDivider(width: 1),
          // Main content
          Expanded(
            child: Column(
              children: [
                // Input bar
                _buildInputBar(),
                const Divider(height: 1),
                // Analysis results
                Expanded(child: _buildResults()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Consumer<WebSocketService>(
      builder: (_, ws, __) => Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: '输入日文，或从 LunaTranslator 自动获取...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
                onSubmitted: (_) => _submit(ws),
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _submit(ws),
              icon: const Icon(Icons.send, size: 18),
              label: const Text('解析'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    return Consumer<WebSocketService>(
      builder: (_, ws, __) {
        final state = ws.state;
        final basic = state.basic;
        final deep = state.deep;

        if (basic == null) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.translate, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('等待日文输入...',
                    style: TextStyle(color: Colors.grey, fontSize: 16)),
                SizedBox(height: 8),
                Text('从 LunaTranslator 复制文本或在上方输入',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Original text with grammar highlighting
              GrammarHighlight(
                text: basic.text,
                matches: basic.grammarMatches,
                annotations: deep?.levelAnnotations ?? [],
              ),
              const SizedBox(height: 16),

              // Tokens (word cards)
              WordCard(tokens: basic.tokens),
              const SizedBox(height: 16),

              // Deep analysis loading indicator
              if (state.isLoadingDeep && deep == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('正在进行深度分析...',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),

              // Deep analysis sections
              if (deep != null) ...[
                const Divider(height: 32),
                CoreGrammarView(points: deep.coreGrammar),
                const SizedBox(height: 16),
                SentenceBreakdown(components: deep.sentenceBreakdown),
                const SizedBox(height: 16),
                GrammarTree(nodes: deep.grammarTree),
                const SizedBox(height: 16),
                ComparisonTable(groups: deep.comparisons),
                const SizedBox(height: 16),
                CommonMistakesView(mistakes: deep.commonMistakes),
                if (deep.culturalContext.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildSection('Cultural Context', deep.culturalContext),
                ],
                if (deep.applications.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildListSection('Applications', deep.applications),
                ],
              ],
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(content, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  Widget _buildListSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        ...items.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('  ', style: TextStyle(fontSize: 14)),
                  Expanded(child: Text(s, style: const TextStyle(fontSize: 14))),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildHistory() {
    return Consumer<WebSocketService>(
      builder: (_, ws, __) {
        final history = ws.history;
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              child: Text('历史记录 (${history.length})',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            const Divider(height: 1),
            Expanded(
              child: history.isEmpty
                  ? const Center(
                      child: Text('暂无记录', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: history.length,
                      itemBuilder: (_, i) {
                        final item = history[i];
                        return ListTile(
                          dense: true,
                          title: Text(
                            item.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                          onTap: () => ws.sendText(item.text),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
