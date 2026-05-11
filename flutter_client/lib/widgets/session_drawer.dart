import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../models/session.dart';

class SessionDrawer extends ConsumerWidget {
  final WidgetRef ref;

  const SessionDrawer({super.key, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef _) {
    final chatState = ref.watch(chatProvider);
    final sessions = chatState.sessions;
    final activeId = chatState.activeSessionId;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.swap_horiz_rounded,
                    size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('Switch Session',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    )),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    ref.read(chatProvider.notifier).newSession();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),

          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.inbox_rounded,
                      size: 36,
                      color: colorScheme.onSurface.withOpacity(0.2)),
                  const SizedBox(height: 8),
                  Text('No sessions available',
                      style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.4))),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  final isActive = session.sessionId == activeId;
                  return ListTile(
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isActive
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Icon(
                          isActive
                              ? Icons.chat_bubble_rounded
                              : Icons.chat_bubble_outline_rounded,
                          size: 18,
                          color: isActive
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ),
                    title: Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.normal,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    subtitle: session.preview != null
                        ? Text(
                            session.preview!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  colorScheme.onSurface.withOpacity(0.4),
                            ),
                          )
                        : null,
                    trailing: isActive
                        ? Icon(Icons.check_circle_rounded,
                            color: colorScheme.primary, size: 20)
                        : null,
                    selected: isActive,
                    selectedTileColor:
                        colorScheme.primaryContainer.withOpacity(0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onTap: isActive
                        ? null
                        : () {
                            ref.read(chatProvider.notifier).switchSession(
                                  session.sessionId,
                                  index: session.index,
                                  title: session.title,
                                );
                            Navigator.pop(context);
                          },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
