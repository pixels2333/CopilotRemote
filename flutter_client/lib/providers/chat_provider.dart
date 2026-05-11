import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/envelope.dart';
import '../models/session.dart';
import '../models/message.dart';
import '../models/types.dart';
import '../models/slash_command.dart';
import '../models/agent.dart';
import '../services/websocket_service.dart';
import '../services/protocol_decoder.dart';

/// Immutable chat state
class ChatState {
  final List<MirrorMessage> messages;
  final ConnectionStatus connectionStatus;
  final String? sessionId;
  final int lastSeq;
  final bool isSending;
  final String? errorMessage;
  final List<MirrorChatSession> sessions;
  final String? activeSessionId;
  final bool isSwitchingSession;
  final List<MirrorSlashCommandItem> slashCommands;
  final List<MirrorAgentItem> agents;
  final String? activeAgentId;

  const ChatState({
    this.messages = const [],
    this.connectionStatus = ConnectionStatus.disconnected,
    this.sessionId,
    this.lastSeq = 0,
    this.isSending = false,
    this.errorMessage,
    this.sessions = const [],
    this.activeSessionId,
    this.isSwitchingSession = false,
    this.slashCommands = const [],
    this.agents = const [],
    this.activeAgentId,
  });

  ChatState copyWith({
    List<MirrorMessage>? messages,
    ConnectionStatus? connectionStatus,
    String? sessionId,
    int? lastSeq,
    bool? isSending,
    String? errorMessage,
    List<MirrorChatSession>? sessions,
    String? activeSessionId,
    bool? isSwitchingSession,
    List<MirrorSlashCommandItem>? slashCommands,
    List<MirrorAgentItem>? agents,
    String? activeAgentId,
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      sessionId: sessionId ?? this.sessionId,
      lastSeq: lastSeq ?? this.lastSeq,
      isSending: isSending ?? this.isSending,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      isSwitchingSession: isSwitchingSession ?? this.isSwitchingSession,
      slashCommands: slashCommands ?? this.slashCommands,
      agents: agents ?? this.agents,
      activeAgentId: activeAgentId ?? this.activeAgentId,
    );
  }
}

/// Riverpod provider for the WebSocket service
final websocketServiceProvider = Provider<WebSocketService?>((ref) => null);

/// The core chat state notifier
class ChatNotifier extends StateNotifier<ChatState> {
  final Uuid _uuid = const Uuid();
  WebSocketService? _wsService;
  StreamSubscription? _messageSub;
  StreamSubscription? _statusSub;
  Timer? _typewriterTimer;
  int _seq = 0;

  ChatNotifier() : super(const ChatState());

  /// Connect to the bridge at [url] with optional [authToken]
  Future<void> connect(String url, {String? authToken}) async {
    state = state.copyWith(connectionStatus: ConnectionStatus.connecting);

    _wsService?.dispose();
    _wsService = WebSocketService(url: url, authToken: authToken);

    _messageSub = _wsService!.messages.listen(_onRawMessage);
    _statusSub = _wsService!.onStatusChange.listen((connected) {
      state = state.copyWith(
        connectionStatus:
            connected ? ConnectionStatus.connected : ConnectionStatus.reconnecting,
      );
    });

    await _wsService!.connect();
  }

  /// Send a user message
  void sendMessage(String text) {
    if (text.trim().isEmpty || state.isSending) return;

    final requestId = _uuid.v4();
    state = state.copyWith(isSending: true, clearError: true);

    _send('client.command.sendMessage', {
      'text': text,
      'submit': true,
      'focus': true,
    }, requestId: requestId);
  }

  /// Request stop generation
  void stopGeneration() {
    _send('client.command.stopGeneration', {});
  }

  /// Focus the input on desktop
  void focusInput() {
    _send('client.command.focusInput', {});
  }

  /// Disconnect from the bridge
  void disconnect() {
    _typewriterTimer?.cancel();
    _messageSub?.cancel();
    _statusSub?.cancel();
    _wsService?.disconnect();
    _wsService?.dispose();
    _wsService = null;
    state = state.copyWith(connectionStatus: ConnectionStatus.disconnected);
  }

  // ── Session management ──

  /// Request session list
  void listSessions() {
    _send('client.command.listSessions', {});
  }

  /// Switch to another session
  void switchSession(String sessionId, {int? index, String? title}) {
    _send('client.command.switchSession', {
      if (sessionId.isNotEmpty) 'sessionId': sessionId,
      if (index != null) 'index': index,
      if (title != null) 'title': title,
    });
    state = state.copyWith(isSwitchingSession: true);
  }

  /// Create a new session
  void newSession() {
    _send('client.command.newSession', {});
  }

  // ── Slash command management ──

  /// Request slash command list
  void listSlashCommands({String? query}) {
    _send('client.command.listSlashCommands', {
      if (query != null) 'query': query,
    });
  }

  /// Apply a slash command by index
  void applySlashCommand(int index, {bool insertOnly = false}) {
    _send('client.command.applySlashCommand', {
      'index': index,
      'insertOnly': insertOnly,
    });
  }

