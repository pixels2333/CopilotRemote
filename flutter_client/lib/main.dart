import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/chat_screen.dart';
import 'providers/chat_provider.dart';

void main() {
  runApp(
    const ProviderScope(
      child: CopilotMirrorApp(),
    ),
  );
}

class CopilotMirrorApp extends StatelessWidget {
  const CopilotMirrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Copilot Mirror',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF131315),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
          surface: const Color(0xFF1C1C1F),
        ),
        useMaterial3: true,
        fontFamily: 'sans-serif',
      ),
      home: const ChatScreen(),
    );
  }
}
