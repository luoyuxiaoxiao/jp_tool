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
}
