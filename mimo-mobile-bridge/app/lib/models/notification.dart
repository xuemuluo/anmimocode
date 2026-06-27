/// 胶囊通知类型
///
/// 对应不同业务场景的通知展示
enum CapsuleType {
  /// 会话状态变化
  sessionStatus,

  /// 工具执行进度
  toolExecution,

  /// 权限请求
  permissionRequest,

  /// 任务完成
  taskComplete,

  /// 错误警告
  errorAlert,

  /// 进度更新
  progress,
}

/// 通知优先级
enum CapsulePriority {
  /// 低
  low,

  /// 普通
  normal,

  /// 高
  high,

  /// 紧急
  urgent,
}

/// 通知状态指示
enum CapsuleStatus {
  /// 空闲
  idle,

  /// 工作中
  working,

  /// 等待用户操作
  waiting,

  /// 已完成
  completed,

  /// 出错
  error,
}

/// 快捷动作按钮类型
enum QuickActionType {
  /// 确认
  confirm,

  /// 拒绝
  deny,

  /// 仅此一次
  once,

  /// 始终允许
  always,

  /// 拒绝
  reject,

  /// 查看详情
  view,

  /// 中止
  abort,
}

/// 权限回复类型
enum PermissionReply {
  /// 仅此一次
  once,

  /// 始终允许
  always,

  /// 拒绝
  reject,
}

/// 标准动作按钮类型
enum CapsuleActionType {
  primary,
  secondary,
  destructive,
}

/// 快捷动作按钮
class QuickAction {
  /// 动作 ID
  final String id;

  /// 按钮文字
  final String label;

  /// 图标名称（material icon）
  final String? icon;

  /// 动作类型
  final QuickActionType type;

  /// 权限回复类型（权限请求时使用）
  final PermissionReply? reply;

  /// 是否为主要按钮（高亮显示）
  final bool primary;

  const QuickAction({
    required this.id,
    required this.label,
    this.icon,
    required this.type,
    this.reply,
    this.primary = false,
  });
}

/// 标准动作按钮（展开后显示）
class CapsuleAction {
  /// 动作 ID
  final String id;

  /// 按钮文字
  final String label;

  /// 图标名称
  final String? icon;

  /// 按钮类型
  final CapsuleActionType type;

  const CapsuleAction({
    required this.id,
    required this.label,
    this.icon,
    this.type = CapsuleActionType.secondary,
  });
}

/// 胶囊通知数据
///
/// 类似 iOS Dynamic Island 的悬浮通知，可展开/收起
class CapsuleNotification {
  /// 通知 ID
  final String id;

  /// 通知类型
  final CapsuleType type;

  /// 关联的会话 ID
  final String sessionId;

  /// 关联的项目名称（用于上下文展示）
  final String? projectName;

  /// 优先级
  final CapsulePriority priority;

  /// 标题
  final String title;

  /// 副标题/描述
  final String? subtitle;

  /// 状态指示
  final CapsuleStatus? status;

  /// 进度（0-100）
  final int? progress;

  /// 角标数字
  final int? badge;

  /// 快捷动作按钮列表（收起状态也可显示）
  final List<QuickAction> quickActions;

  /// 标准动作按钮列表（展开后显示）
  final List<CapsuleAction> actions;

  /// 自动消失时间（毫秒），null 或 0 表示常驻
  final int? duration;

  /// 创建时间戳
  final int timestamp;

  /// 是否可关闭
  final bool dismissible;

  const CapsuleNotification({
    required this.id,
    required this.type,
    required this.sessionId,
    this.projectName,
    this.priority = CapsulePriority.normal,
    required this.title,
    this.subtitle,
    this.status,
    this.progress,
    this.badge,
    this.quickActions = const [],
    this.actions = const [],
    this.duration,
    required this.timestamp,
    this.dismissible = true,
  });

  CapsuleNotification copyWith({
    String? id,
    CapsuleType? type,
    String? sessionId,
    String? projectName,
    CapsulePriority? priority,
    String? title,
    String? subtitle,
    CapsuleStatus? status,
    int? progress,
    int? badge,
    List<QuickAction>? quickActions,
    List<CapsuleAction>? actions,
    int? duration,
    int? timestamp,
    bool? dismissible,
  }) {
    return CapsuleNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      sessionId: sessionId ?? this.sessionId,
      projectName: projectName ?? this.projectName,
      priority: priority ?? this.priority,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      badge: badge ?? this.badge,
      quickActions: quickActions ?? this.quickActions,
      actions: actions ?? this.actions,
      duration: duration ?? this.duration,
      timestamp: timestamp ?? this.timestamp,
      dismissible: dismissible ?? this.dismissible,
    );
  }
}
