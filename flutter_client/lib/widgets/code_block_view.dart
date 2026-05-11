import 'package:flutter/material.dart';
import '../models/message.dart';

class CodeBlockView extends StatelessWidget {
  final MirrorBlock block;
  const CodeBlockView({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lang = block.language ?? '';
    final code = block.content;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: colorScheme.surfaceContainerLowest,
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(10),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.code_rounded,
                      size: 14,
                      color: colorScheme.onSurface.withOpacity(0.5)),
                  const SizedBox(width: 6),
                  Text(
                    lang.isNotEmpty ? lang : 'code',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface.withOpacity(0.5),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      // Copy to clipboard — simplified for now
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.copy_rounded,
                          size: 14,
                          color: colorScheme.onSurface.withOpacity(0.4)),
                    ),
                  ),
                ],
              ),
            ),
            // Code content
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: SelectableText(
                  code,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 1.6,
                    color: colorScheme.onSurface.withOpacity(0.85),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
