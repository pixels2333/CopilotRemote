import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../models/types.dart';
import '../widgets/connection_status_bar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_composer.dart';
import '../widgets/session_drawer.dart';
import '../widgets/agent_chip.dart';

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
          if (chatState.connectionStatus == ConnectionStatus.connected)
            IconButton(
              icon: const Icon(Icons.swap_horiz_rounded),
              tooltip: 'Switch session',
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
            Text('Switching session…',
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
            Text('No messages yet',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 4),
            Text('Start a conversation in VS Code',
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
            Text('Not connected',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 4),
            Text('Start the Node.js Bridge to connect.',
                style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withOpacity(0.3))),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                ref.read(chatProvider.notifier).connect(
                    'ws://127.0.0.1:17321/copilot-mirror/ws');
              },
              icon: const Icon(Icons.link_rounded),
              label: const Text('Connect'),
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

  void _showSessionDrawer(BuildContext context, WidgetRef ref) {
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
