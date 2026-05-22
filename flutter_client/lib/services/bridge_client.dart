import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Bridge event types mapped from MirrorEnvelope protocol
enum BridgeEventType {
  hello,
  snapshot,
  message,
  delta,
  block,
  blockUpdate,
  messageEnd,
  sessionList,
  sessionSwitched,
  slashList,
  agentList,
  agentSwitched,
  inputContext,
  error,
}

/// Parsed bridge event
class BridgeEvent {
  final BridgeEventType type;
  final Map<String, dynamic> payload;
  final String? requestId;
  final String? sessionId;

  BridgeEvent({
    required this.type,
    required this.payload,
    this.requestId,
    this.sessionId,
  });
}

/// Bridge client that communicates with the Node.js Bridge
/// using the MirrorEnvelope protocol (v1).
class BridgeClient {
  final String url;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final _eventController = StreamController<BridgeEvent>.broadcast();
  Stream<BridgeEvent> get events => _eventController.stream;
  bool _connected = false;
  int _seq = 0;

  BridgeClient({required this.url});

  bool get isConnected => _connected;

  /// Connect to bridge WebSocket and send client.hello
  Future<void> connect() async {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    await _channel!.ready;
    _connected = true;

    _sub = _channel!.stream.listen(
      (data) {
        try {
          final raw = jsonDecode(data as String) as Map<String, dynamic>;
          _handleEnvelope(raw);
        } catch (_) {}
      },
      onError: (_) => _onDisconnect(),
      onDone: () => _onDisconnect(),
    );

    // Send client.hello to trigger snapshot from bridge
    _send('client.hello', {
      'clientName': 'copilot_mirror_flutter',
      'protocolVersion': 1,
      'capabilities': {
        'acceptDelta': true,
        'acceptThinking': true,
        'acceptArtifacts': true,
      },
    });
  }

  void _handleEnvelope(Map<String, dynamic> raw) {
    final type = raw['type'] as String? ?? '';
    final payload = raw['payload'] as Map<String, dynamic>? ?? {};
    final requestId = raw['requestId'] as String?;
    final sessionId = raw['sessionId'] as String?;

    BridgeEventType? eventType;
    switch (type) {
      case 'server.hello':
        eventType = BridgeEventType.hello;
        break;
      case 'session.snapshot':
        eventType = BridgeEventType.snapshot;
        break;
      case 'session.message':
        eventType = BridgeEventType.message;
        break;
      case 'session.delta':
        eventType = BridgeEventType.delta;
        break;
      case 'input.context':
        eventType = BridgeEventType.inputContext;
        break;
      case 'session.block':
        eventType = BridgeEventType.block;
        break;
      case 'session.blockUpdate':
        eventType = BridgeEventType.blockUpdate;
        break;
      case 'session.messageEnd':
        eventType = BridgeEventType.messageEnd;
        break;
      case 'session.list':
        eventType = BridgeEventType.sessionList;
        break;
      case 'session.switched':
        eventType = BridgeEventType.sessionSwitched;
        break;
      case 'slot.list':
        eventType = BridgeEventType.slashList;
        break;
      case 'agent.list':
        eventType = BridgeEventType.agentList;
        break;
      case 'agent.switched':
        eventType = BridgeEventType.agentSwitched;
        break;
      case 'server.error':
        eventType = BridgeEventType.error;
        break;
    }

    if (eventType != null) {
      _eventController.add(BridgeEvent(
        type: eventType,
        payload: payload,
        requestId: requestId,
        sessionId: sessionId,
      ));
    }
  }

  void _send(String type, Map<String, dynamic> payload, {String? requestId}) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({
      'v': 1,
      'seq': ++_seq,
      'type': type,
      if (requestId != null) 'requestId': requestId,
      'timestamp': DateTime.now().toIso8601String(),
      'payload': payload,
    }));
  }

  // ── Commands ─────────────────

  void sendMessage(String text, {bool submit = true}) {
    _send('client.command.sendMessage', {
      'text': text,
      'options': {'submit': submit},
    });
  }

  void stopGeneration() {
    _send('client.command.stopGeneration', {});
  }

  void listSessions() {
    _send('client.command.listSessions', {});
  }

  void switchSession(String sessionId, {int? index, String? title}) {
    final payload = <String, dynamic>{};
    if (sessionId.isNotEmpty) payload['sessionId'] = sessionId;
    if (index != null) payload['index'] = index;
    if (title != null) payload['title'] = title;
    _send('client.command.switchSession', payload);
  }

  void newSession() {
    _send('client.command.newSession', {});
  }

  void listSlashCommands({String? query}) {
    final payload = <String, dynamic>{};
    if (query != null) payload['query'] = query;
    _send('client.command.listSlashCommands', payload);
  }

  void applySlashCommand(int index, {bool insertOnly = false}) {
    _send('client.command.applySlashCommand', {
      'index': index,
      'insertOnly': insertOnly,
    });
  }

  void listAgents() {
    _send('client.command.listAgents', {});
  }

  void switchAgent(String? agentId, {int? index, String? name}) {
    final payload = <String, dynamic>{};
    if (agentId != null) payload['agentId'] = agentId;
    if (index != null) payload['index'] = index;
    if (name != null) payload['name'] = name;
    _send('client.command.switchAgent', payload);
  }

  void refresh() {
    _send('client.command.refresh', {});
  }

  void focusInput() {
    _send('client.command.focusInput', {});
  }

  /// Send a raw envelope (used for custom or future commands)
  void sendRaw(String type, Map<String, dynamic> payload, {String? requestId}) {
    _send(type, payload, requestId: requestId);
  }

  // ── Lifecycle ──────────────────

  void disconnect() {
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _connected = false;
  }

  void dispose() {
    disconnect();
    _eventController.close();
  }

  void _onDisconnect() {
    _connected = false;
  }
}