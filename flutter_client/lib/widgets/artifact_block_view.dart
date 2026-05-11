import 'package:flutter/material.dart';
import '../models/message.dart';

class ArtifactBlockView extends StatelessWidget {
  final MirrorBlock block;
  const ArtifactBlockView({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final artifactName = block.title ?? 'Artifact';
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: colorScheme.primaryContainer.withOpacity(0.15),
          border: Border.all(
            color: colorScheme.primary.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(typeIcon,
                    size: 20, color: colorScheme.primary),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(artifactName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      )),
                  Text(artifactType,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withOpacity(0.4),
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
