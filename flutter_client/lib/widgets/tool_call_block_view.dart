import 'package:flutter/material.dart';
import '../models/message.dart';
import '../models/types.dart';

class ToolCallBlockView extends StatelessWidget {
  final MirrorBlock block;
  const ToolCallBlockView({super.key, required this.block});

  IconData _iconForTool(String? toolName) {
    final name = (toolName ?? '').toLowerCase();
    if (name.contains('search') || name.contains('grep') || name.contains('find')) {
      return Icons.search_rounded;
    }
    if (name.contains('read') || name.contains('file') || name.contains('list')) {
      return Icons.description_rounded;
    }
    if (name.contains('edit') || name.contains('write') || name.contains('create')) {
      return Icons.edit_rounded;
    }
    if (name.contains('run') || name.contains('exec') || name.contains('bash')) {
      return Icons.terminal_rounded;
    }
    if (name.contains('web') || name.contains('fetch') || name.contains('browse')) {
      return Icons.language_rounded;
    }
    return Icons.build_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final toolName = block.displayName ??
      block.toolName ??
      block.language ??
      block.metadata?['name'] as String? ??
      'Tool';
    final summary = block.summary ?? block.content;
    final status = block.toolState == ToolState.running
      ? MirrorStatus.streaming
      : (block.toolState == ToolState.failed
        ? MirrorStatus.failed
        : block.status);
    final isError = status == MirrorStatus.failed;

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case MirrorStatus.pending:
        statusColor = Colors.grey;
        statusIcon = Icons.schedule_rounded;
      case MirrorStatus.streaming:
        statusColor = Colors.blue;
        statusIcon = Icons.sync_rounded;
      case MirrorStatus.completed:
        statusColor = const Color(0xFF4ADE80);
        statusIcon = Icons.check_circle_outline_rounded;
      case MirrorStatus.failed:
        statusColor = Colors.red;
        statusIcon = Icons.error_outline_rounded;
      case MirrorStatus.cancelled:
        statusColor = Colors.amber;
        statusIcon = Icons.cancel_outlined;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isError
              ? const Color(0x157F1D1D)
              : const Color(0x0F4ADE80),
          border: Border.all(
            color: isError
                ? const Color(0x407F1D1D)
                : const Color(0x404ADE80),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(_iconForTool(toolName),
                    size: 16, color: statusColor),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(toolName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF4ADE80),
                      )),
                  if (summary.isNotEmpty)
                    Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF71717A),
                      ),
                    ),
                ],
              ),
            ),
            if (status == MirrorStatus.streaming)
              SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: statusColor,
                ),
              )
            else
              Icon(statusIcon, size: 18, color: statusColor),
          ],
        ),
      ),
    );
  }
}
