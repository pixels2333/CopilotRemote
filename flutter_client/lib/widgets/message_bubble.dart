import 'package:flutter/material.dart';
import '../models/message.dart';
import '../models/types.dart';
import 'text_block_view.dart';
import 'thinking_block_view.dart';
import 'code_block_view.dart';
import 'tool_call_block_view.dart';
import 'artifact_block_view.dart';

class MessageBubble extends StatelessWidget {
  final MirrorMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = message.role == MessageRole.user;
    final isAssistant = message.role == MessageRole.assistant;
    final isSystem = message.role == MessageRole.system;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : (isSystem ? CrossAxisAlignment.center : CrossAxisAlignment.start),
        children: [
          // Role label for assistant
          if (isAssistant)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🤖', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  Text('Copilot',
                      style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.primary.withOpacity(0.7))),
                ],
              ),
            ),

          // Bubble
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUser
                  ? colorScheme.primaryContainer
                  : (isSystem
                      ? colorScheme.surfaceContainerHighest
                      : colorScheme.surfaceContainerHigh),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: isUser
                    ? const Radius.circular(16)
                    : const Radius.circular(4),
                bottomRight: isUser
                    ? const Radius.circular(4)
                    : const Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: message.blocks.map((block) {
                return _buildBlock(block, colorScheme);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlock(MirrorBlock block, ColorScheme colorScheme) {
    switch (block.type) {
      case BlockType.text:
        return TextBlockView(block: block);
      case BlockType.thinking:
        return ThinkingBlockView(block: block);
      case BlockType.codeBlock:
        return CodeBlockView(block: block);
      case BlockType.toolCall:
        return ToolCallBlockView(block: block);
      case BlockType.artifact:
        return ArtifactBlockView(block: block);
    }
  }
}
