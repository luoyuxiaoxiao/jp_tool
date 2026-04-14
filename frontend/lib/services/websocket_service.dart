/// WebSocket service — connects to Python backend, receives analysis results.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  final String toggleGrammarAutoLearn;
  final String submitAnalyze;
  final String focusInput;

  const ShortcutConfig({
    this.toggleClipboard = 'ctrl+shift+b',
    this.toggleGrammarAutoLearn = 'ctrl+shift+g',
    this.submitAnalyze = 'ctrl+enter',
    this.focusInput = 'ctrl+l',
  });

  factory ShortcutConfig.fromJson(Map<String, dynamic> j) {
    final raw = j['shortcuts'];
    final source = raw is Map<String, dynamic> ? raw : j;
    return ShortcutConfig(
      toggleClipboard:
          (source['toggle_clipboard'] ?? 'ctrl+shift+b').toString(),
      toggleGrammarAutoLearn:
          (source['toggle_grammar_auto_learn'] ?? 'ctrl+shift+g').toString(),
      submitAnalyze: (source['submit_analyze'] ?? 'ctrl+enter').toString(),
      focusInput: (source['focus_input'] ?? 'ctrl+l').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'toggle_clipboard': toggleClipboard,
        'toggle_grammar_auto_learn': toggleGrammarAutoLearn,
        'submit_analyze': submitAnalyze,
        'focus_input': focusInput,
      };
}

class WebSocketService extends ChangeNotifier {
  static const int _defaultBackendPort = 8765;
  static const List<int> _fallbackBackendPorts = [18765, 28675, 38575, 47865];
  static const int _defaultHistoryLimit = 100;
  static const int _minHistoryLimit = 20;
  static const int _maxHistoryLimit = 500;
  static const String _historyStorageKey = 'jp_history_items_v1';
  static const String _historyLimitStorageKey = 'jp_history_limit_v1';
  static const String _backendAutoStartStorageKey = 'jp_backend_autostart_v1';
  static const String _backendExePathStorageKey = 'jp_backend_exe_path_v1';

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  int _connectionToken = 0;
  bool _shouldReconnect = true;
  bool _connected = false;
  String _serverUrl = 'ws://localhost:8765/ws';
  bool _llmEnabled = false;
  bool _clipboardEnabled = true;
  bool _grammarAutoLearnEnabled = true;
  bool _autoStartBackend = true;
  String _backendExecutablePath = '';
  int? _managedBackendPid;
  int? _managedBackendPort;
  String? _managedBackendError;
  bool _startingManagedBackend = false;
  ShortcutConfig _shortcutConfig = const ShortcutConfig();
  int _historyLimit = _defaultHistoryLimit;

  // Current analysis state
  AnalysisState _state = const AnalysisState();
  AnalysisState get state => _state;
  bool get connected => _connected;
  String get serverUrl => _serverUrl;
  bool get llmEnabled => _llmEnabled;
  bool get clipboardEnabled => _clipboardEnabled;
  bool get grammarAutoLearnEnabled => _grammarAutoLearnEnabled;
  bool get autoStartBackend => _autoStartBackend;
  String get backendExecutablePath => _backendExecutablePath;
  int? get managedBackendPid => _managedBackendPid;
  int? get managedBackendPort => _managedBackendPort;
  String? get managedBackendError => _managedBackendError;
  bool get isManagedBackendRunning => _managedBackendPid != null;
  ShortcutConfig get shortcutConfig => _shortcutConfig;
  int get historyLimit => _historyLimit;

  // History
  final List<BasicResult> _history = [];
  List<BasicResult> get history => List.unmodifiable(_history);

  WebSocketService() {
    unawaited(_loadHistoryFromPrefs());
  }

  void connect({String? url}) {
    final trimmed = url?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      _serverUrl = trimmed;
    }

