import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          color: Color(0xFF18181B),
          border: Border.fromBorderSide(BorderSide(color: Color(0xFF27272A))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: const BoxDecoration(
                color: Color(0xFF1F1F23),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(10),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.code_rounded,
                      size: 14,
                      color: Color(0xFF71717A)),
                  const SizedBox(width: 6),
                  Text(
                    lang.isNotEmpty ? lang : 'code',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF71717A),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.copy_rounded,
                          size: 14,
                          color: Color(0xFF71717A)),
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
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 1.6,
                    color: Color(0xFFE4E4E7),
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
