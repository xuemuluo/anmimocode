import 'dart:convert';

/// 会话状态枚举
///
/// 对应 MiMoCode 的 SessionStatus
enum SessionStatus {
  /// 空闲，等待用户输入
  idle,

  /// 忙碌，AI 正在处理
  processing,

  /// 错误状态
  error,
}

/// 会话状态扩展方法
extension SessionStatusExtension on SessionStatus {
  /// 获取状态中文标签
  String get label {
    switch (this) {
      case SessionStatus.idle:
        return '空闲';
      case SessionStatus.processing:
        return '执行中';
      case SessionStatus.error:
        return '错误';
    }
  }

  /// 从字符串解析状态
  static SessionStatus fromString(String? status) {
    switch (status) {
      case 'idle':
        return SessionStatus.idle;
      case 'processing':
      case 'busy':
      case 'running':
        return SessionStatus.processing;
      case 'error':
        return SessionStatus.error;
      default:
        return SessionStatus.idle;
    }
  }
}

/// 消息部分类型
///
/// 一条消息可以由多个部分组成（文本、工具调用等）
enum MessagePartType {
  /// 文本部分
  text,

  /// 工具调用部分
  tool,

  /// 思考过程
  reasoning,

  /// 其他/未知
  unknown,
}

/// 消息角色
enum MessageRole {
  /// 用户消息
  user,

  /// AI 助手消息
  assistant,

  /// 系统消息
  system,
}

/// 消息角色扩展
extension MessageRoleExtension on MessageRole {
  static MessageRole fromString(String? role) {
    switch (role) {
      case 'user':
        return MessageRole.user;
      case 'assistant':
        return MessageRole.assistant;
      case 'system':
        return MessageRole.system;
      default:
        return MessageRole.assistant;
    }
  }
}

/// 工具执行状态
enum ToolStatus {
  /// 等待执行
  pending,

  /// 执行中
  running,

  /// 已完成
  completed,

  /// 出错
  error,
}

/// 工具状态扩展
extension ToolStatusExtension on ToolStatus {
  String get label {
    switch (this) {
      case ToolStatus.pending:
        return '等待中';
      case ToolStatus.running:
        return '执行中';
      case ToolStatus.completed:
        return '完成';
      case ToolStatus.error:
        return '错误';
    }
  }

  static ToolStatus fromString(String? status) {
    switch (status) {
      case 'pending':
        return ToolStatus.pending;
      case 'running':
      case 'in_progress':
        return ToolStatus.running;
      case 'completed':
      case 'done':
      case 'success':
        return ToolStatus.completed;
      case 'error':
      case 'failed':
        return ToolStatus.error;
      default:
        return ToolStatus.pending;
    }
  }
}

/// 消息部分
///
/// 表示一条消息的组成部分。一条 AI 消息可能包含文本和多个工具调用。
class MessagePart {
  /// 部分 ID
  final String id;

  /// 部分类型
  final MessagePartType type;

  /// 文本内容（type 为 text 时使用）
  final String text;

  /// 工具名称（type 为 tool 时使用）
  final String? toolName;

  /// 工具执行状态
  final ToolStatus? toolStatus;

  /// 工具执行标题
  final String? toolTitle;

  /// 工具输入参数
  final Map<String, dynamic>? toolInput;

  /// 工具输出
  final String? toolOutput;

  /// 工具错误信息
  final String? toolError;

  /// 工具执行开始时间（毫秒时间戳）
  final int? toolStartTime;

  /// 工具执行结束时间（毫秒时间戳）
  final int? toolEndTime;

  const MessagePart({
    required this.id,
    required this.type,
    required this.text,
    this.toolName,
    this.toolStatus,
    this.toolTitle,
    this.toolInput,
    this.toolOutput,
    this.toolError,
    this.toolStartTime,
    this.toolEndTime,
  });

  /// 创建文本部分
  factory MessagePart.text({required String id, required String text}) {
    return MessagePart(id: id, type: MessagePartType.text, text: text);
  }

  /// 创建工具部分
  factory MessagePart.tool({
    required String id,
    required String toolName,
    ToolStatus status = ToolStatus.pending,
    String? title,
    Map<String, dynamic>? input,
    String? output,
    String? error,
    int? startTime,
    int? endTime,
  }) {
    return MessagePart(
      id: id,
      type: MessagePartType.tool,
      text: '',
      toolName: toolName,
      toolStatus: status,
      toolTitle: title,
      toolInput: input,
      toolOutput: output,
      toolError: error,
      toolStartTime: startTime,
      toolEndTime: endTime,
    );
  }

