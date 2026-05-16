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
import '../widgets/glass_container.dart';
import '../theme/vscode_colors.dart';
import 'settings_screen.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: GlassContainer(
          borderRadius: BorderRadius.zero,
          blur: 15,
          opacity: 0.7,
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.3), width: 0.5),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: VSCodeColors.copilotGradient,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: VSCodeColors.accentCopilot.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.blur_on_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Copilot Mirror',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (chatState.activeSessionId != null)
                        Text(
                          (chatState.activeSessionId!.split('_').tryGet(1) as String?)
                              ?.replaceAll('_', ' ') ?? 'Default Session',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.primary.withOpacity(0.8),
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
              const SizedBox(width: 4),
              // Action buttons with subtle backgrounds
              _AppBarAction(
                icon: Icons.settings_outlined,
                tooltip: '设置',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
              _AppBarAction(
                icon: Icons.refresh_rounded,
                tooltip: '刷新/重新同步',
                isLoading: chatState.isLoadingSessions,
                onPressed: () => _refresh(ref),
              ),
              if (chatState.connectionStatus == ConnectionStatus.connected)
                _AppBarAction(
                  icon: Icons.swap_horiz_rounded,
                  tooltip: '切换会话',
                  onPressed: () => _showSessionDrawer(context, ref),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // Background decoration if any, otherwise just full body
          Column(
            children: [
              Expanded(
                child: _buildBody(context, ref, chatState, colorScheme),
              ),
            ],
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ChatComposer(),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + kToolbarHeight,
            left: 0,
            right: 0,
            child: const ConnectionStatusBar(),
          ),
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
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: VSCodeColors.copilotGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: VSCodeColors.accentCopilot.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () {
                  final url = ref.read(settingsProvider).bridgeUrl;
                  ref.read(chatProvider.notifier).connect(url);
                },
                icon: const Icon(Icons.link_rounded, color: Colors.white),
                label: const Text(
                  '立即连接',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ListView.builder(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
            bottom: 110,
          ),
          itemCount: chatState.messages.length,
          itemBuilder: (context, index) {
            final msg = chatState.messages[index];
            return MessageBubble(message: msg);
          },
        ),
        if (chatState.errorMessage != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + kToolbarHeight + 10,
            left: 0,
            right: 0,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.error.withOpacity(0.3)),
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

class _AppBarAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isLoading;

  const _AppBarAction({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: IconButton(
        onPressed: isLoading ? null : onPressed,
        tooltip: tooltip,
        icon: isLoading 
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 22),
        style: IconButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

extension on List {
  Object? tryGet(int index) => index < length ? this[index] : null;
}
