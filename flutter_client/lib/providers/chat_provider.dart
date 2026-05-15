import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/session.dart';
import '../models/message.dart';
import '../models/types.dart';
import '../models/slash_command.dart';
import '../models/agent.dart';
import '../services/cdp_service.dart';
import '../services/bridge_client.dart';
import '../services/dom_observer.dart';

class ChatState {
  final List<MirrorMessage> messages;
  final ConnectionStatus connectionStatus;
  final String? sessionId;
  final bool isSending;
  final bool isLoadingSessions;
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
    this.isSending = false,
    this.isLoadingSessions = false,
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
    bool? isSending,
    bool? isLoadingSessions,
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
      isSending: isSending ?? this.isSending,
      isLoadingSessions: isLoadingSessions ?? this.isLoadingSessions,
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

class ChatNotifier extends StateNotifier<ChatState> {
  CdpClient? _cdpClient;
  StreamSubscription? _cdpSub;
  BridgeClient? _bridgeClient;
  StreamSubscription? _bridgeSub;
  Timer? _listSessionsTimeoutTimer;
  Completer<void>? _listSessionsCompleter;

  ChatNotifier() : super(const ChatState());

  /// Connect to bridge (ws://) or discover Copilot via CDP (host:port)
  Future<void> connect(String input) async {
    state = state.copyWith(
      connectionStatus: ConnectionStatus.connecting,
      isLoadingSessions: false,
      isSwitchingSession: false,
      clearError: true,
    );

    // Clean up previous connections
    _bridgeClient?.dispose();
    _bridgeClient = null;
    _bridgeSub?.cancel();
    _bridgeSub = null;
    _cdpClient?.dispose();
    _cdpClient = null;
    _cdpSub?.cancel();
    _cdpSub = null;

    try {
      if (input.startsWith('ws://') || input.startsWith('wss://')) {
        // ── Bridge Protocol (MirrorEnvelope) ──
        _bridgeClient = BridgeClient(url: input);
        _bridgeSub = _bridgeClient!.events.listen(_onBridgeEvent);
        await _bridgeClient!.connect();

        // Wait briefly for server.hello / session.snapshot
        await Future.delayed(const Duration(milliseconds: 500));

        if (_bridgeClient?.isConnected != true) {
          state = state.copyWith(
            connectionStatus: ConnectionStatus.failed,
            errorMessage: 'Bridge 连接失败，请确认 Node.js Bridge (端口 17321) 是否在运行。',
          );
          return;
        }

        state = state.copyWith(
          connectionStatus: ConnectionStatus.connected,
          sessionId: 'bridge',
        );
      } else {
        // ── Direct CDP (auto-discovery) ──
        final parts = input.split(':');
        final host = parts.isNotEmpty ? parts[0] : '127.0.0.1';
        final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 9229 : 9229;

        _cdpClient = CdpClient(host: host, port: port);
        _cdpSub = _cdpClient!.events.listen(_onCdpEvent);

        final wsUrl = await _cdpClient!.connectToCopilot();
        if (wsUrl == null) {
          state = state.copyWith(
            connectionStatus: ConnectionStatus.failed,
            errorMessage: '自动发现 Copilot 目标失败。请尝试在设置中手动粘贴 WebSocket URL，或检查 VS Code 是否已开启远程调试(--remote-debugging-port=$port)。',
          );
          return;
        }

        await _cdpClient!.enableRuntimeAndBinding();
        await _cdpClient!.injectObserver(DomObserver.buildObserverScript());

        state = state.copyWith(
          connectionStatus: ConnectionStatus.connected,
          sessionId: 'cdp_direct',
        );
      }
    } catch (e) {
      state = state.copyWith(
        connectionStatus: ConnectionStatus.failed,
        errorMessage: '连接失败: $e',
      );
    }
  }
  /// Send a user message
  
  void disconnect() {
    _listSessionsTimeoutTimer?.cancel();
    _cdpSub?.cancel();
    _cdpClient?.dispose();
    _cdpClient = null;
    _bridgeSub?.cancel();
    _bridgeClient?.dispose();
    _bridgeClient = null;
    _completeListSessionsRequest();
    state = state.copyWith(connectionStatus: ConnectionStatus.disconnected, isLoadingSessions: false);
  }

