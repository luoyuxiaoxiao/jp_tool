/// Settings screen — configure server URL, LLM provider, etc.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import 'llm_config_screen.dart';
import 'shortcut_config_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;
  late TextEditingController _backendPortController;
  late TextEditingController _dictPathController;
  late TextEditingController _ginzaPathController;
  late TextEditingController _onnxPathController;
  late TextEditingController _lunaWsController;
  late TextEditingController _queueMaxPendingController;
  final ScrollController _backendLogScrollController = ScrollController();
  bool _dropPrefetchWhenBusy = true;
  String _ginzaSplitMode = 'C';
  String _dependencyFocusStyle = 'classic';
  bool _savingResources = false;

  @override
  void initState() {
    super.initState();
    final ws = context.read<WebSocketService>();
    _urlController = TextEditingController(text: ws.serverUrl);
    _backendPortController = TextEditingController(
      text: _extractLocalPort(ws.serverUrl).toString(),
    );
    _dictPathController = TextEditingController();
    _ginzaPathController = TextEditingController(text: 'ja_ginza_electra');
    _onnxPathController = TextEditingController();
    _lunaWsController = TextEditingController();
    _queueMaxPendingController = TextEditingController(text: '120');
    unawaited(ws.refreshServerStatus());
    unawaited(_loadExternalResourceConfig());
  }

  @override
  void dispose() {
    _urlController.dispose();
    _backendPortController.dispose();
    _dictPathController.dispose();
    _ginzaPathController.dispose();
    _onnxPathController.dispose();
    _lunaWsController.dispose();
    _queueMaxPendingController.dispose();
    _backendLogScrollController.dispose();
    super.dispose();
  }

  int _extractLocalPort(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.hasPort) {
        return uri.port;
      }
    } catch (_) {
      // ignore parse errors
    }
    return 8765;
  }

  Future<void> _applyLocalBackendPort() async {
    final port = int.tryParse(_backendPortController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('端口号无效，请输入 1-65535')),
      );
      return;
    }

    final ws = context.read<WebSocketService>();
    final targetUrl = 'ws://127.0.0.1:$port/ws';
    _urlController.text = targetUrl;
    ws.connect(url: targetUrl);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已切换后端端口到 $port，正在重连...')),
    );
  }

  Future<void> _loadExternalResourceConfig() async {
    final ws = context.read<WebSocketService>();
    final cfg = await ws.getResourceConfig();
    if (!mounted || cfg == null) return;

    setState(() {
      _dictPathController.text = cfg.dictionaryDbPath;
      _ginzaPathController.text = cfg.ginzaModelPath.trim().isNotEmpty
          ? cfg.ginzaModelPath
          : 'ja_ginza_electra';
      _ginzaSplitMode = _normalizeGinzaSplitMode(cfg.ginzaSplitMode);
      _dependencyFocusStyle =
          _normalizeDependencyFocusStyle(cfg.dependencyFocusStyle);
      _onnxPathController.text = cfg.onnxModelPath;
      _lunaWsController.text = cfg.lunaWsOriginUrl;
      _queueMaxPendingController.text = cfg.queueMaxPending.toString();
      _dropPrefetchWhenBusy = cfg.queueDropPrefetchWhenBusy;
    });
  }

  Future<void> _saveExternalResourceConfig() async {
    if (_savingResources) return;
    setState(() => _savingResources = true);

    final ws = context.read<WebSocketService>();
    final queueMax =
        int.tryParse(_queueMaxPendingController.text.trim()) ?? 120;
    final ok = await ws.saveResourceConfig(
      ExternalResourceConfig(
        dictionaryDbPath: _dictPathController.text.trim(),
        ginzaModelPath: _ginzaPathController.text.trim(),
        ginzaSplitMode: _ginzaSplitMode,
        dependencyFocusStyle: _dependencyFocusStyle,
        onnxModelPath: _onnxPathController.text.trim(),
        lunaWsEnabled: ws.resourceConfig.lunaWsEnabled,
        lunaWsOriginUrl: _lunaWsController.text.trim(),
        queueMaxPending: queueMax.clamp(10, 5000),
        queueDropPrefetchWhenBusy: _dropPrefetchWhenBusy,
      ),
    );

    if (!mounted) return;
    setState(() => _savingResources = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '外置资源配置已保存' : '保存失败，请检查后端连接')),
    );
  }

  void _showResourceHelpDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('外置资源配置说明'),
        content: const Text(
          '用于配置不打包进程序的重资源路径。\n\n'
          '词典库路径：例如 JMdict SQLite 文件。\n'
          'GiNZA 模型路径：可选深度模式使用。\n'
          'GiNZA 分词等级：A 最细、B 中等、C 最粗（阅读场景推荐 C）。\n'
          '依存聚焦风格：classic 经典 / vivid 炫彩。\n'
          'ONNX 模型路径：后续优化预留。\n'
          'Luna WebSocket 原文流：可直接填端口（如 2333），也可填完整 ws 地址。\n'
          'Luna 预取开关：请在主界面“跟随模式”旁边切换。\n\n'
          '保存后路径将写入后端 SQLite，供后续分析任务调用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Server connection
          Text('服务器连接', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'WebSocket 地址',
              hintText: 'ws://localhost:8765/ws',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              final ws = context.read<WebSocketService>();
              ws.connect(url: _urlController.text.trim());
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('正在重新连接...')),
              );
            },
            child: const Text('重新连接'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _backendPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '本地后端端口（快速设置）',
                    hintText: '8765',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _applyLocalBackendPort,
                child: const Text('应用端口'),
              ),
            ],
          ),
          Consumer<WebSocketService>(
            builder: (_, ws, __) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('前端启动时自动拉起后端'),
              subtitle: Text(
                ws.autoStartBackend ? '当前开启：优先尝试拉起本地后端' : '当前关闭：仅尝试连接已运行后端',
              ),
              value: ws.autoStartBackend,
              onChanged: (value) async {
                await ws.setAutoStartBackend(value);
              },
            ),
          ),

          const SizedBox(height: 16),
          Consumer<WebSocketService>(
            builder: (_, ws, __) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('窗口材质效果', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: ws.windowEffect,
                  decoration: const InputDecoration(
                    labelText: '窗口效果',
                    border: OutlineInputBorder(),
                  ),
                  items: ws.windowEffectValues
                      .map(
                        (v) => DropdownMenuItem<String>(
                          value: v,
                          child: Text(_windowEffectLabel(v)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    await ws.setWindowEffect(value);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                              Text('窗口效果已切换为：${_windowEffectLabel(value)}')),
                    );
                  },
                ),
                const SizedBox(height: 4),
                const Text(
                  '仅保留差异明显的材质：Transparent / Mica / Disabled',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Text('后端日志', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用后端日志'),
                  subtitle: Text(ws.backendLogEnabled
                      ? '当前开启：展示后端 stdout/stderr（最多保留 600 行）'
                      : '当前关闭：不显示后端日志输出'),
                  value: ws.backendLogEnabled,
                  onChanged: (value) async {
                    await ws.setBackendLogEnabled(value);
                  },
                ),
                if (ws.backendLogEnabled) ...[
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('清空日志'),
                        onPressed: () async {
                          await ws.clearBackendLogs();
                        },
                      ),
                      const SizedBox(width: 8),
                      Text('日志行数：${ws.backendLogs.length}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    height: 180,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.black.withAlpha(70),
                    ),
                    child: Scrollbar(
                      controller: _backendLogScrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _backendLogScrollController,
                        itemCount: ws.backendLogs.length,
                        itemBuilder: (_, index) {
                          final line = ws.backendLogs[index];
                          return SelectableText(
                            line,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.25,
                              color: Colors.white70,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
                if (ws.managedBackendError != null &&
                    ws.managedBackendError!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '后端状态：${ws.managedBackendError}',
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
          Consumer<WebSocketService>(
            builder: (_, ws, __) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用剪贴板自动监听'),
              subtitle: Text(
                ws.clipboardEnabled ? '当前开启，复制日文会自动解析' : '当前关闭，仅手动输入或Luna推送',
              ),
              value: ws.clipboardEnabled,
              onChanged: (value) async {
                final ok = await ws.setClipboardEnabled(value);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? (value ? '已开启剪贴板监听' : '已关闭剪贴板监听')
                        : '切换失败，请检查后端连接'),
                  ),
                );
              },
            ),
          ),

          Consumer<WebSocketService>(
            builder: (_, ws, __) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用语法自动学习'),
              subtitle: Text(
                ws.grammarAutoLearnEnabled
                    ? '当前开启，LLM 新语法会自动持久化到数据库'
                    : '当前关闭，不会从 LLM 结果写入新语法',
              ),
              value: ws.grammarAutoLearnEnabled,
              onChanged: (value) async {
                final ok = await ws.setGrammarAutoLearnEnabled(value);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? (value ? '已开启语法自动学习' : '已关闭语法自动学习')
                        : '切换失败，请检查后端连接'),
                  ),
                );
              },
            ),
          ),

          Consumer<WebSocketService>(
            builder: (_, ws, __) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自动触发深度分析'),
              subtitle: Text(
                ws.deepAutoAnalyzeEnabled
                    ? '当前开启：新文本会自动进入深度分析队列（建议与预取配合）'
                    : '当前关闭：仅缓存基础结果，需手动触发深度分析',
              ),
              value: ws.deepAutoAnalyzeEnabled,
              onChanged: (value) async {
                final ok = await ws.setDeepAutoAnalyzeEnabled(value);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? (value ? '已开启自动深度分析' : '已关闭自动深度分析')
                        : '切换失败，请检查后端连接'),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune),
            title: const Text('LLM/API 配置'),
            subtitle: const Text('点击进入独立配置界面，保存后自动记忆'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LlmConfigScreen()),
              );
            },
          ),

          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.keyboard),
            title: const Text('快捷键管理'),
            subtitle: const Text('自定义开关剪贴板、提交解析等快捷键'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ShortcutConfigScreen()),
              );
            },
          ),

          const SizedBox(height: 8),
          Consumer<WebSocketService>(
            builder: (_, ws, __) {
              final options = <int>{20, 50, 100, 200, 500, ws.historyLimit}
                  .toList()
                ..sort();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('历史记录设置',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: ws.historyLimit,
                    decoration: const InputDecoration(
                      labelText: '历史记录上限',
                      border: OutlineInputBorder(),
                    ),
                    items: options
                        .map(
                          (n) => DropdownMenuItem<int>(
                            value: n,
                            child: Text('$n 条'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) async {
                      if (value == null) return;
                      await ws.setHistoryLimit(value);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('历史记录上限已设置为 $value 条')),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('当前记录数：${ws.history.length}',
                          style: const TextStyle(color: Colors.grey)),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('清空历史记录'),
                        onPressed: () async {
                          await ws.clearHistory();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('历史记录已清空')),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 20),
          Row(
            children: [
              Text('外置资源配置', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 6),
              IconButton(
                onPressed: _showResourceHelpDialog,
                tooltip: '配置说明',
                icon: const Icon(Icons.info_outline, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _dictPathController,
            decoration: const InputDecoration(
              labelText: '词典 SQLite 路径',
              hintText: '例如 D:\\Dicts\\jmdict_zh.sqlite',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ginzaPathController,
            decoration: const InputDecoration(
              labelText: 'GiNZA 模型路径（可选）',
              hintText: '例如 D:\\Models\\ja_ginza',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _ginzaSplitMode,
            decoration: const InputDecoration(
              labelText: 'GiNZA 分词等级',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'A', child: Text('A（细粒度）')),
              DropdownMenuItem(value: 'B', child: Text('B（平衡）')),
              DropdownMenuItem(value: 'C', child: Text('C（粗粒度，阅读推荐）')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _ginzaSplitMode = _normalizeGinzaSplitMode(value));
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _dependencyFocusStyle,
            decoration: const InputDecoration(
              labelText: '依存聚焦风格',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'classic', child: Text('classic（经典）')),
              DropdownMenuItem(value: 'vivid', child: Text('vivid（炫彩）')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _dependencyFocusStyle = _normalizeDependencyFocusStyle(value);
              });
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _onnxPathController,
            decoration: const InputDecoration(
              labelText: 'ONNX 模型路径（预留）',
              hintText: '例如 D:\\Models\\ginza.onnx',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Consumer<WebSocketService>(
            builder: (_, ws, __) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Luna 预取开关已移到主界面'),
              subtitle: Text(
                ws.resourceConfig.lunaWsEnabled
                    ? '当前状态：已开启（主界面跟随模式旁边可关闭）'
                    : '当前状态：已关闭（主界面跟随模式旁边可开启）',
              ),
            ),
          ),
          TextField(
            controller: _lunaWsController,
            decoration: const InputDecoration(
              labelText: 'Luna WebSocket 原文流地址',
              hintText: '例如 ws://127.0.0.1:23333/api/ws/text/origin',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _queueMaxPendingController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '深度分析队列上限',
              hintText: '120',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _dropPrefetchWhenBusy,
            onChanged: (value) => setState(() => _dropPrefetchWhenBusy = value),
            title: const Text('拥塞时丢弃预取任务'),
            subtitle: const Text('开启后优先保障手动分析请求，防止预取堆积导致卡顿'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _savingResources ? null : _saveExternalResourceConfig,
            icon: const Icon(Icons.save),
            label: Text(_savingResources ? '保存中...' : '保存外置资源配置'),
          ),

          const SizedBox(height: 24),
          Text('关于', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('日语语法解析器 v1.0',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Galgame 实时日语语法学习工具',
                      style: TextStyle(color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('功能：', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('• JLPT N1-N5 语法等级标注'),
                  Text('• Luna 文本预取 + 队列缓存'),
                  Text('• LLM 深度语法分析（Ollama / 通用API）'),
                  Text('• LunaTranslator 实时文本获取'),
                  Text('• 外置资源路径配置（词典 / GiNZA / ONNX）'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _windowEffectLabel(String value) {
    switch (value) {
      case 'transparent':
        return 'Transparent（默认）';
      case 'mica':
        return 'Mica';
      case 'disabled':
        return 'Disabled';
      default:
        return value;
    }
  }

  String _normalizeGinzaSplitMode(String raw) {
    final mode = raw.trim().toUpperCase();
    if (mode == 'A' || mode == 'B' || mode == 'C') {
      return mode;
    }
    return 'C';
  }

  String _normalizeDependencyFocusStyle(String raw) {
    final style = raw.trim().toLowerCase();
    if (style == 'classic' || style == 'vivid') {
      return style;
    }
    return 'classic';
  }
}
