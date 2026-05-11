/// An agent participant item from VS Code
class MirrorAgentItem {
  final String id;
  final String name;
  final String? description;
  final int index;
  final bool active;
  final String source;

  const MirrorAgentItem({
    required this.id,
    required this.name,
    this.description,
    required this.index,
    this.active = false,
    this.source = 'dom',
  });

  factory MirrorAgentItem.fromJson(Map<String, dynamic> json) {
    return MirrorAgentItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      index: json['index'] as int? ?? 0,
      active: json['active'] as bool? ?? false,
      source: json['source'] as String? ?? 'dom',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        'index': index,
        'active': active,
        'source': source,
      };

  MirrorAgentItem copyWith({bool? active}) {
    return MirrorAgentItem(
      id: id,
      name: name,
      description: description,
      index: index,
      active: active ?? this.active,
      source: source,
    );
  }
}

/// Payload for agent.list
class AgentListPayload {
  final List<MirrorAgentItem> agents;
  final String? activeAgentId;

  const AgentListPayload({required this.agents, this.activeAgentId});

  factory AgentListPayload.fromJson(Map<String, dynamic> json) =>
      AgentListPayload(
        agents: (json['agents'] as List<dynamic>?)
                ?.map(
                    (a) => MirrorAgentItem.fromJson(a as Map<String, dynamic>))
                .toList() ??
            [],
        activeAgentId: json['activeAgentId'] as String?,
      );
}

/// Payload for agent.switched
class AgentSwitchedPayload {
  final String? fromAgentId;
  final String toAgentId;
  final String reason;

  const AgentSwitchedPayload({
    this.fromAgentId,
    required this.toAgentId,
    required this.reason,
  });

  factory AgentSwitchedPayload.fromJson(Map<String, dynamic> json) =>
      AgentSwitchedPayload(
        fromAgentId: json['fromAgentId'] as String?,
        toAgentId: json['toAgentId'] as String? ?? '',
        reason: json['reason'] as String? ?? 'client',
      );
}
