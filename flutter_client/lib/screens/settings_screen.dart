import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../providers/chat_provider.dart';
import '../models/types.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final chatState = ref.watch(chatProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Bridge connection section
          Text('Bridge 连接',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: settings.bridgeUrl,
            decoration: const InputDecoration(
              labelText: 'Bridge WebSocket 地址',
              hintText: 'ws://127.0.0.1:17321/copilot-mirror/ws',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setBridgeUrl(v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: switch (chatState.connectionStatus) {
                    ConnectionStatus.connected => Colors.green,
                    ConnectionStatus.connecting || ConnectionStatus.reconnecting => Colors.orange,
                    ConnectionStatus.disconnected => Colors.grey,
                    ConnectionStatus.failed => Colors.red,
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(
                switch (chatState.connectionStatus) {
                  ConnectionStatus.connected => '已连接',
                  ConnectionStatus.connecting => '连接中...',
                  ConnectionStatus.reconnecting => '重连中...',
                  ConnectionStatus.disconnected => '已断开',
                  ConnectionStatus.failed => '失败',
                },
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () {
                  final url = settings.bridgeUrl.isNotEmpty ? settings.bridgeUrl : settings.bridgeUrl;
                  ref.read(chatProvider.notifier).connect(url);
                },
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('连接'),
              ),
              const SizedBox(width: 8),
              if (chatState.connectionStatus == ConnectionStatus.connected)
                FilledButton.tonalIcon(
                  onPressed: () => ref.read(chatProvider.notifier).disconnect(),
                  icon: const Icon(Icons.link_off_rounded, size: 18),
                  label: const Text('断开'),
                  style: FilledButton.styleFrom(backgroundColor: colorScheme.errorContainer),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('外观', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('深色模式'),
            subtitle: Text(
              settings.themeMode == ThemeMode.light ? '浅色主题' : '深色主题',
            ),
            value: settings.themeMode == ThemeMode.dark,
            onChanged: (dark) {
              ref.read(settingsProvider.notifier).setThemeMode(
                dark ? ThemeMode.dark : ThemeMode.light,
              );
            },
            secondary: Icon(
              settings.themeMode == ThemeMode.dark
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
            ),
          ),
          const SizedBox(height: 24),
          Text('关于', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('Copilot Mirror v0.1.0'),
          const Text('VS Code Copilot Chat 移动端伴侣。'),
        ],
      ),
    );
  }
}
