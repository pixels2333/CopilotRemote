import 'package:flutter/material.dart';
import '../models/message.dart';

class TextBlockView extends StatelessWidget {
  final MirrorBlock block;

  const TextBlockView({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final content = block.visibleContent.isNotEmpty
        ? block.visibleContent
        : block.content;
    if (content.isEmpty &&
        block.status == MirrorStatus.streaming) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: LinearProgressIndicator(),
      );
    }
    if (content.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText(
        content,
        style: TextStyle(
          fontSize: 14,
          height: 1.6,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
