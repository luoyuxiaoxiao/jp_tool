/// WebSocket service — connects to Python backend, receives analysis results.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/analysis_result.dart';

class LlmConfig {
  final String backend;
  final String ollamaModel;
  final String ollamaUrl;
  final String apiFormat;
  final String apiBaseUrl;
  final String apiModel;
  final String apiKey;
  final String apiTimeout;

  const LlmConfig({
    this.backend = 'auto',
    this.ollamaModel = 'qwen2.5:7b',
    this.ollamaUrl = 'http://localhost:11434',
    this.apiFormat = 'openai',
    this.apiBaseUrl = 'https://api.openai.com',
    this.apiModel = 'gpt-4o-mini',
    this.apiKey = '',
    this.apiTimeout = '30',
  });

  factory LlmConfig.fromJson(Map<String, dynamic> j) => LlmConfig(
        backend: (j['backend'] ?? 'auto').toString(),
        ollamaModel: (j['ollama_model'] ?? 'qwen2.5:7b').toString(),
        ollamaUrl: (j['ollama_url'] ?? 'http://localhost:11434').toString(),
        apiFormat: (j['api_format'] ?? 'openai').toString(),
        apiBaseUrl: (j['api_base_url'] ?? 'https://api.openai.com').toString(),
        apiModel: (j['api_model'] ?? 'gpt-4o-mini').toString(),
        apiKey: (j['api_key'] ?? '').toString(),
        apiTimeout: (j['api_timeout'] ?? '30').toString(),
      );

  Map<String, dynamic> toJson() => {
        'backend': backend,
        'ollama_model': ollamaModel,
        'ollama_url': ollamaUrl,
        'api_format': apiFormat,
        'api_base_url': apiBaseUrl,
        'api_model': apiModel,
        'api_key': apiKey,
        'api_timeout': apiTimeout,
      };
}

class LlmModelFetchResult {
  final bool ok;
  final String backend;
  final List<String> models;
  final String? error;
  final String? hint;
  final int? statusCode;

  const LlmModelFetchResult({
    required this.ok,
    required this.backend,
    required this.models,
    this.error,
    this.hint,
    this.statusCode,
  });

  factory LlmModelFetchResult.fromJson(Map<String, dynamic> j) {
    final modelsRaw = j['models'];
    final models = <String>[];
    if (modelsRaw is List) {
      for (final item in modelsRaw) {
        models.add(item.toString());
      }
    }

    return LlmModelFetchResult(
      ok: (j['status'] == 'ok') || (j['ok'] == true),
      backend: (j['backend'] ?? '').toString(),
      models: models,
      error: j['error']?.toString(),
      hint: j['hint']?.toString(),
      statusCode: j['status_code'] is int ? j['status_code'] as int : null,
    );
  }
}

class ShortcutConfig {
  final String toggleClipboard;
  final String submitAnalyze;
  final String focusInput;

  const ShortcutConfig({
    this.toggleClipboard = 'ctrl+shift+b',
    this.submitAnalyze = 'ctrl+enter',
    this.focusInput = 'ctrl+l',
  });

  factory ShortcutConfig.fromJson(Map<String, dynamic> j) {
    final raw = j['shortcuts'];
    final source = raw is Map<String, dynamic> ? raw : j;
    return ShortcutConfig(
      toggleClipboard:
          (source['toggle_clipboard'] ?? 'ctrl+shift+b').toString(),
      submitAnalyze: (source['submit_analyze'] ?? 'ctrl+enter').toString(),
      focusInput: (source['focus_input'] ?? 'ctrl+l').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'toggle_clipboard': toggleClipboard,
        'submit_analyze': submitAnalyze,
        'focus_input': focusInput,
      };
}

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  bool _connected = false;
  String _serverUrl = 'ws://localhost:8765/ws';
  bool _llmEnabled = false;
  bool _clipboardEnabled = true;
  ShortcutConfig _shortcutConfig = const ShortcutConfig();

  // Current analysis state
  AnalysisState _state = const AnalysisState();
  AnalysisState get state => _state;
  bool get connected => _connected;
  String get serverUrl => _serverUrl;
  bool get llmEnabled => _llmEnabled;
  bool get clipboardEnabled => _clipboardEnabled;
  ShortcutConfig get shortcutConfig => _shortcutConfig;

  // History
  final List<BasicResult> _history = [];
  List<BasicResult> get history => List.unmodifiable(_history);

