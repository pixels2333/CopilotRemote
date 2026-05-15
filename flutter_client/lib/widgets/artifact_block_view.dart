import 'package:flutter/material.dart';
import '../models/message.dart';

class ArtifactBlockView extends StatelessWidget {
  final MirrorBlock block;
  const ArtifactBlockView({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final artifactName = block.fileName ?? block.language ?? 'Artifact';
    final artifactType = block.language ?? 'file';

    IconData typeIcon;
    switch (artifactType.toLowerCase()) {
      case 'html':
      case 'svg':
        typeIcon = Icons.code_rounded;
      case 'image':
      case 'png':
      case 'jpg':
        typeIcon = Icons.image_rounded;
      case 'markdown':
      case 'md':
        typeIcon = Icons.article_rounded;
      case 'json':
      case 'yaml':
      case 'xml':
        typeIcon = Icons.data_object_rounded;
      default:
        typeIcon = Icons.insert_drive_file_rounded;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          color: Color(0x0FFBBF24),
          border: Border.fromBorderSide(BorderSide(color: Color(0x40FBBF24))),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0x1AFBBF24),
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              child: Center(
                child: Icon(typeIcon,
                    size: 20, color: const Color(0xFFFBBF24)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(artifactName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE4E4E7),
                      )),
                  Text(artifactType,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF71717A),
                      )),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                // TODO: open artifact — leave to device
              },
              icon: Icon(Icons.open_in_new_rounded,
                  size: 18, color: colorScheme.primary),
              tooltip: 'Open artifact',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}