  void _onCdpEvent(Map<String, dynamic> msg) {
    if (msg['method'] == 'Runtime.bindingCalled') {
      final params = msg['params'] as Map<String, dynamic>?;
      if (params == null) return;
      if (params['name'] != '__copilotMirrorEmit') return;
      final payload = params['payload'] as String?;
      if (payload == null) return;
      try {
        _onDomEvent(jsonDecode(payload) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  void _onBridgeEvent(BridgeEvent evt) {
    switch (evt.type) {
      case BridgeEventType.hello:
        final cdp = evt.payload['cdp'] as Map<String, dynamic>?;
        if (cdp != null && cdp['connected'] != true) {
          // Bridge 已连接但 CDP 未就绪 — Bridge 会自动重试，无需干扰用户
        }
        break;

      case BridgeEventType.snapshot:
        _onDomSnapshot(evt.payload);
        break;

      case BridgeEventType.message:
        _onDomMessage(evt.payload);
        break;

      case BridgeEventType.delta:
        _onDomDelta(evt.payload);
        break;

      case BridgeEventType.block:
        _onDomBlock(evt.payload);
        break;

      case BridgeEventType.blockUpdate:
        _onDomBlockUpdate(evt.payload);
        break;

      case BridgeEventType.messageEnd:
        _onDomMessageEnd(evt.payload);
        break;

      case BridgeEventType.sessionList:
        _onSessionListData(evt.payload);
        break;

      case BridgeEventType.sessionSwitched:
        final toId = evt.payload['toSessionId'] as String?;
        final fromId = evt.payload['fromSessionId'] as String?;
        if (toId != null && toId != state.activeSessionId) {
          state = state.copyWith(
            messages: const [],
            activeSessionId: toId,
            isSwitchingSession: false,
          );
        }
        break;

      case BridgeEventType.slashList:
        final rawItems = evt.payload['items'] as List<dynamic>? ?? [];
        final commands = rawItems.map((i) {
          final map = i as Map<String, dynamic>;
          return MirrorSlashCommandItem(
            id: map['id'] as String? ?? '',
            label: map['label'] as String? ?? '',
            title: map['title'] as String?,
            description: map['description'] as String?,
            detail: map['detail'] as String?,
            index: map['index'] as int? ?? 0,
            source: map['source'] as String? ?? 'dom',
          );
        }).toList();
        state = state.copyWith(slashCommands: commands);
        break;

      case BridgeEventType.agentList:
        final rawAgents = evt.payload['agents'] as List<dynamic>? ?? [];
        final activeId = evt.payload['activeAgentId'] as String?;
        final agents = rawAgents.map((a) {
          final map = a as Map<String, dynamic>;
          return MirrorAgentItem(
            id: map['id'] as String? ?? '',
            name: map['name'] as String? ?? '',
            description: map['description'] as String?,
            index: map['index'] as int? ?? 0,
            active: map['active'] as bool? ?? false,
            source: map['source'] as String? ?? 'dom',
          );
        }).toList();
        state = state.copyWith(agents: agents, activeAgentId: activeId);
        break;

      case BridgeEventType.agentSwitched:
        final toId = evt.payload['toAgentId'] as String?;
        if (toId != null) {
          state = state.copyWith(activeAgentId: toId);
        }
        break;

      case BridgeEventType.error:
        state = state.copyWith(
          connectionStatus: ConnectionStatus.failed,
          errorMessage: evt.payload['message'] as String? ?? 'Bridge 返回了错误',
        );
        break;
    }
  }

  void _onDomEvent(Map<String, dynamic> event) {
    switch (event['kind'] as String?) {
      case 'snapshot': _onDomSnapshot(event); break;
      case 'message': _onDomMessage(event); break;
      case 'delta': _onDomDelta(event); break;
      case 'block': _onDomBlock(event); break;
      case 'blockUpdate': _onDomBlockUpdate(event); break;
      case 'messageEnd': _onDomMessageEnd(event); break;
    }
  }

  void _onDomSnapshot(Map<String, dynamic> event) {
    final raw = event['messages'] as List<dynamic>?;
    if (raw == null) return;
    state = state.copyWith(
      messages: raw.map((m) => MirrorMessage.fromJson(m as Map<String, dynamic>)).toList(),
      isSending: false,
    );
  }

  void _onDomMessage(Map<String, dynamic> event) {
    final raw = event['message'] as Map<String, dynamic>?;
    if (raw == null) return;
    state = state.copyWith(
      messages: [...state.messages, MirrorMessage.fromJson(raw)],
      isSending: false,
    );
  }

  void _onDomDelta(Map<String, dynamic> event) {
    final messageId = event['messageId'] as String?;
    final blockId = event['blockId'] as String?;
    final chunk = event['chunk'] as String?;
    final offset = event['offset'] as int? ?? 0;
    if (messageId == null || blockId == null || chunk == null) return;
    final msgs = List<MirrorMessage>.from(state.messages);
    final mi = msgs.indexWhere((m) => m.id == messageId);
    if (mi < 0) return;
    final bi = msgs[mi].blocks.indexWhere((b) => b.id == blockId);
    if (bi >= 0) {
      final b = msgs[mi].blocks[bi];
      if (offset <= b.content.length) {
        b.content = b.content.substring(0, offset) + chunk;
        b.visibleContent = b.content;
        b.status = MirrorStatus.streaming;
      }
    } else {
      msgs[mi].blocks.add(MirrorBlock(
        id: blockId, type: _parseBlockType(event['blockType'] as String?),
        status: MirrorStatus.streaming, content: chunk, visibleContent: chunk,
      ));
    }
    state = state.copyWith(messages: msgs);
  }

  void _onDomBlock(Map<String, dynamic> event) {
    final messageId = event['messageId'] as String?;
    final rawBlock = event['block'] as Map<String, dynamic>?;
    if (messageId == null || rawBlock == null) return;
    final msgs = List<MirrorMessage>.from(state.messages);
    final mi = msgs.indexWhere((m) => m.id == messageId);
    if (mi < 0) return;
    final blocks = List<MirrorBlock>.from(msgs[mi].blocks)..add(MirrorBlock.fromJson(rawBlock));
    msgs[mi] = msgs[mi].copyWith(blocks: () => blocks);
    state = state.copyWith(messages: msgs);
  }

  void _onDomBlockUpdate(Map<String, dynamic> event) {
    final messageId = event['messageId'] as String?;
    final blockId = event['blockId'] as String?;
    final patch = event['patch'] as Map<String, dynamic>?;
    if (messageId == null || blockId == null || patch == null) return;
    final msgs = List<MirrorMessage>.from(state.messages);
    final mi = msgs.indexWhere((m) => m.id == messageId);
    if (mi < 0) return;
    final bi = msgs[mi].blocks.indexWhere((b) => b.id == blockId);
    if (bi < 0) return;
    final b = msgs[mi].blocks[bi];
    if (patch.containsKey('content')) {
      b.content = patch['content'] as String;
      b.visibleContent = b.content;
    }
    if (patch.containsKey('status')) {
      b.status = MirrorStatus.fromJson(patch['status'] as String);
    }
    state = state.copyWith(messages: msgs);
  }

  void _onDomMessageEnd(Map<String, dynamic> event) {
    final messageId = event['messageId'] as String?;
    final status = event['status'] as String?;
    if (messageId == null) return;
    final msgs = List<MirrorMessage>.from(state.messages);
    final mi = msgs.indexWhere((m) => m.id == messageId);
    if (mi < 0) return;
    if (status != null) msgs[mi].status = MirrorStatus.fromJson(status);
    for (final b in msgs[mi].blocks) {
      if (b.status == MirrorStatus.streaming) b.status = MirrorStatus.completed;
    }
    state = state.copyWith(messages: msgs, isSending: false);
  }

void sendMessage(String text) {
    if (text.trim().isEmpty || state.isSending) return;
    state = state.copyWith(isSending: true, clearError: true);
    if (_bridgeClient != null) {
      _bridgeClient!.sendMessage(text);
      // Bridge will push session.snapshot after sending, reset isSending there
    } else if (_cdpClient != null) {
      _cdpClient!
          .evaluate(DomObserver.buildSendPromptScript(text, true))
          .catchError((_) => state = state.copyWith(isSending: false));
    }
  }

  void stopGeneration() {
    if (_bridgeClient != null) {
      _bridgeClient!.stopGeneration();
    } else {
      _cdpClient?.evaluate(DomObserver.buildStopGenerationScript());
    }
  }

  Future<void> listSessions({Duration timeout = const Duration(seconds: 2)}) async {
    if (state.connectionStatus != ConnectionStatus.connected) return;
    if (_bridgeClient != null) {
      state = state.copyWith(isLoadingSessions: true);
      _bridgeClient!.listSessions();
      return;
    }
    if (_cdpClient == null) return;
    if (_listSessionsCompleter != null && !_listSessionsCompleter!.isCompleted) {
      return _listSessionsCompleter!.future;
    }
    final completer = Completer<void>();
    _listSessionsCompleter = completer;
    state = state.copyWith(isLoadingSessions: true);
    _listSessionsTimeoutTimer = Timer(timeout, () => _completeListSessionsRequest());
    try {
      await _cdpClient!.evaluate(DomObserver.buildOpenSessionSidebarScript());
      await Future.delayed(const Duration(milliseconds: 200));
      final result = await _cdpClient!.evaluate(DomObserver.buildSessionListScript());
      if (result is String) {
        final parsed = jsonDecode(result) as Map<String, dynamic>;
        if (parsed['ok'] == true && parsed['result'] != null) {
          _onSessionListData(parsed['result'] as Map<String, dynamic>);
        }
      }
    } catch (_) {}
    _completeListSessionsRequest();
  }

  void _onSessionListData(Map<String, dynamic> data) {
    final rawSessions = data['sessions'] as List<dynamic>? ?? [];
    final activeId = data['activeSessionId'] as String?;
    final sessions = rawSessions.map((s) {
      final map = s as Map<String, dynamic>;
      return MirrorChatSession(
        sessionId: map['sessionId'] as String? ?? '',
        title: map['title'] as String? ?? '',
        index: map['index'] as int? ?? 0,
        active: map['active'] as bool? ?? false,
        updatedAt: map['updatedAt'] as String?,
        source: map['source'] as String? ?? 'dom',
      );
    }).toList();
    if (activeId != null && activeId != state.activeSessionId && state.activeSessionId != null) {
      state = state.copyWith(messages: const [], activeSessionId: activeId, sessions: sessions, isLoadingSessions: false, isSwitchingSession: false);
    } else {
      state = state.copyWith(sessions: sessions, activeSessionId: activeId ?? state.activeSessionId, isLoadingSessions: false);
    }
  }

  void switchSession(String sessionId, {int? index, String? title}) {
    if (_bridgeClient != null) {
      state = state.copyWith(isSwitchingSession: true);
      _bridgeClient!.switchSession(sessionId, index: index, title: title);
      return;
    }
    if (_cdpClient == null) return;
    state = state.copyWith(isSwitchingSession: true);
    if (index != null) _cdpClient!.evaluate(DomObserver.buildSwitchSessionScript(index));
    _scheduleSessionListRefresh();
  }

  void newSession() {
    if (_bridgeClient != null) {
      _bridgeClient!.newSession();
      return;
    }
    if (_cdpClient == null) return;
    _cdpClient!.evaluate(DomObserver.buildNewSessionScript());
    _scheduleSessionListRefresh();
  }

  void _scheduleSessionListRefresh() {
    Future.delayed(const Duration(milliseconds: 600), () => listSessions());
  }

  void listSlashCommands({String? query}) {
    if (_bridgeClient != null) {
      _bridgeClient!.listSlashCommands(query: query);
      return;
    }
    if (_cdpClient == null) return;
    _cdpClient!.evaluate(DomObserver.buildSlashListScript(query));
    Future.delayed(const Duration(milliseconds: 300), () {
      _cdpClient!.evaluate(DomObserver.buildScanSuggestWidgetScript()).then((result) {
        if (result is String) {
          try {
            final parsed = jsonDecode(result) as Map<String, dynamic>;
            if (parsed['ok'] == true && parsed['result'] != null) {
              final items = (parsed['result']['items'] as List<dynamic>?) ?? [];
              final commands = items.map((i) {
                final map = i as Map<String, dynamic>;
                return MirrorSlashCommandItem(id: map['id'] as String? ?? '', label: map['label'] as String? ?? '', title: map['title'] as String? ?? '', description: map['description'] as String?, detail: map['detail'] as String?, index: map['index'] as int? ?? 0, source: map['source'] as String? ?? 'dom');
              }).toList();
              state = state.copyWith(slashCommands: commands);
            }
          } catch (_) {}
        }
      });
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      _cdpClient?.evaluate(DomObserver.buildRestoreInputScript());
    });
  }

  void applySlashCommand(int index, {bool insertOnly = false}) {
    if (_bridgeClient != null) {
      _bridgeClient!.applySlashCommand(index, insertOnly: insertOnly);
      return;
    }
    if (_cdpClient == null) return;
    _cdpClient!.evaluate(DomObserver.buildApplySlashScript(index, insertOnly));
  }

  void listAgents() {
    if (_bridgeClient != null) {
      _bridgeClient!.listAgents();
      return;
    }
    if (_cdpClient == null) return;
    _cdpClient!.evaluate(DomObserver.buildAgentListScript());
    Future.delayed(const Duration(milliseconds: 350), () {
      _cdpClient!.evaluate(DomObserver.buildScanAgentListScript()).then((result) {
        if (result is String) {
          try {
            final parsed = jsonDecode(result) as Map<String, dynamic>;
            if (parsed['ok'] == true && parsed['result'] != null) {
              final data = parsed['result'] as Map<String, dynamic>;
              final rawAgents = data['agents'] as List<dynamic>? ?? [];
              final activeId = data['activeAgentId'] as String?;
              final agents = rawAgents.map((a) {
                final map = a as Map<String, dynamic>;
                return MirrorAgentItem(id: map['id'] as String? ?? '', name: map['name'] as String? ?? '', description: map['description'] as String?, index: map['index'] as int? ?? 0, active: map['active'] as bool? ?? false, source: map['source'] as String? ?? 'dom');
              }).toList();
              state = state.copyWith(agents: agents, activeAgentId: activeId);
            }
          } catch (_) {}
        }
      });
    });
  }

  void switchAgent(String? agentId, {int? index, String? name}) {
    if (_bridgeClient != null) {
      _bridgeClient!.switchAgent(agentId, index: index, name: name);
      return;
    }
    if (_cdpClient == null) return;
    if (index != null) _cdpClient!.evaluate(DomObserver.buildSwitchAgentScript(index));
  }

  void refresh() {
    if (_bridgeClient != null) {
      state = state.copyWith(isLoadingSessions: true);
      _bridgeClient!.refresh();
      return;
    }
    if (_cdpClient == null) return;
    state = state.copyWith(isLoadingSessions: true);
    _cdpClient!.evaluate(DomObserver.buildSnapshotScript()).then((result) {
      if (result is String) {
        try {
          final parsed = jsonDecode(result) as Map<String, dynamic>;
          if (parsed['ok'] == true && parsed['result'] != null) {
            final data = parsed['result'] as Map<String, dynamic>;
            final rawMessages = data['messages'] as List<dynamic>? ?? [];
            final messages = rawMessages.map((m) => MirrorMessage.fromJson(m as Map<String, dynamic>)).toList();
            state = state.copyWith(messages: messages, isLoadingSessions: false);
          }
        } catch (_) {}
      }
    }).catchError((_){state=state.copyWith(isLoadingSessions:false);});
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  @override
  void dispose() {
    _listSessionsTimeoutTimer?.cancel();
    _cdpSub?.cancel();
    _cdpClient?.dispose();
    _bridgeSub?.cancel();
    _bridgeClient?.dispose();
    super.dispose();
  }

  void _completeListSessionsRequest() {
    _listSessionsTimeoutTimer?.cancel();
    _listSessionsTimeoutTimer = null;
    final completer = _listSessionsCompleter;
    _listSessionsCompleter = null;
    if (!(completer?.isCompleted ?? true)) completer!.complete();
    state = state.copyWith(isLoadingSessions: false);
  }

  static BlockType _parseBlockType(String? type) {
    switch (type) {
      case 'thinking': return BlockType.thinking;
      case 'code_block': return BlockType.codeBlock;
      case 'tool_call': return BlockType.toolCall;
      case 'artifact': return BlockType.artifact;
      default: return BlockType.text;
    }
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier();
});