  /// 从 JSON 解析
  factory MessagePart.fromJson(Map<String, dynamic> json) {
    final type = _parsePartType(json['type']);
    return MessagePart(
      id: json['id'] ?? json['partId'] ?? '',
      type: type,
      text: json['text'] ?? '',
      toolName: json['tool'],
      toolStatus: ToolStatusExtension.fromString(json['status']),
      toolTitle: json['title'],
      toolInput: json['input'] is Map
          ? Map<String, dynamic>.from(json['input'] as Map)
          : null,
      toolOutput: json['output']?.toString(),
      toolError: json['error']?.toString(),
      toolStartTime:
          json['time'] is Map ? json['time']['start'] as int? : null,
      toolEndTime: json['time'] is Map ? json['time']['end'] as int? : null,
    );
  }

  static MessagePartType _parsePartType(String? type) {
    switch (type) {
      case 'text':
        return MessagePartType.text;
      case 'tool':
        return MessagePartType.tool;
      case 'reasoning':
        return MessagePartType.reasoning;
      default:
        return MessagePartType.unknown;
    }
  }

  /// 复制并修改
  MessagePart copyWith({
    String? id,
    MessagePartType? type,
    String? text,
    String? toolName,
    ToolStatus? toolStatus,
    String? toolTitle,
    Map<String, dynamic>? toolInput,
    String? toolOutput,
    String? toolError,
    int? toolStartTime,
    int? toolEndTime,
  }) {
    return MessagePart(
      id: id ?? this.id,
      type: type ?? this.type,
      text: text ?? this.text,
      toolName: toolName ?? this.toolName,
      toolStatus: toolStatus ?? this.toolStatus,
      toolTitle: toolTitle ?? this.toolTitle,
      toolInput: toolInput ?? this.toolInput,
      toolOutput: toolOutput ?? this.toolOutput,
      toolError: toolError ?? this.toolError,
      toolStartTime: toolStartTime ?? this.toolStartTime,
      toolEndTime: toolEndTime ?? this.toolEndTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'text': text,
      if (toolName != null) 'tool': toolName,
      if (toolStatus != null) 'status': toolStatus!.name,
      if (toolTitle != null) 'title': toolTitle,
      if (toolInput != null) 'input': toolInput,
      if (toolOutput != null) 'output': toolOutput,
      if (toolError != null) 'error': toolError,
      if (toolStartTime != null || toolEndTime != null)
        'time': {
          if (toolStartTime != null) 'start': toolStartTime,
          if (toolEndTime != null) 'end': toolEndTime,
        },
    };
  }

  @override
  String toString() => 'MessagePart(${toJson()})';
}

/// 消息
///
/// 表示一条完整的对话消息，可由多个部分（MessagePart）组成
class Message {
  /// 消息 ID
  final String id;

  /// 所属会话 ID
  final String sessionId;

  /// 消息角色
  final MessageRole role;

  /// 消息部分列表
  final List<MessagePart> parts;

  /// 创建时间（毫秒时间戳）
  final int createdAt;

  /// Token 使用情况
  final TokenUsage? tokens;

  /// 费用（美元）
  final double? cost;

  const Message({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.parts,
    required this.createdAt,
    this.tokens,
    this.cost,
  });

  /// 从 JSON 解析
  factory Message.fromJson(Map<String, dynamic> json) {
    final partsRaw = json['parts'] as List? ?? [];
    return Message(
      id: json['id'] ?? json['messageId'] ?? '',
      sessionId: json['sessionId'] ?? '',
      role: MessageRoleExtension.fromString(json['role']),
      parts: partsRaw
          .map((p) => MessagePart.fromJson(p as Map<String, dynamic>))
          .toList(),
      createdAt: json['createdAt'] ?? json['timestamp'] ?? 0,
      tokens: json['tokens'] != null
          ? TokenUsage.fromJson(json['tokens'] as Map<String, dynamic>)
          : null,
      cost: (json['cost'] as num?)?.toDouble(),
    );
  }

  /// 获取消息的纯文本内容（拼接所有文本部分）
  String get textContent {
    return parts
        .where((p) => p.type == MessagePartType.text)
        .map((p) => p.text)
        .join();
  }

  /// 获取所有工具部分
  List<MessagePart> get toolParts {
    return parts.where((p) => p.type == MessagePartType.tool).toList();
  }

  /// 复制并修改
  Message copyWith({
    String? id,
    String? sessionId,
    MessageRole? role,
    List<MessagePart>? parts,
    int? createdAt,
    TokenUsage? tokens,
    double? cost,
  }) {
    return Message(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      parts: parts ?? this.parts,
      createdAt: createdAt ?? this.createdAt,
      tokens: tokens ?? this.tokens,
      cost: cost ?? this.cost,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionId': sessionId,
      'role': role.name,
      'parts': parts.map((p) => p.toJson()).toList(),
      'createdAt': createdAt,
      if (tokens != null) 'tokens': tokens!.toJson(),
      if (cost != null) 'cost': cost,
    };
  }

