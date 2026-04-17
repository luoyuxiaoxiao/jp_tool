library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';

class ResourceConfigHubScreen extends StatelessWidget {
  const ResourceConfigHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('资源配置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: const Text('外置资源配置'),
            subtitle: const Text('词典路径、GiNZA 模型、分词等级、依存风格、ONNX 路径'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ExternalResourceConfigScreen()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sync_alt),
            title: const Text('Luna相关配置'),
            subtitle: const Text('原文流地址、队列上限、拥塞策略'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const LunaRelatedConfigScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class ExternalResourceConfigScreen extends StatefulWidget {
  const ExternalResourceConfigScreen({super.key});

  @override
  State<ExternalResourceConfigScreen> createState() =>
      _ExternalResourceConfigScreenState();
}

class _ExternalResourceConfigScreenState
    extends State<ExternalResourceConfigScreen> {
  static const String _ginzaInstallPackageName = 'ja_ginza_electra';

  late final TextEditingController _dictPathController;
  late final TextEditingController _ginzaPathController;
  late final TextEditingController _onnxPathController;
  String _ginzaSplitMode = 'C';
  String _dependencyFocusStyle = 'classic';
  bool _ginzaEnabled = false;
  String _ginzaStatusText = 'GiNZA 未启动';
  bool _ginzaPackageInstalled = false;
  String _ginzaPackageStatusText = 'GiNZA 包未安装';
  bool _installingGinza = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dictPathController = TextEditingController();
    _ginzaPathController = TextEditingController();
    _onnxPathController = TextEditingController();
    unawaited(_load());
  }

  @override
  void dispose() {
    _dictPathController.dispose();
    _ginzaPathController.dispose();
    _onnxPathController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ws = context.read<WebSocketService>();
    final results = await Future.wait([
      ws.getResourceConfig(),
      ws.getGinzaStatus(),
      ws.getGinzaPackageStatus(packageName: _ginzaInstallPackageName),
    ]);
    final cfg = results[0] as ExternalResourceConfig?;
    final status = results[1] as GinzaRuntimeStatus?;
    final packageStatus = results[2] as GinzaPackageStatus?;
    if (!mounted || cfg == null) return;

    setState(() {
      _dictPathController.text = cfg.dictionaryDbPath;
      _ginzaPathController.text = cfg.ginzaModelPath.trim();
      _onnxPathController.text = cfg.onnxModelPath;
      _ginzaSplitMode = _normalizeGinzaSplitMode(cfg.ginzaSplitMode);
      _dependencyFocusStyle =
          _normalizeDependencyFocusStyle(cfg.dependencyFocusStyle);
      _ginzaEnabled = status?.enabled ?? false;
      _ginzaStatusText = status == null
          ? 'GiNZA 状态未知'
          : status.enabled
              ? 'GiNZA 已启动：${status.model.isNotEmpty ? status.model : '已加载'}，分词等级 ${status.splitMode}'
              : 'GiNZA 未启动：${status.error.isNotEmpty ? status.error : '请填写模型路径后保存'}';
      _ginzaPackageInstalled = packageStatus?.installed ?? false;
      _ginzaPackageStatusText = packageStatus == null
          ? 'GiNZA 包状态未知'
          : packageStatus.installed
              ? 'GiNZA 包已安装${packageStatus.version.isNotEmpty ? '：v${packageStatus.version}' : ''}，无需重复下载'
              : 'GiNZA 包未安装，点击右侧下载并自动填入';
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final ws = context.read<WebSocketService>();
    final messenger = ScaffoldMessenger.of(context);
    final current = ws.resourceConfig;
    final ok = await ws.saveResourceConfig(
      ExternalResourceConfig(
        dictionaryDbPath: _dictPathController.text.trim(),
        ginzaModelPath: _ginzaPathController.text.trim(),
        ginzaSplitMode: _ginzaSplitMode,
        dependencyFocusStyle: _dependencyFocusStyle,
        onnxModelPath: _onnxPathController.text.trim(),
        lunaWsEnabled: current.lunaWsEnabled,
        lunaWsOriginUrl: current.lunaWsOriginUrl,
        queueMaxPending: current.queueMaxPending,
        queueDropPrefetchWhenBusy: current.queueDropPrefetchWhenBusy,
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    await _load();
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? '外置资源配置已保存' : '保存失败，请检查后端连接')),
    );
  }

  Future<bool> _saveOnlyGinzaModelPath(String modelPath) async {
    final ws = context.read<WebSocketService>();
    final current = ws.resourceConfig;
    return ws.saveResourceConfig(
      ExternalResourceConfig(
        dictionaryDbPath: current.dictionaryDbPath,
        ginzaModelPath: modelPath.trim(),
        ginzaSplitMode: current.ginzaSplitMode,
        dependencyFocusStyle: current.dependencyFocusStyle,
        onnxModelPath: current.onnxModelPath,
        lunaWsEnabled: current.lunaWsEnabled,
        lunaWsOriginUrl: current.lunaWsOriginUrl,
        queueMaxPending: current.queueMaxPending,
        queueDropPrefetchWhenBusy: current.queueDropPrefetchWhenBusy,
      ),
    );
  }

  Future<void> _installGinza() async {
    if (_installingGinza) return;

    final ws = context.read<WebSocketService>();
    final messenger = ScaffoldMessenger.of(context);
    final packageStatus = await ws.getGinzaPackageStatus(
      packageName: _ginzaInstallPackageName,
    );

    if (!mounted) return;

    if (packageStatus != null && packageStatus.installed) {
      setState(() {
        _ginzaPackageInstalled = true;
        _ginzaPackageStatusText =
            'GiNZA 包已安装${packageStatus.version.isNotEmpty ? '：v${packageStatus.version}' : ''}，无需重复下载';
        _ginzaPathController.text = packageStatus.packageName;
      });
      await _saveOnlyGinzaModelPath(packageStatus.packageName);
      await _load();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${packageStatus.packageName} 已安装，无需重复下载，已自动回填配置',
          ),
        ),
      );
      return;
    }

    setState(() => _installingGinza = true);
    final result = await ws.installGinzaPackage(
      packageName: _ginzaInstallPackageName,
    );

    if (!mounted) return;
    setState(() => _installingGinza = false);

    if (result != null && result.ok) {
      _ginzaPathController.text = result.packageName;
      _ginzaPackageInstalled = true;
      _ginzaPackageStatusText = 'GiNZA 包已安装，已自动回填 ${result.packageName}';
      await _load();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              result.message.isNotEmpty ? result.message : 'GiNZA 已安装并已自动填入配置'),
        ),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result?.error.isNotEmpty == true
              ? result!.error
              : 'GiNZA 安装失败，请检查网络或 Python 环境',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('外置资源配置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '支持相对路径，基于程序根目录，例如 cache/dicts/... 或 cache/models/...。',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
              color: Colors.white10,
            ),
            child: Text(
              _ginzaStatusText,
              style: TextStyle(
                color: _ginzaEnabled ? Colors.greenAccent : Colors.orangeAccent,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _ginzaPackageStatusText,
            style: TextStyle(
              color: _ginzaPackageInstalled
                  ? Colors.greenAccent
                  : Colors.orangeAccent,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _dictPathController,
            decoration: const InputDecoration(
              labelText: '词典 SQLite 路径',
              hintText: '例如 cache/dicts/jmdict_zh.sqlite',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _ginzaPathController,
                  decoration: const InputDecoration(
                    labelText: 'GiNZA 模型路径/包名（可选）',
                    hintText:
                        '例如 cache/models/ja_ginza_electra 或 ja_ginza_electra',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _installingGinza ? null : _installGinza,
                icon: _installingGinza
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download, size: 18),
                label: Text(_installingGinza ? '下载中' : '下载'),
              ),
            ],
          ),
          if (_installingGinza) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 3),
          ],
          const SizedBox(height: 10),
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
            onChanged: _ginzaEnabled
                ? (value) {
                    if (value == null) return;
                    setState(() =>
                        _ginzaSplitMode = _normalizeGinzaSplitMode(value));
                  }
                : null,
          ),
          const SizedBox(height: 10),
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
            onChanged: _ginzaEnabled
                ? (value) {
                    if (value == null) return;
                    setState(() {
                      _dependencyFocusStyle =
                          _normalizeDependencyFocusStyle(value);
                    });
                  }
                : null,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _onnxPathController,
            decoration: const InputDecoration(
              labelText: 'ONNX 模型路径（预留）',
              hintText: '例如 cache/models/ginza.onnx',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save),
            label: Text(_saving ? '保存中...' : '保存外置资源配置'),
          ),
        ],
      ),
    );
  }
}

