/// A single chat session item shown in the sidebar session list
class MirrorChatSession {
  final String sessionId;
  final String title;
  final int index;
  final bool active;
  final String? updatedAt;
  final String? preview;
  final String source;

  const MirrorChatSession({
    required this.sessionId,
    required this.title,
    required this.index,
    this.active = false,
    this.updatedAt,
    this.preview,
    this.source = 'dom',
  });

  factory MirrorChatSession.fromJson(Map<String, dynamic> json) {
    return MirrorChatSession(
      sessionId: json['sessionId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      index: json['index'] as int? ?? 0,
      active: json['active'] as bool? ?? false,
      updatedAt: json['updatedAt'] as String?,
      preview: json['preview'] as String?,
      source: json['source'] as String? ?? 'dom',
    );
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'title': title,
        'index': index,
        'active': active,
        if (updatedAt != null) 'updatedAt': updatedAt,
        if (preview != null) 'preview': preview,
        'source': source,
      };

  MirrorChatSession copyWith({bool? active}) {
    return MirrorChatSession(
      sessionId: sessionId,
      title: title,
      index: index,
      active: active ?? this.active,
      updatedAt: updatedAt,
      preview: preview,
      source: source,
    );
  }
}
