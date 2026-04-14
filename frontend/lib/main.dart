import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/websocket_service.dart';
import 'screens/analysis_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => WebSocketService()..connect(),
      child: const JpGrammarApp(),
    ),
  );
}

class JpGrammarApp extends StatelessWidget {
  const JpGrammarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JP Grammar Analyzer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Noto Sans JP',
      ),
      home: const AnalysisScreen(),
    );
  }
}
