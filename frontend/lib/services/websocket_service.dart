/// WebSocket service — connects to Python backend, receives analysis results.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/analysis_result.dart';

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  bool _connected = false;
  String _serverUrl = 'ws://localhost:8765/ws';

  // Current analysis state
  AnalysisState _state = const AnalysisState();
  AnalysisState get state => _state;
  bool get connected => _connected;
  String get serverUrl => _serverUrl;

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
      _state = const AnalysisState(isLoadingDeep: true);
      notifyListeners();
    }
  }

  void _onMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String?;

      if (type == 'basic_result') {
        final basic = BasicResult.fromJson(json);
        _state = AnalysisState(basic: basic, isLoadingDeep: true);
        _history.insert(0, basic);
        if (_history.length > 100) _history.removeLast();
      } else if (type == 'deep_result') {
        final deep = DeepResult.fromJson(json);
        _state = _state.copyWith(deep: deep, isLoadingDeep: false);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to parse message: $e');
    }
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
