import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../models/agent.dart';
import '../models/types.dart';

/// A tappable chip showing the current active agent.
/// Opens a bottom sheet to list and switch agents.
class AgentChip extends ConsumerWidget {
  const AgentChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider);
    final activeAgentId = chatState.activeAgentId;
    final activeAgent = chatState.agents.where((a) => a.active).firstOrNull;
    final label = activeAgent?.name ?? activeAgentId ?? 'Agent';
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: 'Switch agent',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: chatState.connectionStatus == ConnectionStatus.connected
            ? () => _showAgentPicker(context, ref, chatState)
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.outline.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smart_toy_rounded,
                  size: 14, color: colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down_rounded,
                  size: 14, color: colorScheme.onSurface.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }

  void _showAgentPicker(
      BuildContext context, WidgetRef ref, ChatState chatState) {
    ref.read(chatProvider.notifier).listAgents();

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Consumer(builder: (ctx, watchRef, _) {
          final state = watchRef.watch(chatProvider);
          final agents = state.agents;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Switch Agent',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              if (agents.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                ...agents.map(
                  (a) => ListTile(
                    leading: Icon(
                      a.active
                          ? Icons.smart_toy_rounded
                          : Icons.smart_toy_outlined,
                      color: a.active
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(a.name),
                    subtitle:
                        a.description != null ? Text(a.description!) : null,
                    trailing:
                        a.active ? const Icon(Icons.check, size: 18) : null,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      ref
                          .read(chatProvider.notifier)
                          .switchAgent(a.id, index: a.index, name: a.name);
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          );
        });
      },
    );
  }
}
