import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../models/types.dart';
import '../models/slash_command.dart';

class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({super.key});

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _slashLayerLink = LayerLink();
  OverlayEntry? _slashOverlay;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _removeSlashOverlay();
    super.dispose();
  }

  void _send(WidgetRef ref) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final state = ref.read(chatProvider);
    if (state.connectionStatus != ConnectionStatus.connected) return;

    ref.read(chatProvider.notifier).sendMessage(text);
    _controller.clear();
    _focusNode.unfocus();
  }

  void _showSlashMenu(WidgetRef ref) {
    _removeSlashOverlay();
    ref.read(chatProvider.notifier).listSlashCommands();

    _slashOverlay = OverlayEntry(
      builder: (context) {
        return Consumer(builder: (ctx, watchRef, _) {
          final state = watchRef.watch(chatProvider);
          final slashCommands = state.slashCommands;

          if (slashCommands.isEmpty) {
            return const SizedBox.shrink();
          }

          return Positioned(
            width: 280,
            child: CompositedTransformFollower(
              link: _slashLayerLink,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: const Offset(0, -8),
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    itemCount: slashCommands.length,
                    itemBuilder: (ctx, i) {
                      final cmd = slashCommands[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.terminal_rounded,
                            size: 16,
                            color: Theme.of(context)
                                .colorScheme
                                .primary),
                        title: Text(cmd.label,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: cmd.description != null
                            ? Text(cmd.description!,
                                style: const TextStyle(fontSize: 11))
                            : null,
                        onTap: () {
                          _removeSlashOverlay();
                          ref
                              .read(chatProvider.notifier)
                              .applySlashCommand(cmd.index);
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        });
      },
    );

    Overlay.of(context).insert(_slashOverlay!);
  }

  void _removeSlashOverlay() {
    _slashOverlay?.remove();
    _slashOverlay = null;
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final isConnected =
        chatState.connectionStatus == ConnectionStatus.connected;
    final isSending = chatState.isSending;
    final colorScheme = Theme.of(context).colorScheme;

    // Auto-unfocus when disconnected
    if (!isConnected && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 6,
        bottom: MediaQuery.of(context).padding.bottom + 6,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1F),
        border: Border(
          top: BorderSide(
            color: Color(0xFF2A2A2E),
          ),
        ),
      ),
      child: CompositedTransformTarget(
        link: _slashLayerLink,
        child: Row(
          children: [
            // Slash command button
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: isConnected ? () => _showSlashMenu(ref) : null,
                child: Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isConnected
                          ? const Color(0xFF6366F1)
                          : const Color(0xFF3F3F46),
                    ),
                  ),
                  child: Icon(
                    Icons.terminal_rounded,
                    size: 18,
                    color: isConnected
                        ? const Color(0xFF6366F1)
                        : const Color(0xFF52525B),
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
              enabled: isConnected && !isSending,
              textInputAction: TextInputAction.send,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: isConnected ? 'Message…' : 'Not connected',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: const Color(0xFF1E1E24),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                hintStyle: const TextStyle(
                  color: Color(0xFF52525B),
                ),
              ),
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFFE4E4E7),
              ),
              onSubmitted: (_) => _send(ref),
            ),
          ),
          const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            child: isSending
                ? SizedBox(
                    width: 38,
                    height: 38,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  )
                : Material(
                    color: isConnected
                        ? const Color(0xFF6366F1)
                        : const Color(0xFF3F3F46),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: isConnected ? () => _send(ref) : null,
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          color: isConnected
                              ? Colors.white
                              : const Color(0xFF71717A),
                          size: 20,
                        ),
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
