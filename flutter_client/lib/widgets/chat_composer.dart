import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../models/types.dart';
import '../models/slash_command.dart';
import '../theme/vscode_colors.dart';
import 'glass_container.dart';

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
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextOrStateChanged);
  }

  void _onTextOrStateChanged() {
    // Called on both text changes and isSending changes via setState
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextOrStateChanged);
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
    _isSending = chatState.isSending;
    final colorScheme = Theme.of(context).colorScheme;

    // Auto-unfocus when disconnected
    if (!isConnected && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CompositedTransformTarget(
            link: _slashLayerLink,
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              blur: 20,
              opacity: 0.8,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Theme.of(context).dividerColor.withOpacity(0.1),
                width: 0.5,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Slash command button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: isConnected ? () => _showSlashMenu(ref) : null,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isConnected
                              ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4)
                              : Colors.grey.withOpacity(0.1),
                        ),
                        child: Icon(
                          Icons.alternate_email_rounded,
                          size: 20,
                          color: isConnected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: isConnected && !isSending,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 8,
                      decoration: InputDecoration(
                        hintText: isConnected ? '问问 Copilot…' : '未连接',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 10),
                        hintStyle: TextStyle(
                          color: Theme.of(context).hintColor.withOpacity(0.5),
                          fontSize: 15,
                        ),
                      ),
                      style: const TextStyle(fontSize: 15),
                      onSubmitted: (_) => _send(ref),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Send/Stop button (reacts to both text changes and isSending state)
                  _AnimatedSendButton(
                    showStop: _isSending,
                    canSend: isConnected && !_isSending && _controller.text.trim().isNotEmpty,
                    onStop: () => ref.read(chatProvider.notifier).stopGeneration(),
                    onSend: () => _send(ref),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small animated send/stop button that rebuilds whenever its parent
/// detects a change in text or sending state (via setState).
class _AnimatedSendButton extends StatelessWidget {
  final bool showStop;
  final bool canSend;
  final VoidCallback onStop;
  final VoidCallback onSend;

  const _AnimatedSendButton({
    required this.showStop,
    required this.canSend,
    required this.onStop,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: !showStop && canSend
            ? const LinearGradient(
                colors: VSCodeColors.copilotGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: showStop
            ? Colors.red.withOpacity(0.8)
            : canSend
                ? null
                : Theme.of(context).disabledColor.withOpacity(0.1),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: showStop
            ? const Icon(Icons.stop_rounded, size: 22, color: Colors.white)
            : Icon(
                Icons.arrow_upward_rounded,
                size: 22,
                color: canSend ? Colors.white : Colors.grey.withOpacity(0.5),
              ),
        onPressed: showStop ? onStop : (canSend ? onSend : null),
      ),
    );
  }
}