  // ── Agent management ──

  /// Request agent list
  void listAgents() {
    _send('client.command.listAgents', {});
  }

  /// Switch to another agent
  void switchAgent(String? agentId, {int? index, String? name}) {
    _send('client.command.switchAgent', {
      if (agentId != null) 'agentId': agentId,
      if (index != null) 'index': index,
      if (name != null) 'name': name,
    });
  }

  void _send(String type, Map<String, dynamic> payload, {String? requestId}) {
    _wsService?.send({
      'v': 1,
      'seq': ++_seq,
      'type': type,
      'sessionId': state.sessionId,
      if (requestId != null) 'requestId': requestId,
      'payload': payload,
    });
  }

  void _onRawMessage(Map<String, dynamic> raw) {
    final event = decodeProtocolEvent(raw);
    final seq = event.envelope.seq;

    // Deduplicate
    if (seq > 0 && seq <= state.lastSeq) return;

    switch (event) {
      case ServerHello e:
        _onServerHello(e);
      case SessionSnapshot e:
        _onSessionSnapshot(e);
      case MessageStart e:
        _onMessageStart(e);
      case BlockStart e:
        _onBlockStart(e);
      case BlockDelta e:
        _onBlockDelta(e);
      case BlockUpdate e:
        _onBlockUpdate(e);
      case BlockEnd e:
        _onBlockEnd(e);
      case MessageEnd e:
        _onMessageEnd(e);
      case ServerAck e:
        _onServerAck(e);
      case ServerError e:
        _onServerError(e);
      case ServerStatus e:
        state = state.copyWith(
          lastSeq: seq > 0 ? seq : state.lastSeq,
        );
      case SessionList e:
        _onSessionList(e);
      case SessionSwitched e:
        _onSessionSwitched(e);
      case SlashList e:
        _onSlashList(e);
      case AgentList e:
        _onAgentList(e);
      case AgentSwitched e:
        _onAgentSwitched(e);
      case UnknownEvent _:
        break;
    }
  }

  void _onServerHello(ServerHello e) {
    final session = e.hello.session;
    state = state.copyWith(
      connectionStatus: ConnectionStatus.connected,
      sessionId: session['sessionId'] as String?,
      lastSeq: e.envelope.seq,
    );
  }

  void _onSessionSnapshot(SessionSnapshot e) {
    final messages = e.snapshot.messages
        .map((m) => MirrorMessage.fromJson(m))
        .toList();
    state = state.copyWith(
      messages: messages,
      lastSeq: e.envelope.seq,
    );
    _startTypewriter();
  }

  void _onMessageStart(MessageStart e) {
    final msg = MirrorMessage.fromJson(e.message);
    state = state.copyWith(
      messages: [...state.messages, msg],
      lastSeq: e.envelope.seq,
    );
  }

  void _onBlockStart(BlockStart e) {
    final msgs = List<MirrorMessage>.from(state.messages);
    final idx = msgs.indexWhere((m) => m.id == e.messageId);
    if (idx < 0) return;

    final block = MirrorBlock.fromJson(e.block);
    msgs[idx] = msgs[idx].copyWith(
      blocks: () => [...msgs[idx].blocks, block],
      status: () => MirrorStatus.streaming,
    );
    state = state.copyWith(messages: msgs, lastSeq: e.envelope.seq);
  }

  void _onBlockDelta(BlockDelta e) {
    final d = e.delta;
    final msgs = List<MirrorMessage>.from(state.messages);
    final msgIdx = msgs.indexWhere((m) => m.id == d.messageId);
    if (msgIdx < 0) return;

    final blockIdx = msgs[msgIdx].blocks.indexWhere((b) => b.id == d.blockId);
    if (blockIdx < 0) return;

    final block = msgs[msgIdx].blocks[blockIdx];
    final newContent = d.op == DeltaOp.append && d.offset == block.content.length
        ? block.content + d.chunk
        : (d.op == DeltaOp.replace ? d.chunk : block.content + d.chunk);

    msgs[msgIdx] = msgs[msgIdx].copyWith(
      blocks: () {
        final updated = List<MirrorBlock>.from(msgs[msgIdx].blocks);
        updated[blockIdx] = block.copyWith(
          content: newContent,
          status: MirrorStatus.streaming,
        );
        return updated;
      },
    );
    state = state.copyWith(messages: msgs, lastSeq: e.envelope.seq);
  }

  void _onBlockUpdate(BlockUpdate e) {
    final msgs = List<MirrorMessage>.from(state.messages);
    final msgIdx = msgs.indexWhere((m) => m.id == e.messageId);
    if (msgIdx < 0) return;

    final blockIdx =
        msgs[msgIdx].blocks.indexWhere((b) => b.id == e.blockId);
    if (blockIdx < 0) return;

    final current = msgs[msgIdx].blocks[blockIdx];
    msgs[msgIdx] = msgs[msgIdx].copyWith(
      blocks: () {
        final updated = List<MirrorBlock>.from(msgs[msgIdx].blocks);
        updated[blockIdx] = current.copyWith(
          metadata: e.patch,
          toolState: e.patch['toolState'] != null
              ? ToolState.fromJson(e.patch['toolState'] as String)
              : current.toolState,
        );
        return updated;
      },
    );
    state = state.copyWith(messages: msgs, lastSeq: e.envelope.seq);
  }

