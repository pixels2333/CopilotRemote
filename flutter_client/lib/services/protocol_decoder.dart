import '../models/envelope.dart';
import '../models/types.dart';
import '../models/slash_command.dart';
import '../models/agent.dart';

/// Result of decoding a single server event
sealed class ProtocolEvent {
  final MirrorEnvelope envelope;
  const ProtocolEvent(this.envelope);
}

/// Server hello (connection established)
class ServerHello extends ProtocolEvent {
  final ServerHelloPayload hello;
  const ServerHello(super.envelope, this.hello);
}

/// Session snapshot (full state)
class SessionSnapshot extends ProtocolEvent {
  final SessionSnapshotPayload snapshot;
  const SessionSnapshot(super.envelope, this.snapshot);
}

/// Message start
class MessageStart extends ProtocolEvent {
  final Map<String, dynamic> message;
  const MessageStart(super.envelope, this.message);
}

/// Block start
class BlockStart extends ProtocolEvent {
  final String messageId;
  final Map<String, dynamic> block;
  const BlockStart(super.envelope, this.messageId, this.block);
}

/// Block delta (streaming content chunk)
class BlockDelta extends ProtocolEvent {
  final BlockDeltaPayload delta;
  const BlockDelta(super.envelope, this.delta);
}

/// Block update (structured field merge)
class BlockUpdate extends ProtocolEvent {
  final String messageId;
  final String blockId;
  final Map<String, dynamic> patch;
  const BlockUpdate(super.envelope, this.messageId, this.blockId, this.patch);
}

/// Block end
class BlockEnd extends ProtocolEvent {
  final String messageId;
  final String blockId;
  final MirrorStatus status;
  final int? finalLength;
  const BlockEnd(
    super.envelope,
    this.messageId,
    this.blockId,
    this.status,
    this.finalLength,
  );
}

/// Message end
class MessageEnd extends ProtocolEvent {
  final String messageId;
  final MirrorStatus status;
  const MessageEnd(super.envelope, this.messageId, this.status);
}

/// Server acknowledgment
class ServerAck extends ProtocolEvent {
  final ServerAckPayload ack;
  const ServerAck(super.envelope, this.ack);
}

/// Server error
class ServerError extends ProtocolEvent {
  final ServerErrorPayload error;
  const ServerError(super.envelope, this.error);
}

/// Server status update
class ServerStatus extends ProtocolEvent {
  final Map<String, dynamic> status;
  const ServerStatus(super.envelope, this.status);
}

/// Session list (all available sessions)
class SessionList extends ProtocolEvent {
  final SessionListPayload list;
  const SessionList(super.envelope, this.list);
}

/// Session switched (active session changed)
class SessionSwitched extends ProtocolEvent {
  final SessionSwitchedPayload switched;
  const SessionSwitched(super.envelope, this.switched);
}

/// Slash list (available slash commands)
class SlashList extends ProtocolEvent {
  final SlashListPayload list;
  const SlashList(super.envelope, this.list);
}

/// Agent list (available agents)
class AgentList extends ProtocolEvent {
  final AgentListPayload list;
  const AgentList(super.envelope, this.list);
}

/// Agent switched (active agent changed)
class AgentSwitched extends ProtocolEvent {
  final AgentSwitchedPayload switched;
  const AgentSwitched(super.envelope, this.switched);
}

/// Unknown event type
class UnknownEvent extends ProtocolEvent {
  const UnknownEvent(super.envelope);
}

/// Decodes raw MirrorEnvelope JSON into typed ProtocolEvent objects.
ProtocolEvent decodeProtocolEvent(Map<String, dynamic> raw) {
  final envelope = MirrorEnvelope.fromJson(raw);

  switch (envelope.type) {
    case 'server.hello':
      return ServerHello(
          envelope, ServerHelloPayload.fromJson(envelope.payload));

    case 'session.snapshot':
      return SessionSnapshot(
          envelope, SessionSnapshotPayload.fromJson(envelope.payload));

    case 'message.start':
      return MessageStart(envelope, envelope.payload);

    case 'block.start':
      return BlockStart(
        envelope,
        envelope.payload['messageId'] as String? ?? '',
        envelope.payload['block'] as Map<String, dynamic>? ?? {},
      );

    case 'block.delta':
      return BlockDelta(
          envelope, BlockDeltaPayload.fromJson(envelope.payload));

    case 'block.update':
      return BlockUpdate(
        envelope,
        envelope.payload['messageId'] as String? ?? '',
        envelope.payload['blockId'] as String? ?? '',
        envelope.payload['patch'] as Map<String, dynamic>? ?? {},
      );

    case 'block.end':
      return BlockEnd(
        envelope,
        envelope.payload['messageId'] as String? ?? '',
        envelope.payload['blockId'] as String? ?? '',
        MirrorStatus.fromJson(
            envelope.payload['status'] as String? ?? 'completed'),
        envelope.payload['finalLength'] as int?,
      );

    case 'message.end':
      return MessageEnd(
        envelope,
        envelope.payload['messageId'] as String? ?? '',
        MirrorStatus.fromJson(
            envelope.payload['status'] as String? ?? 'completed'),
      );

    case 'server.ack':
      return ServerAck(envelope, ServerAckPayload.fromJson(envelope.payload));

    case 'server.error':
      return ServerError(
          envelope, ServerErrorPayload.fromJson(envelope.payload));

    case 'server.status':
      return ServerStatus(envelope, envelope.payload);

    case 'session.list':
      return SessionList(
          envelope, SessionListPayload.fromJson(envelope.payload));

    case 'session.switched':
      return SessionSwitched(
          envelope, SessionSwitchedPayload.fromJson(envelope.payload));

    case 'slash.list':
      return SlashList(
          envelope, SlashListPayload.fromJson(envelope.payload));

    case 'agent.list':
      return AgentList(
          envelope, AgentListPayload.fromJson(envelope.payload));

    case 'agent.switched':
      return AgentSwitched(
          envelope, AgentSwitchedPayload.fromJson(envelope.payload));

    default:
      return UnknownEvent(envelope);
  }
}
