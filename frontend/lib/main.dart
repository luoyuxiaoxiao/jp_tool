import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/websocket_service.dart';
import 'screens/analysis_screen.dart';
import 'theme/font_styles.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => WebSocketService()..connect(),
      child: const JpGrammarApp(),
    ),
  );
}

class JpGrammarApp extends StatefulWidget {
  const JpGrammarApp({super.key});

  @override
  State<JpGrammarApp> createState() => _JpGrammarAppState();
}

class _JpGrammarAppState extends State<JpGrammarApp> {
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  WebSocketService? _service;
  String? _lastBackendError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<WebSocketService>();
    if (_service == service) {
      return;
    }

    _service?.removeListener(_onServiceChanged);
    _service = service;
    _lastBackendError = service.managedBackendError;
    _service?.addListener(_onServiceChanged);
  }

  void _onServiceChanged() {
    final service = _service;
    if (!mounted || service == null) {
      return;
    }

    final error = service.managedBackendError;
    if (error != null && error.isNotEmpty && error != _lastBackendError) {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    }

    _lastBackendError = error;
  }

  @override
  void dispose() {
    _service?.removeListener(_onServiceChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      colorSchemeSeed: const Color(0xFF3A6EA5),
      brightness: Brightness.dark,
      useMaterial3: true,
    );

    return MaterialApp(
      scaffoldMessengerKey: _messengerKey,
      title: 'JP Grammar Analyzer',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        scaffoldBackgroundColor: const Color(0xCC11151D),
        canvasColor: const Color(0xCC11151D),
        cardColor: const Color(0xAA1D2430),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xAA161D27),
          elevation: 0,
        ),
        textTheme: buildCjkTextTheme(baseTheme.textTheme),
      ),
      home: const AnalysisScreen(),
    );
  }
}