  void _onBlockEnd(BlockEnd e) {
    final msgs = List<MirrorMessage>.from(state.messages);
    final msgIdx = msgs.indexWhere((m) => m.id == e.messageId);
    if (msgIdx < 0) return;

    final blockIdx =
        msgs[msgIdx].blocks.indexWhere((b) => b.id == e.blockId);
    if (blockIdx < 0) return;

    msgs[msgIdx] = msgs[msgIdx].copyWith(
      blocks: () {
        final updated = List<MirrorBlock>.from(msgs[msgIdx].blocks);
        updated[blockIdx] = updated[blockIdx].copyWith(
          status: e.status,
          visibleContent: updated[blockIdx].content,
        );
        return updated;
      },
    );
    state = state.copyWith(messages: msgs, lastSeq: e.envelope.seq);
  }

  void _onMessageEnd(MessageEnd e) {
    final msgs = List<MirrorMessage>.from(state.messages);
    final idx = msgs.indexWhere((m) => m.id == e.messageId);
    if (idx < 0) return;

    msgs[idx] = msgs[idx].copyWith(
      status: e.status,
      blocks: () => msgs[idx].blocks.map((b) {
        if (b.status == MirrorStatus.streaming) {
          return b.copyWith(
            status: e.status,
            visibleContent: b.content,
          );
        }
        b.visibleContent = b.content;
        return b;
      }).toList(),
    );
    state = state.copyWith(messages: msgs, lastSeq: e.envelope.seq);
  }

  void _onServerAck(ServerAck e) {
    state = state.copyWith(isSending: false, lastSeq: e.envelope.seq);
  }

  void _onServerError(ServerError e) {
    state = state.copyWith(
      isSending: false,
      errorMessage: '${e.error.code}: ${e.error.message}',
      lastSeq: e.envelope.seq,
    );
  }

  void _onSessionList(SessionList e) {
    final activeId = e.list.activeSessionId;
    final sessions = e.list.sessions;

    // Mark active session in the list
    final updated = sessions.map((s) {
      return s.copyWith(active: s.sessionId == activeId);
    }).toList();

    state = state.copyWith(
      sessions: updated,
      activeSessionId: activeId,
      lastSeq: e.envelope.seq,
    );
  }

  void _onSessionSwitched(SessionSwitched e) {
    state = state.copyWith(
      messages: const [], // clear messages on session switch
      activeSessionId: e.switched.toSessionId,
      isSwitchingSession: false,
      lastSeq: e.envelope.seq,
    );
    _typewriterTimer?.cancel();
  }

  void _onSlashList(SlashList e) {
    state = state.copyWith(
      slashCommands: e.list.items,
      lastSeq: e.envelope.seq,
    );
  }

  void _onAgentList(AgentList e) {
    final activeId = e.list.activeAgentId;
    final agents = e.list.agents;

    // Mark active agent in the list
    final updated = agents.map((a) {
      return a.copyWith(active: a.id == activeId);
    }).toList();

    state = state.copyWith(
      agents: updated,
      activeAgentId: activeId,
      lastSeq: e.envelope.seq,
    );
  }

  void _onAgentSwitched(AgentSwitched e) {
    state = state.copyWith(
      activeAgentId: e.switched.toAgentId,
      lastSeq: e.envelope.seq,
    );
  }

  /// Typewriter ticker: advance visibleContent toward content
  void _startTypewriter() {
    _typewriterTimer?.cancel();
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      var changed = false;
      final msgs = List<MirrorMessage>.from(state.messages);
      for (var m = 0; m < msgs.length; m++) {
        for (var b = 0; b < msgs[m].blocks.length; b++) {
          final block = msgs[m].blocks[b];
          if (block.visibleContent.length >= block.content.length) continue;
          final remaining = block.content.length - block.visibleContent.length;
          final step = remaining > 100 ? 20 : (remaining > 20 ? 8 : 4);
          final end = (block.visibleContent.length + step)
              .clamp(0, block.content.length);
          msgs[m] = msgs[m].copyWith(
            blocks: () {
              final updated = List<MirrorBlock>.from(msgs[m].blocks);
              updated[b] = block.copyWith(
                visibleContent: block.content.substring(0, end),
              );
              return updated;
            },
          );
          changed = true;
          break; // one block per tick
        }
        if (changed) break;
      }
      if (changed) {
        state = state.copyWith(messages: msgs);
      }
    });
  }

  /// Clear the error message
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  @override
  void dispose() {
    _typewriterTimer?.cancel();
    _messageSub?.cancel();
    _statusSub?.cancel();
    _wsService?.dispose();
    super.dispose();
  }
}

/// The main chat provider
final chatProvider =
    StateNotifierProvider<ChatNotifier, ChatState>((ref) => ChatNotifier());
