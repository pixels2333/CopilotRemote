import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../models/types.dart';
import '../widgets/connection_status_bar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_composer.dart';
import '../widgets/session_drawer.dart';
import '../widgets/agent_chip.dart';
import 'settings_screen.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
              ),
              child: const Center(
                child: Text('✦',
                    style: TextStyle(fontSize: 14, color: Colors.white)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Copilot Mirror',
                      style: TextStyle(fontSize: 16)),
                  if (chatState.activeSessionId != null)
                    Text(
                      chatState.activeSessionId!
                          .split('_')
                          .getRange(1, 2)
                          .join(' ')
                          .replaceAll('_', ' '),
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withOpacity(0.5),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            _ConnectionDot(
              status: chatState.connectionStatus,
              colorScheme: colorScheme,
            ),
          ],
        ),
        actions: [
          if (chatState.connectionStatus == ConnectionStatus.connected)
            const AgentChip(),
          if (chatState.connectionStatus == ConnectionStatus.connected)
            const SizedBox(width: 4),
          // Settings button
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: '设置',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          // Refresh button (always visible to trigger re-sync)
          IconButton(
            icon: chatState.isLoadingSessions
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: '刷新/重新同步',
            onPressed: () => _refresh(ref),
          ),
          if (chatState.connectionStatus == ConnectionStatus.connected)
            chatState.isLoadingSessions
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.swap_horiz_rounded),
                    tooltip: '切换会话',
                    onPressed: () => _showSessionDrawer(context, ref),
                  ),
        ],
      ),
      body: Column(
        children: [
          const ConnectionStatusBar(),
          Expanded(
            child: _buildBody(context, ref, chatState, colorScheme),
          ),
          const ChatComposer(),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    ChatState chatState,
    ColorScheme colorScheme,
  ) {
    if (chatState.isSwitchingSession) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('切换会话中…',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (chatState.messages.isEmpty &&
        chatState.connectionStatus == ConnectionStatus.connected) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                size: 48, color: colorScheme.onSurface.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text('暂无消息',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 4),
            Text('在 VS Code 中开始对话',
                style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withOpacity(0.3))),
          ],
        ),
      );
    }

    if (chatState.messages.isEmpty &&
        chatState.connectionStatus != ConnectionStatus.connected) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 48, color: colorScheme.onSurface.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text('未连接',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 4),
            Text('启动 Node.js Bridge 来连接',
                style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withOpacity(0.3))),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                final url = ref.read(settingsProvider).bridgeUrl;
                ref.read(chatProvider.notifier).connect(url);
              },
              icon: const Icon(Icons.link_rounded),
              label: const Text('连接'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          itemCount: chatState.messages.length,
          itemBuilder: (context, index) {
            final msg = chatState.messages[index];
            return MessageBubble(message: msg);
          },
        ),
        if (chatState.errorMessage != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(chatState.errorMessage!,
                          style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onErrorContainer)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        ref.read(chatProvider.notifier).clearError();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _refresh(WidgetRef ref) {
    final notifier = ref.read(chatProvider.notifier);
    notifier.refresh();
  }

  /// Show settings dialog to configure CDP connection
  Future<void> _showSettingsDialog(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    final controller = TextEditingController(text: settings.bridgeUrl);
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CDP 连接设置'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'CDP WebSocket URL',
              hintText: 'ws://127.0.0.1:9229/devtools/page/...',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return '请输入 WebSocket URL';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final newUrl = controller.text.trim();
                ref.read(settingsProvider.notifier).setBridgeUrl(newUrl);
                Navigator.pop(ctx);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _showSessionDrawer(BuildContext context, WidgetRef ref) async {
    await ref.read(chatProvider.notifier).listSessions();
    if (!context.mounted) {
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      builder: (ctx) => SessionDrawer(ref: ref),
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  final ConnectionStatus status;
  final ColorScheme colorScheme;

  const _ConnectionDot({required this.status, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case ConnectionStatus.connected:
        color = Colors.green;
        break;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        color = Colors.orange;
        break;
      case ConnectionStatus.disconnected:
        color = Colors.grey;
        break;
      case ConnectionStatus.failed:
        color = Colors.red;
        break;
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