  @override
  String toString() => 'Message(id: $id, role: ${role.name})';
}

/// Token 使用情况
class TokenUsage {
  /// 输入 Token 数
  final int input;

  /// 输出 Token 数
  final int output;

  /// 推理 Token 数
  final int reasoning;

  /// 缓存读取
  final int cacheRead;

  /// 缓存写入
  final int cacheWrite;

  const TokenUsage({
    this.input = 0,
    this.output = 0,
    this.reasoning = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
  });

  /// 总 Token 数
  int get total => input + output + reasoning;

  factory TokenUsage.fromJson(Map<String, dynamic> json) {
    final cache = json['cache'] ?? {};
    return TokenUsage(
      input: json['input'] ?? 0,
      output: json['output'] ?? 0,
      reasoning: json['reasoning'] ?? 0,
      cacheRead: cache['read'] ?? 0,
      cacheWrite: cache['write'] ?? 0,
    );
  }

  TokenUsage copyWith({
    int? input,
    int? output,
    int? reasoning,
    int? cacheRead,
    int? cacheWrite,
  }) {
    return TokenUsage(
      input: input ?? this.input,
      output: output ?? this.output,
      reasoning: reasoning ?? this.reasoning,
      cacheRead: cacheRead ?? this.cacheRead,
      cacheWrite: cacheWrite ?? this.cacheWrite,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'input': input,
      'output': output,
      'reasoning': reasoning,
      'cache': {'read': cacheRead, 'write': cacheWrite},
    };
  }
}

/// 会话
///
/// 表示一个对话会话，对应 MiMoCode 的 Session
class Session {
  /// 会话 ID
  final String id;

  /// 会话标题
  final String title;

  /// 所属项目目录
  final String? directory;

  /// 创建时间（毫秒时间戳）
  final int createdAt;

  /// 最后更新时间（毫秒时间戳）
  final int updatedAt;

  /// 会话状态
  final SessionStatus status;

  /// 消息数量
  final int messageCount;

  /// Token 使用情况
  final TokenUsage? tokens;

  /// 费用
  final double? cost;

  /// 最后一条消息预览
  final String? preview;

  /// 关联的项目 ID
  final String? projectId;

  const Session({
    required this.id,
    required this.title,
    this.directory,
    required this.createdAt,
    required this.updatedAt,
    this.status = SessionStatus.idle,
    this.messageCount = 0,
    this.tokens,
    this.cost,
    this.preview,
    this.projectId,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] ?? json['sessionId'] ?? '',
      title: json['title'] ?? '未命名会话',
      directory: json['directory'] ?? json['workingDirectory'],
      createdAt: json['createdAt'] ?? json['created_at'] ?? 0,
      updatedAt: json['updatedAt'] ?? json['updated_at'] ?? 0,
      status: SessionStatusExtension.fromString(json['status']),
      messageCount: json['messageCount'] ?? json['message_count'] ?? 0,
      tokens: json['tokens'] != null
          ? TokenUsage.fromJson(json['tokens'] as Map<String, dynamic>)
          : null,
      cost: (json['cost'] as num?)?.toDouble(),
      preview: json['preview'],
      projectId: json['projectId'] ?? json['project_id'],
    );
  }

  Session copyWith({
    String? id,
    String? title,
    String? directory,
    int? createdAt,
    int? updatedAt,
    SessionStatus? status,
    int? messageCount,
    TokenUsage? tokens,
    double? cost,
    String? preview,
    String? projectId,
  }) {
    return Session(
      id: id ?? this.id,
      title: title ?? this.title,
      directory: directory ?? this.directory,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      messageCount: messageCount ?? this.messageCount,
      tokens: tokens ?? this.tokens,
      cost: cost ?? this.cost,
      preview: preview ?? this.preview,
      projectId: projectId ?? this.projectId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      if (directory != null) 'directory': directory,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'status': status.name,
      'messageCount': messageCount,
      if (tokens != null) 'tokens': tokens!.toJson(),
      if (cost != null) 'cost': cost,
      if (preview != null) 'preview': preview,
      if (projectId != null) 'projectId': projectId,
    };
  }

  /// 从 JSON 字符串列表解析会话列表
  static List<Session> parseList(String jsonString) {
    try {
      final data = jsonDecode(jsonString);
      if (data is List) {
        return data
            .map((e) => Session.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (data is Map && data['sessions'] is List) {
        return (data['sessions'] as List)
            .map((e) => Session.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  @override
  String toString() => 'Session(id: $id, title: $title, status: ${status.name})';
}