class LunaRelatedConfigScreen extends StatefulWidget {
  const LunaRelatedConfigScreen({super.key});

  @override
  State<LunaRelatedConfigScreen> createState() =>
      _LunaRelatedConfigScreenState();
}

class _LunaRelatedConfigScreenState extends State<LunaRelatedConfigScreen> {
  late final TextEditingController _lunaWsController;
  late final TextEditingController _queueMaxPendingController;
  bool _dropPrefetchWhenBusy = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _lunaWsController = TextEditingController();
    _queueMaxPendingController = TextEditingController(text: '120');
    unawaited(_load());
  }

  @override
  void dispose() {
    _lunaWsController.dispose();
    _queueMaxPendingController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ws = context.read<WebSocketService>();
    final cfg = await ws.getResourceConfig();
    if (!mounted || cfg == null) return;

    setState(() {
      _lunaWsController.text = cfg.lunaWsOriginUrl;
      _queueMaxPendingController.text = cfg.queueMaxPending.toString();
      _dropPrefetchWhenBusy = cfg.queueDropPrefetchWhenBusy;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final ws = context.read<WebSocketService>();
    final current = ws.resourceConfig;
    final queueMax =
        int.tryParse(_queueMaxPendingController.text.trim()) ?? 120;

    final ok = await ws.saveResourceConfig(
      ExternalResourceConfig(
        dictionaryDbPath: current.dictionaryDbPath,
        ginzaModelPath: current.ginzaModelPath,
        ginzaSplitMode: current.ginzaSplitMode,
        dependencyFocusStyle: current.dependencyFocusStyle,
        onnxModelPath: current.onnxModelPath,
        lunaWsEnabled: current.lunaWsEnabled,
        lunaWsOriginUrl: _lunaWsController.text.trim(),
        queueMaxPending: queueMax.clamp(10, 5000),
        queueDropPrefetchWhenBusy: _dropPrefetchWhenBusy,
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Luna相关配置已保存' : '保存失败，请检查后端连接')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketService>(
      builder: (_, ws, __) => Scaffold(
        appBar: AppBar(title: const Text('Luna相关配置')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
                color: Colors.white10,
              ),
              child: Text(
                ws.autoFollowLunaEnabled
                    ? '自动跟随Luna当前为开启状态，开关位于主界面顶部。'
                    : '自动跟随Luna当前为关闭状态，开关位于主界面顶部。',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lunaWsController,
              decoration: const InputDecoration(
                labelText: 'Luna WebSocket 原文流地址',
                hintText: '例如 ws://127.0.0.1:23333/api/ws/text/origin',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
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
              onChanged: (value) =>
                  setState(() => _dropPrefetchWhenBusy = value),
              title: const Text('拥塞时丢弃预取任务'),
              subtitle: const Text('开启后优先保障手动分析请求，防止预取堆积导致卡顿'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(_saving ? '保存中...' : '保存Luna相关配置'),
            ),
          ],
        ),
      ),
    );
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
