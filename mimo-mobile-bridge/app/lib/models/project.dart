/// 项目模型
///
/// 对应 MiMoCode 中的 Project，表示电脑端已打开的项目
class Project {
  /// 项目 ID
  final String id;

  /// 项目名称
  final String name;

  /// 项目目录路径
  final String directory;

  /// Git 分支（可选）
  final String? branch;

  /// 项目下的会话数量
  final int sessionCount;

  /// 最后活跃时间（毫秒时间戳）
  final int lastActiveAt;

  /// 是否为当前活动项目
  final bool isCurrent;

  const Project({
    required this.id,
    required this.name,
    required this.directory,
    this.branch,
    this.sessionCount = 0,
    this.lastActiveAt = 0,
    this.isCurrent = false,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    final directory = json['directory'] ?? json['path'] ?? '';
    return Project(
      id: json['id'] ?? directory,
      name: json['name'] ?? _extractNameFromDirectory(directory),
      directory: directory,
      branch: json['branch'],
      sessionCount: json['sessionCount'] ?? json['session_count'] ?? 0,
      lastActiveAt: json['lastActiveAt'] ??
          json['last_active_at'] ??
          json['updatedAt'] ??
          0,
      isCurrent: json['isCurrent'] ?? json['is_current'] ?? false,
    );
  }

  /// 从目录路径提取项目名（取最后一段）
  static String _extractNameFromDirectory(String directory) {
    if (directory.isEmpty) return '未命名项目';
    // 兼容 Windows 和 Unix 路径
    final normalized = directory.replaceAll('\\', '/');
    final segments = normalized.split('/')..removeWhere((s) => s.isEmpty);
    return segments.isEmpty ? directory : segments.last;
  }

  Project copyWith({
    String? id,
    String? name,
    String? directory,
    String? branch,
    int? sessionCount,
    int? lastActiveAt,
    bool? isCurrent,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      directory: directory ?? this.directory,
      branch: branch ?? this.branch,
      sessionCount: sessionCount ?? this.sessionCount,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      isCurrent: isCurrent ?? this.isCurrent,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'directory': directory,
      if (branch != null) 'branch': branch,
      'sessionCount': sessionCount,
      'lastActiveAt': lastActiveAt,
      'isCurrent': isCurrent,
    };
  }

  @override
  String toString() => 'Project(id: $id, name: $name)';
}