    _shouldReconnect = true;
    _cancelReconnectTimer();
    unawaited(_startManagedBackendIfNeeded());
    _startConnectionCycle();
  }

  void disconnect() {
    _shouldReconnect = false;
    _cancelReconnectTimer();
    _connectionToken += 1;
    _closeChannel();
  }

  void _startConnectionCycle() {
    final token = ++_connectionToken;
    _closeChannel();
    _openChannel(token);
  }

  void _openChannel(int token) {
    try {
      final channel = WebSocketChannel.connect(Uri.parse(_serverUrl));
      _channel = channel;
      _setConnected(true);
      unawaited(refreshServerStatus());

      channel.stream.listen(
        _onMessage,
        onError: (e) => _handleChannelClosed(token, error: e),
        onDone: () => _handleChannelClosed(token),
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('WebSocket connect failed: $e');
      _handleChannelClosed(token, error: e);
    }
  }

  void _handleChannelClosed(int token, {Object? error}) {
    if (token != _connectionToken) return;

    if (error != null) {
      debugPrint('WebSocket closed with error: $error');
    }

    _channel = null;
    _setConnected(false);
    unawaited(_startManagedBackendIfNeeded());
    _scheduleReconnect(token);
  }

  void _scheduleReconnect(int token) {
    if (!_shouldReconnect || token != _connectionToken) return;
    if (_reconnectTimer?.isActive == true) return;

    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _reconnectTimer = null;
      if (!_shouldReconnect || token != _connectionToken) return;
      _startConnectionCycle();
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _closeChannel() {
    try {
      _channel?.sink.close();
    } catch (_) {
      // Ignore close errors from stale sockets.
    }
    _channel = null;
    _setConnected(false);
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    notifyListeners();
  }

  /// Send text for analysis via WebSocket.
  void sendText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _channel == null || !_connected) return;

    try {
      _channel!.sink.add(jsonEncode({'type': 'analyze', 'text': trimmed}));
      _state = AnalysisState(isLoadingDeep: _llmEnabled);
      notifyListeners();
    } catch (e) {
      debugPrint('WebSocket send failed: $e');
      _handleChannelClosed(_connectionToken, error: e);
    }
  }

  Future<void> refreshServerStatus() async {
    await Future.wait([
      refreshLlmStatus(),
      refreshClipboardStatus(),
      refreshGrammarAutoLearnStatus(),
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

  Future<void> refreshGrammarAutoLearnStatus() async {
    final data = await _requestJson('GET', '/api/grammar/auto-learn/status');
    if (data == null) return;

    _grammarAutoLearnEnabled = data['enabled'] == true;
    notifyListeners();
  }

  Future<bool> setGrammarAutoLearnEnabled(bool enabled) async {
    final data = await _requestJson(
      'POST',
      '/api/grammar/auto-learn/configure',
      body: {'enabled': enabled},
    );
    if (data == null) return false;

    _grammarAutoLearnEnabled = data['enabled'] == true;
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

  Future<bool> setHistoryLimit(int limit) async {
    _historyLimit = _sanitizeHistoryLimit(limit);
    _trimHistoryToLimit();
    notifyListeners();
    await _saveHistoryToPrefs();
    return true;
  }

  Future<void> clearHistory() async {
    _history.clear();
    notifyListeners();
    await _saveHistoryToPrefs();
  }

  Future<void> setAutoStartBackend(bool enabled) async {
    _autoStartBackend = enabled;
    notifyListeners();
    await _saveBackendPrefs();
  }

  Future<void> setBackendExecutablePath(String path) async {
    _backendExecutablePath = path.trim();
    notifyListeners();
    await _saveBackendPrefs();
  }

  Future<bool> startManagedBackendNow() async {
    return _startManagedBackendIfNeeded(force: true);
  }

  Future<bool> stopManagedBackendNow() async {
    final pid = _managedBackendPid;
    if (pid == null || kIsWeb || !Platform.isWindows) return false;

    try {
      await Process.run('taskkill', ['/PID', '$pid', '/T', '/F']);
    } catch (e) {
      debugPrint('Stop managed backend failed: $e');
    }

    _managedBackendPid = null;
    _managedBackendPort = null;
    notifyListeners();
    return true;
  }

  Future<bool> _startManagedBackendIfNeeded({bool force = false}) async {
    if (kIsWeb || !Platform.isWindows) return false;
    if (_startingManagedBackend) return false;
    if (!force && !_autoStartBackend) return false;
    if (_managedBackendPid != null) return true;

    final exePath = _resolveBackendExecutablePath();
    if (exePath == null || exePath.isEmpty) {
      _managedBackendError = '未找到可执行文件，请先配置后端 exe 路径';
      notifyListeners();
      debugPrint('Managed backend start skipped: executable not found');
      return false;
    }

    final ports = _candidateBackendPorts();
    if (ports.isEmpty) {
      _managedBackendError = '没有可用的候选端口';
      notifyListeners();
      return false;
    }

    _startingManagedBackend = true;
    _managedBackendError = null;
    notifyListeners();
    try {
      for (final port in ports) {
        final existingReady = await _checkBackendReady(port);
        if (existingReady) {
          _managedBackendError = null;
          _serverUrl = _localWsUrl(port);
          notifyListeners();
          return true;
        }

        final available = await _isPortAvailable(port);
        if (!available) {
          continue;
        }

        final pid = await _launchBackendProcess(exePath, port);
        if (pid == null) {
          continue;
        }

        final ready = await _waitBackendReady(port);
        if (!ready) {
          await _killProcess(pid);
          continue;
        }

        _managedBackendPid = pid;
        _managedBackendPort = port;
        _managedBackendError = null;
        _serverUrl = _localWsUrl(port);
        notifyListeners();
        return true;
      }

      _managedBackendError =
          '默认端口 $_defaultBackendPort 与备用端口均不可用，请释放端口后重试';
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('Managed backend start exception: $e');
      _managedBackendError = '启动异常：$e';
      notifyListeners();
      return false;
    } finally {
      _startingManagedBackend = false;
      notifyListeners();
    }
  }

  List<int> _candidateBackendPorts() {
    final ports = <int>[];
    final preferred = _preferredServerPort();

    if (preferred != null) {
      ports.add(preferred);
    }
    if (!ports.contains(_defaultBackendPort)) {
      ports.add(_defaultBackendPort);
    }
    for (final p in _fallbackBackendPorts) {
      if (!ports.contains(p)) {
        ports.add(p);
      }
    }
    return ports;
  }

  int? _preferredServerPort() {
    try {
      final uri = Uri.parse(_serverUrl);
      if (!_isLocalHost(uri.host)) {
        return null;
      }
      final p = uri.hasPort ? uri.port : _defaultBackendPort;
      if (p <= 0 || p > 65535) {
        return null;
      }
      return p;
    } catch (_) {
      return null;
    }
  }

  bool _isLocalHost(String host) {
    final value = host.toLowerCase();
    return value == 'localhost' || value == '127.0.0.1' || value == '::1';
  }

  String _localWsUrl(int port) => 'ws://127.0.0.1:$port/ws';

  Future<bool> _isPortAvailable(int port) async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      await socket?.close();
    }
  }

  Future<int?> _launchBackendProcess(String exePath, int port) async {
    try {
      final escapedPath = exePath.replaceAll("'", "''");
      final workingDir = File(exePath).parent.path.replaceAll("'", "''");
      final command =
          "\$env:JP_TOOL_PORT='$port'; \$p = Start-Process -FilePath '$escapedPath' -WorkingDirectory '$workingDir' -WindowStyle Hidden -PassThru; \$p.Id";

      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
      );

      if (result.exitCode != 0) {
        debugPrint(
            'Managed backend start failed on port $port: ${result.stderr ?? 'unknown error'}');
        return null;
      }

      final output = result.stdout.toString();
      final match = RegExp(r'(\d+)').firstMatch(output);
      if (match == null) {
        debugPrint('Managed backend start failed on port $port: pid not returned');
        return null;
      }

      return int.tryParse(match.group(1)!);
    } catch (e) {
      debugPrint('Managed backend launch exception on port $port: $e');
      return null;
    }
  }

  Future<bool> _waitBackendReady(
    int port, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _checkBackendReady(port)) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  Future<bool> _checkBackendReady(int port) async {
    final client = HttpClient();
    try {
      final uri = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        path: '/api/llm/status',
      );
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(milliseconds: 800));
      final response =
          await request.close().timeout(const Duration(milliseconds: 800));
      await response.drain<List<int>>();
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _killProcess(int pid) async {
    try {
      await Process.run('taskkill', ['/PID', '$pid', '/T', '/F']);
    } catch (_) {
      // Ignore cleanup failures.
    }
  }

  String? _resolveBackendExecutablePath() {
    final configured = _backendExecutablePath.trim();
    if (configured.isNotEmpty && File(configured).existsSync()) {
      return configured;
    }

    if (kIsWeb || !Platform.isWindows) {
      return null;
    }

    final roots = <String>{
      Directory.current.path,
      File(Platform.resolvedExecutable).parent.path,
    };

    final candidates = <String>[];
    for (final root in roots) {
      candidates.addAll([
        '$root\\jp_grammar.exe',
        '$root\\backend\\jp_grammar.exe',
        '$root\\backend\\dist\\jp_grammar\\jp_grammar.exe',
        '$root\\resources\\backend\\jp_grammar.exe',
      ]);
    }

    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }

    return null;
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
        _insertHistory(basic, notify: false);
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

  int _sanitizeHistoryLimit(int value) {
    if (value < _minHistoryLimit) return _minHistoryLimit;
    if (value > _maxHistoryLimit) return _maxHistoryLimit;
    return value;
  }

  String _normalizedHistoryText(String text) {
    return text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  void _insertHistory(BasicResult basic, {bool notify = true}) {
    final key = _normalizedHistoryText(basic.text);
    if (key.isEmpty) return;

    _history.removeWhere((item) => _normalizedHistoryText(item.text) == key);
    _history.insert(0, basic);
    _trimHistoryToLimit();

    if (notify) {
      notifyListeners();
    }
    unawaited(_saveHistoryToPrefs());
  }

  void _trimHistoryToLimit() {
    if (_history.length <= _historyLimit) return;
    _history.removeRange(_historyLimit, _history.length);
  }

  Future<void> _loadHistoryFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoStartBackend =
          prefs.getBool(_backendAutoStartStorageKey) ?? _autoStartBackend;
      _backendExecutablePath =
          (prefs.getString(_backendExePathStorageKey) ?? '').trim();

      final limit =
          prefs.getInt(_historyLimitStorageKey) ?? _defaultHistoryLimit;
      _historyLimit = _sanitizeHistoryLimit(limit);

      final items = prefs.getStringList(_historyStorageKey) ?? const [];
      _history.clear();
      for (final raw in items) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) continue;
          final item = BasicResult.fromJson(decoded);
          final text = _normalizedHistoryText(item.text);
          if (text.isEmpty) continue;
          _history.removeWhere((x) => _normalizedHistoryText(x.text) == text);
          _history.add(item);
        } catch (_) {
          // Ignore broken item.
        }
      }

      _trimHistoryToLimit();
      notifyListeners();
    } catch (e) {
      debugPrint('Load local history failed: $e');
    }
  }

  Future<void> _saveHistoryToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _history
          .take(_historyLimit)
          .map((item) => jsonEncode(item.toJson()))
          .toList();
      await prefs.setInt(_historyLimitStorageKey, _historyLimit);
      await prefs.setStringList(_historyStorageKey, list);
    } catch (e) {
      debugPrint('Save local history failed: $e');
    }
  }

  Future<void> _saveBackendPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_backendAutoStartStorageKey, _autoStartBackend);
      await prefs.setString(_backendExePathStorageKey, _backendExecutablePath);
    } catch (e) {
      debugPrint('Save backend prefs failed: $e');
    }
  }

  @override
  void dispose() {
    unawaited(stopManagedBackendNow());
    _cancelReconnectTimer();
    disconnect();
    super.dispose();
  }
}
