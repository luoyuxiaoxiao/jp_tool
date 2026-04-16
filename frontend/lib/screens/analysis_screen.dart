/// Main analysis screen - assembles all widgets and handles user input.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/analysis_result.dart';
import '../services/websocket_service.dart';
import '../utils/shortcut_utils.dart';
import '../widgets/grammar_highlight.dart';
import '../widgets/core_grammar_view.dart';
import '../widgets/sentence_breakdown.dart';
import '../widgets/grammar_tree.dart';
import '../widgets/comparison_table.dart';
import '../widgets/common_mistakes_view.dart';
import '../widgets/dependency_focus_view.dart';
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
  final _longTextScrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  String? _lastRenderedText;

  @override
  void dispose() {
    _inputFocusNode.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _longTextScrollController.dispose();
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

  Future<void> _refreshHistoryFromBackend(WebSocketService ws) async {
    await ws.refreshHistoryFromBackend();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已从后端刷新历史记录')),
    );
  }

  Future<void> _deleteHistoryItem(WebSocketService ws, BasicResult item) async {
    final preview =
        item.text.length > 60 ? '${item.text.substring(0, 60)}...' : item.text;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除历史记录'),
        content: Text('确认删除这条记录吗？\n\n$preview'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final ok = await ws.deleteHistoryItem(item.text);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? '历史记录已删除（已同步后端）' : '历史记录已删除（后端同步失败）',
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
                          Expanded(
                            child: ColoredBox(
                              color: const Color(0x6611151D),
                              child: _buildResults(),
                            ),
                          ),
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
                    ScaffoldMessenger.of(context).showSnackBar(
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
                const SizedBox(width: 16),
                const Text('跟随模式', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Switch(
                  value: ws.followModeEnabled,
                  onChanged: (value) async {
                    final ok = await ws.setFollowModeEnabled(value);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok ? (value ? '已开启跟随模式' : '已关闭跟随模式') : '切换失败，请检查后端连接',
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 6),
                Text(
                  ws.followModeEnabled ? '已开启' : '已关闭',
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        ws.followModeEnabled ? Colors.greenAccent : Colors.grey,
                  ),
                ),
                const SizedBox(width: 16),
                const Text('Luna预取', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Switch(
                  value: ws.resourceConfig.lunaWsEnabled,
                  onChanged: (value) async {
                    final ok = await ws.setLunaWsEnabled(value);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? (value ? '已开启 Luna 预取' : '已关闭 Luna 预取')
                              : '切换失败，请检查后端连接',
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 6),
                Text(
                  ws.resourceConfig.lunaWsEnabled ? '已开启' : '已关闭',
                  style: TextStyle(
                    fontSize: 13,
                    color: ws.resourceConfig.lunaWsEnabled
                        ? Colors.greenAccent
                        : Colors.grey,
                  ),
                ),
                const SizedBox(width: 16),
                const Text('分词', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  tooltip: 'GiNZA 分词等级',
                  onSelected: (mode) async {
                    final ok = await ws.setGinzaSplitMode(mode);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok ? 'GiNZA 分词等级已切换为 $mode' : '切换失败，请检查后端连接',
                        ),
                      ),
                    );
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'A',
                      child: Text('A（细粒度）'),
                    ),
                    PopupMenuItem(
                      value: 'B',
                      child: Text('B（平衡）'),
                    ),
                    PopupMenuItem(
                      value: 'C',
                      child: Text('C（粗粒度，阅读推荐）'),
                    ),
                  ],
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                      color: Colors.white10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'GiNZA ${ws.resourceConfig.ginzaSplitMode}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.arrow_drop_down, size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                PopupMenuButton<String>(
                  tooltip: '依存聚焦风格',
                  onSelected: (style) async {
                    final ok = await ws.setDependencyFocusStyle(style);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? '依存聚焦风格已切换为 ${style == 'vivid' ? 'vivid（炫彩）' : 'classic（经典）'}'
                              : '切换失败，请检查后端连接',
                        ),
                      ),
                    );
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'classic',
                      child: Text('classic（经典）'),
                    ),
                    PopupMenuItem(
                      value: 'vivid',
                      child: Text('vivid（炫彩）'),
                    ),
                  ],
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                      color: Colors.white10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ws.resourceConfig.dependencyFocusStyle == 'vivid'
                              ? '依存 vivid'
                              : '依存 classic',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.arrow_drop_down, size: 16),
                      ],
                    ),
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

        if (_lastRenderedText != basic.text) {
          _lastRenderedText = basic.text;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scrollController.hasClients) {
              return;
            }
            _scrollController.jumpTo(0);
          });
        }

        final hasLocalDetails =
            basic.grammarMatches.isNotEmpty || basic.tokens.isNotEmpty;
        final hasDeepDetails = deep != null;
        final showNoDetailsHint =
            !state.isLoadingDeep && !hasLocalDetails && !hasDeepDetails;

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
                tokens: basic.tokens,
              ),
              if (basic.tokens.isNotEmpty) ...[
                const SizedBox(height: 12),
                DependencyFocusView(
                  tokens: basic.tokens,
                  style: ws.resourceConfig.dependencyFocusStyle,
                ),
              ],
              if (showNoDetailsHint) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Text(
                    '已收到文本，但当前没有可展示的本地语法细节。\n'
                    '请检查后端日志或切换 LLM 配置后重试。',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ),
              ],
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
              controller: _longTextScrollController,
              thumbVisibility: content.length > 300,
              child: SingleChildScrollView(
                controller: _longTextScrollController,
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
              child: Row(
                children: [
                  Expanded(
                    child: Text('历史记录 (${history.length})',
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  IconButton(
                    tooltip: '从后端刷新历史',
                    onPressed: () => unawaited(_refreshHistoryFromBackend(ws)),
                    icon: const Icon(Icons.refresh, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
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
                          trailing: IconButton(
                            tooltip: '删除这条历史记录',
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18,
                            ),
                            onPressed: () =>
                                unawaited(_deleteHistoryItem(ws, item)),
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
