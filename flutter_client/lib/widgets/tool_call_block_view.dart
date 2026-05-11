import 'package:flutter/material.dart';
import '../models/message.dart';

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
    final colorScheme = Theme.of(context).colorScheme;
    final toolName = block.title ?? block.language ?? 'Tool';
    final status = block.status;
    final isError = block.isError;

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case MirrorStatus.pending:
        statusColor = Colors.grey;
        statusIcon = Icons.schedule_rounded;
      case MirrorStatus.running:
        statusColor = Colors.blue;
        statusIcon = Icons.sync_rounded;
      case MirrorStatus.success:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_rounded;
      case MirrorStatus.error:
        statusColor = Colors.red;
        statusIcon = Icons.error_rounded;
      case MirrorStatus.streaming:
        statusColor = Colors.blue;
        statusIcon = Icons.horizontal_rule_rounded;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isError
              ? colorScheme.errorContainer.withOpacity(0.3)
              : colorScheme.surfaceContainerLow,
          border: Border.all(
            color: isError
                ? colorScheme.error.withOpacity(0.3)
                : colorScheme.outline.withOpacity(0.15),
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
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      )),
                  if (block.content.isNotEmpty)
                    Text(
                      block.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                ],
              ),
            ),
            if (status == MirrorStatus.running)
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
