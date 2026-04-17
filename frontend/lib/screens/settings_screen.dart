/// Settings screen.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import 'resource_settings_screens.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _backendPortController;
  final ScrollController _backendLogScrollController = ScrollController();
  bool _reconnecting = false;

  @override
  void initState() {
    super.initState();
    final ws = context.read<WebSocketService>();
    _backendPortController = TextEditingController(
      text: _extractLocalPort(ws.serverUrl).toString(),
    );
    unawaited(ws.refreshServerStatus());
  }

  @override
  void dispose() {
    _backendPortController.dispose();
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
    return 8865;
  }

  Future<void> _reconnect(WebSocketService ws) async {
    final port = int.tryParse(_backendPortController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('端口号无效，请输入 1-65535')),
      );
      return;
    }

    final targetUrl = 'ws://127.0.0.1:$port/ws';
    setState(() => _reconnecting = true);
    final ok = await ws.reconnect(url: targetUrl);
    if (!mounted) return;

    setState(() => _reconnecting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '重连成功：$targetUrl' : '重连失败，请检查后端是否可用')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(
      builder: (_, ws, __) => Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('服务器连接', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: ws.connected ? Colors.greenAccent : Colors.redAccent,
                ),
                const SizedBox(width: 6),
                Text(ws.connected ? '已连接' : '未连接'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '当前地址：${ws.serverUrl}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _backendPortController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '本地后端端口',
                      hintText: '8865',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _reconnecting ? null : () => _reconnect(ws),
                  child: _reconnecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('重新连接'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              kDebugMode
                  ? '当前是 Debug 模式：不会自动拉起后端，请先手动启动 backend/main.py。'
                  : '当前是 Release 模式：前端会自动拉起本地后端。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (ws.managedBackendError != null &&
                ws.managedBackendError!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '后端状态：${ws.managedBackendError}',
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
            const SizedBox(height: 16),
            Text('主题', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: ws.windowEffect,
              decoration: const InputDecoration(
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
                      content: Text('主题已切换为：${_windowEffectLabel(value)}')),
                );
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('显示后端日志'),
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
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
            const SizedBox(height: 16),
            SwitchListTile(
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自动触发深度分析'),
              subtitle: Text(
                ws.deepAutoAnalyzeEnabled
                    ? '当前开启（默认）：新文本会自动进入深度分析队列'
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
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_copy_outlined),
              title: const Text('资源与Luna配置'),
              subtitle: const Text('外置资源配置、Luna相关配置（三级目录）'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ResourceConfigHubScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (_) {
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
                            final backendCleared = await ws.clearHistory();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  backendCleared
                                      ? '历史记录与后端缓存已清空'
                                      : '历史记录已清空（后端缓存未清空，请重启后端后重试）',
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _windowEffectLabel(String value) {
    switch (value) {
      case 'transparent':
        return 'Transparent（默认）';
      case 'mica':
        return 'Mica';
      default:
        return value;
    }
  }
}
