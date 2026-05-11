import 'package:flutter/material.dart';
import '../models/types.dart';
import '../providers/chat_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConnectionStatusBar extends ConsumerWidget {
  const ConnectionStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(chatProvider.select((s) => s.connectionStatus));
    final colorScheme = Theme.of(context).colorScheme;

    Color bgColor;
    Color fgColor;
    IconData icon;
    String text;

    switch (status) {
      case ConnectionStatus.connected:
        bgColor = Colors.green.shade900;
        fgColor = Colors.green.shade200;
        icon = Icons.cloud_done_rounded;
        text = 'Connected';
      case ConnectionStatus.connecting:
        bgColor = Colors.orange.shade900;
        fgColor = Colors.orange.shade200;
        icon = Icons.cloud_upload_rounded;
        text = 'Connecting…';
      case ConnectionStatus.reconnecting:
        bgColor = Colors.orange.shade900;
        fgColor = Colors.orange.shade200;
        icon = Icons.cloud_sync_rounded;
        text = 'Reconnecting…';
      case ConnectionStatus.disconnected:
        bgColor = colorScheme.surfaceContainerHighest;
        fgColor = colorScheme.onSurface.withOpacity(0.6);
        icon = Icons.cloud_off_rounded;
        text = 'Disconnected';
      case ConnectionStatus.failed:
        bgColor = Colors.red.shade900;
        fgColor = Colors.red.shade200;
        icon = Icons.error_outline_rounded;
        text = 'Connection Failed';
    }

    return Container(
      height: 28,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(icon, size: 14, color: fgColor),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(fontSize: 12, color: fgColor)),
        ],
      ),
    );
  }
}
