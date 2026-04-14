/// Settings screen — configure server URL, LLM provider, etc.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';

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

          const SizedBox(height: 24),
          Text('关于', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('日语语法解析器 v1.0', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Galgame 实时日语语法学习工具', style: TextStyle(color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('功能：', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('• MeCab 分词 + 注音'),
                  Text('• JLPT N1-N5 语法等级标注'),
                  Text('• LLM 深度语法分析（Ollama / Claude）'),
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