  void connect({String? url}) {
    if (url != null) _serverUrl = url;
    disconnect();

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));
      _connected = true;
      notifyListeners();
      unawaited(refreshServerStatus());

      _channel!.stream.listen(
        _onMessage,
        onError: (e) {
          debugPrint('WebSocket error: $e');
          _connected = false;
          notifyListeners();
          // Auto-reconnect after 3s
          Future.delayed(const Duration(seconds: 3), () => connect());
        },
        onDone: () {
          _connected = false;
          notifyListeners();
          // Auto-reconnect after 3s
          Future.delayed(const Duration(seconds: 3), () => connect());
        },
      );
    } catch (e) {
      debugPrint('WebSocket connect failed: $e');
      _connected = false;
      notifyListeners();
      Future.delayed(const Duration(seconds: 3), () => connect());
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _connected = false;
  }

  /// Send text for analysis via WebSocket.
  void sendText(String text) {
    if (_channel != null && text.trim().isNotEmpty) {
      _channel!.sink.add(jsonEncode({'type': 'analyze', 'text': text.trim()}));
      _state = AnalysisState(isLoadingDeep: _llmEnabled);
      notifyListeners();
    }
  }

  Future<void> refreshServerStatus() async {
    await Future.wait([
      refreshLlmStatus(),
      refreshClipboardStatus(),
      refreshShortcutConfig(),
    ]);
  }

  Future<void> refreshLlmStatus() async {
    final data = await _requestJson('GET', '/api/llm/status');
    if (data == null) return;

    _llmEnabled = data['enabled'] == true;
    notifyListeners();
  }

  Future<void> refreshClipboardStatus() async {
    final data = await _requestJson('GET', '/api/clipboard/status');
    if (data == null) return;

    _clipboardEnabled = data['enabled'] == true;
    notifyListeners();
  }

  Future<bool> setClipboardEnabled(bool enabled) async {
    final data = await _requestJson('POST', '/api/clipboard/configure',
        body: {'enabled': enabled});
    if (data == null) return false;

    _clipboardEnabled = data['enabled'] == true;
    notifyListeners();
    return true;
  }

  Future<LlmConfig?> getLlmConfig() async {
    final data = await _requestJson('GET', '/api/llm/config');
    if (data == null) return null;
    return LlmConfig.fromJson(data);
  }

  Future<LlmModelFetchResult?> fetchLlmModels(LlmConfig config) async {
    final data = await _requestJson(
      'POST',
      '/api/llm/models',
      body: config.toJson(),
    );
    if (data == null) return null;
    return LlmModelFetchResult.fromJson(data);
  }

  Future<bool> saveLlmConfig(LlmConfig config) async {
    final data = await _requestJson(
      'POST',
      '/api/llm/configure',
      body: config.toJson(),
    );
    if (data == null) return false;

    await refreshServerStatus();
    return data['status'] == 'ok';
  }

  Future<void> refreshShortcutConfig() async {
    final data = await _requestJson('GET', '/api/shortcuts/config');
    if (data == null) return;

    _shortcutConfig = ShortcutConfig.fromJson(data);
    notifyListeners();
  }

  Future<ShortcutConfig?> getShortcutConfig() async {
    final data = await _requestJson('GET', '/api/shortcuts/config');
    if (data == null) return null;

    final cfg = ShortcutConfig.fromJson(data);
    _shortcutConfig = cfg;
    notifyListeners();
    return cfg;
  }

  Future<bool> saveShortcutConfig(ShortcutConfig config) async {
    final data = await _requestJson(
      'POST',
      '/api/shortcuts/configure',
      body: {'shortcuts': config.toJson()},
    );
    if (data == null) return false;

    _shortcutConfig = ShortcutConfig.fromJson(data);
    notifyListeners();
    return data['status'] == 'ok';
  }

  Uri _apiUri(String path) {
    final wsUri = Uri.parse(_serverUrl);
    final scheme = wsUri.scheme == 'wss' ? 'https' : 'http';
    final defaultPort = scheme == 'https' ? 443 : 80;
    final port = wsUri.hasPort ? wsUri.port : defaultPort;

    return Uri(
      scheme: scheme,
      host: wsUri.host,
      port: port,
      path: path,
    );
  }

  Future<Map<String, dynamic>?> _requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, _apiUri(path));
      if (body != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return null;
    } catch (e) {
      debugPrint('HTTP request failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  void _onMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String?;

      if (type == 'basic_result') {
        final basic = BasicResult.fromJson(json);
        _state = AnalysisState(basic: basic, isLoadingDeep: _llmEnabled);
        _history.insert(0, basic);
        if (_history.length > 100) _history.removeLast();
      } else if (type == 'deep_result') {
        final deep = DeepResult.fromJson(json);
        _state = _state.copyWith(
          deep: _isEmptyDeepResult(deep) ? null : deep,
          isLoadingDeep: false,
        );
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to parse message: $e');
    }
  }

  bool _isEmptyDeepResult(DeepResult deep) {
    return deep.coreGrammar.isEmpty &&
        deep.sentenceBreakdown.isEmpty &&
        deep.grammarTree.isEmpty &&
        deep.comparisons.isEmpty &&
        deep.commonMistakes.isEmpty &&
        deep.culturalContext.trim().isEmpty &&
        deep.applications.isEmpty &&
        deep.levelAnnotations.isEmpty;
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
