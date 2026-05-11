import 'types.dart';
import 'session.dart';

/// Copilot Mirror protocol envelope (v1).
/// Top-level object for every WebSocket message.
class MirrorEnvelope {
  final int v;
  final int seq;
  final String type;
  final String? sessionId;
  final String? requestId;
  final String? timestamp;
  final Map<String, dynamic> payload;

  const MirrorEnvelope({
    required this.v,
    required this.seq,
    required this.type,
    this.sessionId,
    this.requestId,
    this.timestamp,
    required this.payload,
  });

  factory MirrorEnvelope.fromJson(Map<String, dynamic> json) {
    return MirrorEnvelope(
      v: json['v'] as int? ?? 1,
      seq: json['seq'] as int? ?? 0,
      type: json['type'] as String? ?? '',
      sessionId: json['sessionId'] as String?,
      requestId: json['requestId'] as String?,
      timestamp: json['timestamp'] as String?,
      payload: json['payload'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
        'v': v,
        'seq': seq,
        'type': type,
        if (sessionId != null) 'sessionId': sessionId,
        if (requestId != null) 'requestId': requestId,
        if (timestamp != null) 'timestamp': timestamp,
        'payload': payload,
      };
}

/// Payload for server.hello
class ServerHelloPayload {
  final String serverId;
  final int protocolVersion;
  final Map<String, dynamic> cdp;
  final Map<String, dynamic> session;
  final Map<String, dynamic> capabilities;

  const ServerHelloPayload({
    required this.serverId,
    required this.protocolVersion,
    required this.cdp,
    required this.session,
    required this.capabilities,
  });

  factory ServerHelloPayload.fromJson(Map<String, dynamic> json) =>
      ServerHelloPayload(
        serverId: json['serverId'] as String? ?? '',
        protocolVersion: json['protocolVersion'] as int? ?? 1,
        cdp: json['cdp'] as Map<String, dynamic>? ?? {},
        session: json['session'] as Map<String, dynamic>? ?? {},
        capabilities: json['capabilities'] as Map<String, dynamic>? ?? {},
      );
}

/// Payload for session.snapshot
class SessionSnapshotPayload {
  final String mode;
  final Map<String, dynamic> cursor;
  final Map<String, dynamic> session;
  final List<Map<String, dynamic>> messages;

  const SessionSnapshotPayload({
    required this.mode,
    required this.cursor,
    required this.session,
    required this.messages,
  });

  factory SessionSnapshotPayload.fromJson(Map<String, dynamic> json) =>
      SessionSnapshotPayload(
        mode: json['mode'] as String? ?? 'full',
        cursor: json['cursor'] as Map<String, dynamic>? ?? {},
        session: json['session'] as Map<String, dynamic>? ?? {},
        messages: (json['messages'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [],
      );
}

/// Payload for block.delta (streaming content)
class BlockDeltaPayload {
  final String messageId;
  final String blockId;
  final BlockType blockType;
  final DeltaOp op;
  final int offset;
  final String chunk;
  final ContentFormat format;
  final bool done;

  const BlockDeltaPayload({
    required this.messageId,
    required this.blockId,
    required this.blockType,
    required this.op,
    required this.offset,
    required this.chunk,
    required this.format,
    required this.done,
  });

  factory BlockDeltaPayload.fromJson(Map<String, dynamic> json) =>
      BlockDeltaPayload(
        messageId: json['messageId'] as String? ?? '',
        blockId: json['blockId'] as String? ?? '',
        blockType: BlockType.fromJson(json['blockType'] as String? ?? 'text'),
        op: DeltaOp.fromJson(json['op'] as String? ?? 'append'),
        offset: json['offset'] as int? ?? 0,
        chunk: json['chunk'] as String? ?? '',
        format:
            ContentFormat.fromJson(json['format'] as String? ?? 'markdown'),
        done: json['done'] as bool? ?? false,
      );
}

/// Payload for server.status
class ServerStatusPayload {
  final bool cdpConnected;
  final int wsClients;
  final String? message;

  const ServerStatusPayload({
    required this.cdpConnected,
    required this.wsClients,
    this.message,
  });

  factory ServerStatusPayload.fromJson(Map<String, dynamic> json) =>
      ServerStatusPayload(
        cdpConnected: json['cdpConnected'] as bool? ?? false,
        wsClients: json['wsClients'] as int? ?? 0,
        message: json['message'] as String?,
      );
}

/// Payload for server.ack
class ServerAckPayload {
  final bool ok;
  final String command;
  final String? acceptedAt;

  const ServerAckPayload({
    required this.ok,
    required this.command,
    this.acceptedAt,
  });

  factory ServerAckPayload.fromJson(Map<String, dynamic> json) =>
      ServerAckPayload(
        ok: json['ok'] as bool? ?? false,
        command: json['command'] as String? ?? '',
        acceptedAt: json['acceptedAt'] as String?,
      );
}

/// Payload for server.error
class ServerErrorPayload {
  final String code;
  final String message;
  final bool retryable;

  const ServerErrorPayload({
    required this.code,
    required this.message,
    required this.retryable,
  });

  factory ServerErrorPayload.fromJson(Map<String, dynamic> json) =>
      ServerErrorPayload(
        code: json['code'] as String? ?? '',
        message: json['message'] as String? ?? '',
        retryable: json['retryable'] as bool? ?? false,
      );
}

/// Payload for session.list
class SessionListPayload {
  final List<MirrorChatSession> sessions;
  final String? activeSessionId;

  const SessionListPayload({
    required this.sessions,
    this.activeSessionId,
  });

  factory SessionListPayload.fromJson(Map<String, dynamic> json) =>
      SessionListPayload(
        sessions: (json['sessions'] as List<dynamic>?)
                ?.map((s) =>
                    MirrorChatSession.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
        activeSessionId: json['activeSessionId'] as String?,
      );
}

/// Payload for session.switched
class SessionSwitchedPayload {
  final String? fromSessionId;
  final String toSessionId;
  final String reason;

  const SessionSwitchedPayload({
    this.fromSessionId,
    required this.toSessionId,
    required this.reason,
  });

  factory SessionSwitchedPayload.fromJson(Map<String, dynamic> json) =>
      SessionSwitchedPayload(
        fromSessionId: json['fromSessionId'] as String?,
        toSessionId: json['toSessionId'] as String? ?? '',
        reason: json['reason'] as String? ?? 'user',
      );
}
