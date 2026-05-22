import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/main_shell.dart';
import 'providers/settings_provider.dart';

void main() {
  runApp(
    const ProviderScope(
      child: CopilotMirrorApp(),
    ),
  );
}

class CopilotMirrorApp extends ConsumerWidget {
  const CopilotMirrorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'Copilot Mirror',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0632E5),
          brightness: Brightness.light,
          surface: const Color(0xFFFFFFFF),
        ),
        useMaterial3: true,
        fontFamily: 'sans-serif',
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF131315),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0632E5),
          brightness: Brightness.dark,
          surface: const Color(0xFF1C1C1F),
        ),
        useMaterial3: true,
        fontFamily: 'sans-serif',
      ),
      themeMode: settings.themeMode,
      home: const MainShell(),
    );
  }
}
