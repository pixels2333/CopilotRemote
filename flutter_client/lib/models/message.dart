import 'types.dart';

/// A single block within a message (text, thinking, code, tool_call, artifact)
class MirrorBlock {
  final String id;
  final BlockType type;
  MirrorStatus status;
  String content;
  String visibleContent;
  String? language;
  String? fileName;
  ToolState? toolState;
  String? artifactId;
  Map<String, dynamic>? metadata;

  MirrorBlock({
    required this.id,
    required this.type,
    this.status = MirrorStatus.pending,
    this.content = '',
    this.visibleContent = '',
    this.language,
    this.fileName,
    this.toolState,
    this.artifactId,
    this.metadata,
  });

  factory MirrorBlock.fromJson(Map<String, dynamic> json) {
    return MirrorBlock(
      id: json['id'] as String? ?? '',
      type: BlockType.fromJson(json['type'] as String? ?? 'text'),
      status:
          MirrorStatus.fromJson(json['status'] as String? ?? 'pending'),
      content: json['content'] as String? ?? '',
      visibleContent: json['content'] as String? ?? '',
      language: json['language'] as String?,
      fileName: json['fileName'] as String?,
      toolState: json['toolState'] != null
          ? ToolState.fromJson(json['toolState'] as String)
          : null,
      artifactId: json['artifactId'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  MirrorBlock copyWith({
    String? id,
    BlockType? type,
    MirrorStatus? status,
    String? content,
    String? visibleContent,
    String? language,
    String? fileName,
    ToolState? toolState,
    String? artifactId,
    Map<String, dynamic>? metadata,
  }) {
    return MirrorBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      status: status ?? this.status,
      content: content ?? this.content,
      visibleContent: visibleContent ?? this.visibleContent,
      language: language ?? this.language,
      fileName: fileName ?? this.fileName,
      toolState: toolState ?? this.toolState,
      artifactId: artifactId ?? this.artifactId,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// A single chat message consisting of ordered blocks
class MirrorMessage {
  final String id;
  final MessageRole role;
  MirrorStatus status;
  final String createdAt;
  final String updatedAt;
  List<MirrorBlock> blocks;
  Map<String, dynamic>? metadata;

  MirrorMessage({
    required this.id,
    required this.role,
    this.status = MirrorStatus.pending,
    String? createdAt,
    String? updatedAt,
    List<MirrorBlock>? blocks,
    this.metadata,
  })  : createdAt = createdAt ?? DateTime.now().toIso8601String(),
        updatedAt = updatedAt ?? DateTime.now().toIso8601String(),
        blocks = blocks ?? [];

  factory MirrorMessage.fromJson(Map<String, dynamic> json) {
    return MirrorMessage(
      id: json['id'] as String? ?? '',
      role: MessageRole.fromJson(json['role'] as String? ?? 'assistant'),
      status:
          MirrorStatus.fromJson(json['status'] as String? ?? 'pending'),
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
      blocks: (json['blocks'] as List<dynamic>?)
              ?.map(
                  (b) => MirrorBlock.fromJson(b as Map<String, dynamic>))
              .toList() ??
          [],
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  MirrorMessage copyWith({
    String? id,
    MessageRole? role,
    MirrorStatus? status,
    String? createdAt,
    String? updatedAt,
    List<MirrorBlock>? Function()? blocks,
    Map<String, dynamic>? metadata,
  }) {
    return MirrorMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      blocks: blocks != null ? blocks() : List.from(this.blocks),
      metadata: metadata ?? this.metadata,
    );
  }
}
