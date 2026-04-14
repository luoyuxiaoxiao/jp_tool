/// LLM/API configuration page for persisted backend settings.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';

class LlmConfigScreen extends StatefulWidget {
  const LlmConfigScreen({super.key});

  @override
  State<LlmConfigScreen> createState() => _LlmConfigScreenState();
}

class _LlmConfigScreenState extends State<LlmConfigScreen> {
  final _formKey = GlobalKey<FormState>();

  String _backend = 'auto';
  String _apiFormat = 'openai';

  late final TextEditingController _ollamaModelCtrl;
  late final TextEditingController _ollamaUrlCtrl;
  late final TextEditingController _apiBaseCtrl;
  late final TextEditingController _apiModelCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _apiTimeoutCtrl;

  bool _loading = true;
  bool _saving = false;
  bool _loadingModels = false;
  List<String> _fetchedModels = const [];
  String? _modelFetchMessage;
  bool _modelFetchError = false;

  @override
  void initState() {
    super.initState();
    _ollamaModelCtrl = TextEditingController();
    _ollamaUrlCtrl = TextEditingController();
    _apiBaseCtrl = TextEditingController();
    _apiModelCtrl = TextEditingController();
    _apiKeyCtrl = TextEditingController();
    _apiTimeoutCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _ollamaModelCtrl.dispose();
    _ollamaUrlCtrl.dispose();
    _apiBaseCtrl.dispose();
    _apiModelCtrl.dispose();
    _apiKeyCtrl.dispose();
    _apiTimeoutCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ws = context.read<WebSocketService>();
    final cfg = await ws.getLlmConfig();
    final c = cfg ?? const LlmConfig();

    if (!mounted) return;
    setState(() {
      _backend = c.backend;
      _apiFormat = c.apiFormat;
      _ollamaModelCtrl.text = c.ollamaModel;
      _ollamaUrlCtrl.text = c.ollamaUrl;
      _apiBaseCtrl.text = c.apiBaseUrl;
      _apiModelCtrl.text = c.apiModel;
      _apiKeyCtrl.text = c.apiKey;
      _apiTimeoutCtrl.text = c.apiTimeout;
      _loading = false;
    });

    if (_backend == 'api' || _backend == 'ollama') {
      unawaited(_fetchModels(silent: true));
    }
  }

  LlmConfig _draftConfig() {
    return LlmConfig(
      backend: _backend,
      ollamaModel: _ollamaModelCtrl.text.trim(),
      ollamaUrl: _ollamaUrlCtrl.text.trim(),
      apiFormat: _apiFormat,
      apiBaseUrl: _apiBaseCtrl.text.trim(),
      apiModel: _apiModelCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      apiTimeout: _apiTimeoutCtrl.text.trim(),
    );
  }

  TextEditingController get _activeModelCtrl =>
      _useApi ? _apiModelCtrl : _ollamaModelCtrl;

