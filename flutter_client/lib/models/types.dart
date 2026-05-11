/// Shared enum types matching the Copilot Mirror protocol (Phase 1)

/// Block content type
enum BlockType {
  text,
  thinking,
  codeBlock,
  toolCall,
  artifact;

  static BlockType fromJson(String value) {
    switch (value) {
      case 'text':
        return BlockType.text;
      case 'thinking':
        return BlockType.thinking;
      case 'code_block':
        return BlockType.codeBlock;
      case 'tool_call':
        return BlockType.toolCall;
      case 'artifact':
        return BlockType.artifact;
      default:
        return BlockType.text;
    }
  }

  String toJson() => name.replaceAllMapped(
      RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}');
}

/// Message role
enum MessageRole {
  user,
  assistant,
  system,
  tool;

  static MessageRole fromJson(String value) =>
      MessageRole.values.firstWhere((e) => e.name == value,
          orElse: () => MessageRole.assistant);

  String toJson() => name;
}

/// Lifecycle status for messages and blocks
enum MirrorStatus {
  pending,
  streaming,
  completed,
  failed,
  cancelled;

  static MirrorStatus fromJson(String value) =>
      MirrorStatus.values.firstWhere((e) => e.name == value,
          orElse: () => MirrorStatus.pending);

  String toJson() => name;
}

/// Delta operation type
enum DeltaOp {
  append,
  replace,
  patch;

  static DeltaOp fromJson(String value) =>
      DeltaOp.values.firstWhere((e) => e.name == value,
          orElse: () => DeltaOp.append);

  String toJson() => name;
}

/// Content format
enum ContentFormat {
  markdown,
  plain,
  json,
  diff;

  static ContentFormat fromJson(String value) =>
      ContentFormat.values.firstWhere((e) => e.name == value,
          orElse: () => ContentFormat.markdown);

  String toJson() => name;
}

/// Tool call state
enum ToolState {
  queued,
  running,
  succeeded,
  failed,
  cancelled;

  static ToolState fromJson(String value) =>
      ToolState.values.firstWhere((e) => e.name == value,
          orElse: () => ToolState.queued);

  String toJson() => name;
}

/// Artifact sub-type
enum ArtifactType {
  file,
  image,
  html,
  markdown,
  diff,
  terminal;

  static ArtifactType fromJson(String value) =>
      ArtifactType.values.firstWhere((e) => e.name == value,
          orElse: () => ArtifactType.file);

  String toJson() => name;
}

/// WebSocket connection status
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed;

  String get label {
    switch (this) {
      case ConnectionStatus.disconnected:
        return 'Disconnected';
      case ConnectionStatus.connecting:
        return 'Connecting…';
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.reconnecting:
        return 'Reconnecting…';
      case ConnectionStatus.failed:
        return 'Connection Failed';
    }
  }
}
