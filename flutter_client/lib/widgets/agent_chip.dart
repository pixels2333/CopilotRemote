import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../models/agent.dart';
import '../models/types.dart';

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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: chatState.connectionStatus == ConnectionStatus.connected
              ? () => _showAgentPicker(context, ref, chatState)
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(width: 2),
                Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: colorScheme.onSurface.withOpacity(0.4)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAgentPicker(BuildContext context, WidgetRef ref, ChatState chatState) {
    ref.read(chatProvider.notifier).listAgents();

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Consumer(builder: (ctx, watchRef, _) {
          final agents = watchRef.watch(chatProvider).agents;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Theme.of(context).dividerColor.withOpacity(0.2), borderRadius: BorderRadius.circular(2))),
                const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('切换预览 Agent', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
                if (agents.isEmpty) const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(strokeWidth: 2))
                else Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                      children: agents.map((a) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            selected: a.active,
                            selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                            leading: Icon(a.active ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined, color: a.active ? Theme.of(context).colorScheme.primary : null),
                            title: Text(a.name, style: TextStyle(fontWeight: a.active ? FontWeight.bold : FontWeight.normal)),
                            subtitle: a.description != null ? Text(a.description!, style: const TextStyle(fontSize: 12)) : null,
                            trailing: a.active ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary, size: 20) : null,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              ref.read(chatProvider.notifier).switchAgent(a.id, index: a.index, name: a.name);
                            },
                          ),
                        )).toList(),
                    ),
                  ),
              ],
            ),
          );
        }),
    );
  }
}