  Future<void> _fetchModels({bool silent = false}) async {
    if (!(_useApi || _useOllama)) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先选择 Ollama 或 通用 API 后再获取模型')),
        );
      }
      return;
    }

    setState(() {
      _loadingModels = true;
      _modelFetchMessage = null;
      _modelFetchError = false;
    });

    final ws = context.read<WebSocketService>();
    final result = await ws.fetchLlmModels(_draftConfig());

    if (!mounted) return;

    if (result == null) {
      setState(() {
        _loadingModels = false;
        _fetchedModels = const [];
        _modelFetchMessage = '获取失败：后端无响应';
        _modelFetchError = true;
      });
      return;
    }

    final msg = StringBuffer();
    if (result.ok) {
      msg.write('获取成功，共 ${result.models.length} 个模型');
      if (result.models.isEmpty) {
        msg.write('（返回为空）');
      }
    } else {
      msg.write(result.error ?? '获取模型失败');
      if (result.statusCode != null) {
        msg.write(' (HTTP ${result.statusCode})');
      }
      if ((result.hint ?? '').isNotEmpty) {
        msg.write('；${result.hint}');
      }
    }

    setState(() {
      _loadingModels = false;
      _fetchedModels = result.models;
      _modelFetchMessage = msg.toString();
      _modelFetchError = !result.ok;
      if (result.models.isNotEmpty &&
          !_fetchedModels.contains(_activeModelCtrl.text.trim())) {
        _activeModelCtrl.text = result.models.first;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final ws = context.read<WebSocketService>();

    final ok = await ws.saveLlmConfig(
      LlmConfig(
        backend: _backend,
        ollamaModel: _ollamaModelCtrl.text.trim(),
        ollamaUrl: _ollamaUrlCtrl.text.trim(),
        apiFormat: _apiFormat,
        apiBaseUrl: _apiBaseCtrl.text.trim(),
        apiModel: _apiModelCtrl.text.trim(),
        apiKey: _apiKeyCtrl.text.trim(),
        apiTimeout: _apiTimeoutCtrl.text.trim(),
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '配置保存成功，后续会自动记住' : '配置保存失败，请检查后端连接'),
      ),
    );
  }

  bool get _useOllama => _backend == 'ollama';
  bool get _useApi => _backend == 'api';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LLM/API 配置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    '一次配置，持久保存到本地数据库（SQLite），重启后自动生效。',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _backend,
                    decoration: const InputDecoration(
                      labelText: '后端类型',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'auto', child: Text('自动检测（优先 Ollama）')),
                      DropdownMenuItem(value: 'off', child: Text('关闭深度分析')),
                      DropdownMenuItem(
                          value: 'ollama', child: Text('Ollama 本地模型')),
                      DropdownMenuItem(value: 'api', child: Text('通用 API')),
                    ],
                    onChanged: (v) {
                      final next = v ?? 'auto';
                      setState(() {
                        _backend = next;
                        _fetchedModels = const [];
                        _modelFetchMessage = null;
                        _modelFetchError = false;
                      });
                      if (next == 'api' || next == 'ollama') {
                        unawaited(_fetchModels(silent: true));
                      }
                    },
                  ),
                  if (_useApi || _useOllama) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed:
                              _loadingModels ? null : () => _fetchModels(),
                          icon: _loadingModels
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.download),
                          label: Text(_loadingModels ? '获取中...' : '获取模型列表'),
                        ),
                        const SizedBox(width: 10),
                        if (_fetchedModels.isNotEmpty)
                          Text('已加载 ${_fetchedModels.length} 个模型',
                              style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                    if (_fetchedModels.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _fetchedModels
                                .contains(_activeModelCtrl.text.trim())
                            ? _activeModelCtrl.text.trim()
                            : null,
                        decoration: const InputDecoration(
                          labelText: '可选模型（可直接选择）',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                        items: _fetchedModels
                            .map((m) =>
                                DropdownMenuItem(value: m, child: Text(m)))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _activeModelCtrl.text = v;
                          });
                        },
                      ),
                    ],
                    if ((_modelFetchMessage ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _modelFetchMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _modelFetchError
                              ? Colors.redAccent
                              : Colors.greenAccent,
                        ),
                      ),
                    ],
                  ],
                  if (_useOllama) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _ollamaModelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ollama 模型名',
                        hintText: 'qwen2.5:7b',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (_useOllama && (v == null || v.trim().isEmpty)) {
                          return '请输入模型名';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _ollamaUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ollama 地址',
                        hintText: 'http://localhost:11434',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (_useOllama && (v == null || v.trim().isEmpty)) {
                          return '请输入Ollama地址';
                        }
                        return null;
                      },
                    ),
                  ],
                  if (_useApi) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _apiFormat,
                      decoration: const InputDecoration(
                        labelText: 'API 格式',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'openai', child: Text('OpenAI 兼容')),
                        DropdownMenuItem(
                            value: 'anthropic', child: Text('Anthropic')),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _apiFormat = v ?? 'openai';
                          _fetchedModels = const [];
                          _modelFetchMessage = null;
                          _modelFetchError = false;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _apiBaseCtrl,
                      decoration: const InputDecoration(
                        labelText: 'API Base URL',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (_useApi && (v == null || v.trim().isEmpty)) {
                          return '请输入API地址';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _apiModelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'API 模型名',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (_useApi && (v == null || v.trim().isEmpty)) {
                          return '请输入模型名';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _apiKeyCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (_useApi && (v == null || v.trim().isEmpty)) {
                          return '请输入API Key';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _apiTimeoutCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '超时（秒）',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (!_useApi) return null;
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null || n < 5 || n > 300) {
                          return '请输入 5-300 的整数';
                        }
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? '保存中...' : '保存配置'),
                  ),
                ],
              ),
            ),
    );
  }
}
