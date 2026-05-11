/// A slash command item from VS Code Copilot Chat suggest widget
class MirrorSlashCommandItem {
  final String id;
  final String label;
  final String? title;
  final String? description;
  final String? detail;
  final int index;
  final String source;

  const MirrorSlashCommandItem({
    required this.id,
    required this.label,
    this.title,
    this.description,
    this.detail,
    required this.index,
    this.source = 'dom',
  });

  factory MirrorSlashCommandItem.fromJson(Map<String, dynamic> json) {
    return MirrorSlashCommandItem(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      title: json['title'] as String?,
      description: json['description'] as String?,
      detail: json['detail'] as String?,
      index: json['index'] as int? ?? 0,
      source: json['source'] as String? ?? 'dom',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (detail != null) 'detail': detail,
        'index': index,
        'source': source,
      };
}

/// Payload for slash.list
class SlashListPayload {
  final List<MirrorSlashCommandItem> items;
  final String? query;

  const SlashListPayload({required this.items, this.query});

  factory SlashListPayload.fromJson(Map<String, dynamic> json) =>
      SlashListPayload(
        items: (json['items'] as List<dynamic>?)
                ?.map((s) =>
                    MirrorSlashCommandItem.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
        query: json['query'] as String?,
      );
}
