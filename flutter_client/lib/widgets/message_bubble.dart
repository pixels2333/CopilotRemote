import 'package:flutter/material.dart';
import '../models/message.dart';
import '../models/types.dart';
import '../theme/vscode_colors.dart';
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : (isSystem ? CrossAxisAlignment.center : CrossAxisAlignment.start),
        children: [
          // Role label for assistant
          if (isAssistant)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: VSCodeColors.copilotGradient),
                    ),
                    child: const Center(
                        child: Text('✦',
                            style: TextStyle(fontSize: 12, color: Colors.white))),
                  ),
                  const SizedBox(width: 6),
                  const Text('Copilot',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFA78BFA))),
                ],
              ),
            ),

          // Bubble
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.88,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: isUser
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: VSCodeColors.copilotGradient,
                    )
                  : null,
              color: !isUser
                  ? (isSystem
                      ? const Color(0xFF27272A).withOpacity(0.5)
                      : const Color(0xFF252526))
                  : null,
              border: Border.all(
                color: isUser 
                  ? Colors.white.withOpacity(0.1) 
                  : (isAssistant ? Color(0x33FFFFFF) : Colors.transparent),
                width: 0.8,
              ),
              borderRadius: BorderRadius.circular(22).copyWith(
                bottomLeft: isUser ? const Radius.circular(22) : const Radius.circular(6),
                bottomRight: isUser ? const Radius.circular(6) : const Radius.circular(22),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
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
