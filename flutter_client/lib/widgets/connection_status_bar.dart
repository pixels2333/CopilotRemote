import 'package:flutter/material.dart';
import '../models/types.dart';
import '../providers/chat_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConnectionStatusBar extends ConsumerWidget {
  const ConnectionStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(chatProvider.select((s) => s.connectionStatus));

    Color bgColor;
    Color fgColor;
    IconData icon;
    String text;

    switch (status) {
      case ConnectionStatus.connected:
        bgColor = const Color(0xFF166534);
        fgColor = const Color(0xFF4ADE80);
        icon = Icons.cloud_done_rounded;
        text = '已连接';
      case ConnectionStatus.connecting:
        bgColor = const Color(0xFF9A3412);
        fgColor = const Color(0xFFFBBF24);
        icon = Icons.cloud_upload_rounded;
        text = '连接中…';
      case ConnectionStatus.reconnecting:
        bgColor = const Color(0xFF9A3412);
        fgColor = const Color(0xFFFBBF24);
        icon = Icons.cloud_sync_rounded;
        text = '重连中…';
      case ConnectionStatus.disconnected:
        bgColor = const Color(0xFF374151);
        fgColor = const Color(0xFFA1A1AA);
        icon = Icons.cloud_off_rounded;
        text = '已断开';
      case ConnectionStatus.failed:
        bgColor = const Color(0xFF991B1B);
        fgColor = const Color(0xFFFCA5A5);
        icon = Icons.error_outline_rounded;
        text = '连接失败';
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
