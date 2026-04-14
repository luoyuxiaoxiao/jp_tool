/// Main analysis screen - assembles all widgets and handles user input.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../utils/shortcut_utils.dart';
import '../widgets/grammar_highlight.dart';
import '../widgets/word_card.dart';
import '../widgets/core_grammar_view.dart';
import '../widgets/sentence_breakdown.dart';
import '../widgets/grammar_tree.dart';
import '../widgets/comparison_table.dart';
import '../widgets/common_mistakes_view.dart';
import 'settings_screen.dart';
import 'llm_config_screen.dart';
import 'shortcut_config_screen.dart';

class _ToggleClipboardIntent extends Intent {
  const _ToggleClipboardIntent();
}

class _ToggleGrammarAutoLearnIntent extends Intent {
  const _ToggleGrammarAutoLearnIntent();
}

class _SubmitAnalyzeIntent extends Intent {
  const _SubmitAnalyzeIntent();
}

class _FocusInputIntent extends Intent {
  const _FocusInputIntent();
}

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();

  @override
  void dispose() {
    _inputFocusNode.dispose();
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

  Future<void> _toggleClipboardByShortcut(WebSocketService ws) async {
    final target = !ws.clipboardEnabled;
    final ok = await ws.setClipboardEnabled(target);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? (target ? '快捷键：已开启剪贴板监听' : '快捷键：已关闭剪贴板监听') : '快捷键执行失败，请检查后端连接',
        ),
      ),
    );
  }

  Future<void> _toggleGrammarAutoLearnByShortcut(WebSocketService ws) async {
    final target = !ws.grammarAutoLearnEnabled;
    final ok = await ws.setGrammarAutoLearnEnabled(target);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? (target ? '快捷键：已开启语法自动学习' : '快捷键：已关闭语法自动学习') : '快捷键执行失败，请检查后端连接',
        ),
      ),
    );
  }

  Map<ShortcutActivator, Intent> _buildShortcuts(ShortcutConfig cfg) {
    final map = <ShortcutActivator, Intent>{};

    final toggle = parseShortcutActivator(cfg.toggleClipboard);
    if (toggle != null) {
      map[toggle] = const _ToggleClipboardIntent();
    }

    final toggleAutoLearn = parseShortcutActivator(cfg.toggleGrammarAutoLearn);
    if (toggleAutoLearn != null) {
      map[toggleAutoLearn] = const _ToggleGrammarAutoLearnIntent();
    }

    final submit = parseShortcutActivator(cfg.submitAnalyze);
    if (submit != null) {
      map[submit] = const _SubmitAnalyzeIntent();
    }

    final focusInput = parseShortcutActivator(cfg.focusInput);
    if (focusInput != null) {
      map[focusInput] = const _FocusInputIntent();
    }

    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(
      builder: (_, ws, __) {
        final shortcutMap = _buildShortcuts(ws.shortcutConfig);
        return Shortcuts(
          shortcuts: shortcutMap,
          child: Actions(
            actions: {
              _ToggleClipboardIntent: CallbackAction<_ToggleClipboardIntent>(
                onInvoke: (_) {
                  unawaited(_toggleClipboardByShortcut(ws));
                  return null;
                },
              ),
              _ToggleGrammarAutoLearnIntent:
                  CallbackAction<_ToggleGrammarAutoLearnIntent>(
                onInvoke: (_) {
                  unawaited(_toggleGrammarAutoLearnByShortcut(ws));
                  return null;
                },
              ),
              _SubmitAnalyzeIntent: CallbackAction<_SubmitAnalyzeIntent>(
                onInvoke: (_) {
                  _submit(ws);
                  return null;
                },
              ),
              _FocusInputIntent: CallbackAction<_FocusInputIntent>(
                onInvoke: (_) {
                  _inputFocusNode.requestFocus();
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('日语语法解析器'),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle,
                            size: 10,
                            color: ws.connected
                                ? Colors.greenAccent
                                : Colors.redAccent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            ws.connected ? '已连接' : '未连接',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard),
                      tooltip: '快捷键管理',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ShortcutConfigScreen()),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.tune),
                      tooltip: 'LLM/API配置',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const LlmConfigScreen()),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings),
                      tooltip: '设置',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()),
                      ),
                    ),
                  ],
                ),
                body: Row(
                  children: [
                    SizedBox(
                      width: 200,
                      child: _buildHistory(),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Column(
                        children: [
                          _buildInputBar(),
                          const Divider(height: 1),
                          Expanded(child: _buildResults()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Consumer<WebSocketService>(
      builder: (_, ws, __) => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _inputFocusNode,
                    decoration: const InputDecoration(
                      hintText: '输入日文，或从 LunaTranslator 自动获取...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
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
            const SizedBox(height: 6),
            Row(
              children: [
                const Text('剪贴板监听', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Switch(
                  value: ws.clipboardEnabled,
                  onChanged: (value) async {
                    final ok = await ws.setClipboardEnabled(value);
                    if (!mounted) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? (value ? '已开启剪贴板监听' : '已关闭剪贴板监听')
                              : '切换失败，请检查后端连接',
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 6),
                Text(
                  ws.clipboardEnabled ? '已开启' : '已关闭',
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        ws.clipboardEnabled ? Colors.greenAccent : Colors.grey,
                  ),
                ),
                const Spacer(),
                if (!ws.llmEnabled)
                  const Text(
                    '轻量模式：不进行深度分析',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
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
              GrammarHighlight(
                text: basic.text,
                matches: basic.grammarMatches,
                annotations: deep?.levelAnnotations ?? [],
              ),
              const SizedBox(height: 16),
              WordCard(tokens: basic.tokens),
              const SizedBox(height: 16),
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
                      Text('正在进行深度分析...', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
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
                  _buildLongTextSection('文化语境', deep.culturalContext),
                ],
                if (deep.applications.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildListSection('应用拓展', deep.applications),
                ],
              ],
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLongTextSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: Scrollbar(
              thumbVisibility: content.length > 300,
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        ...items.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(fontSize: 14)),
                Expanded(child: Text(s, style: const TextStyle(fontSize: 14))),
              ],
            ),
          ),
        ),
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
                      child: Text('暂无记录', style: TextStyle(color: Colors.grey)),
                    )
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
