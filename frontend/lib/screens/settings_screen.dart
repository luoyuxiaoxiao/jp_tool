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

  @override
  void initState() {
    super.initState();
    final ws = context.read<WebSocketService>();
    _urlController = TextEditingController(text: ws.serverUrl);
    unawaited(ws.refreshServerStatus());
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
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
                      thumbVisibility: true,
                      child: ListView.builder(
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
                  Text('• MeCab 分词 + 注音'),
                  Text('• JLPT N1-N5 语法等级标注'),
                  Text('• LLM 深度语法分析（Ollama / 通用API）'),
                  Text('• LunaTranslator 实时文本获取'),
                  Text('• 语法数据库自动学习'),
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
}
