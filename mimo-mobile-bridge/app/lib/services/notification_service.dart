import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/notification.dart';
import 'websocket_service.dart';
// TODO: 安装 flutter_local_notifications 后取消注释
// import 'system_notification_service.dart';

/// 通知服务
///
/// 管理胶囊通知（前台）：
/// - 前台时显示应用内胶囊通知
/// - 权限请求处理
/// - 监听 WebSocket 消息自动生成通知
///
/// 注意：系统通知（后台通知）功能需要安装 flutter_local_notifications 包
/// 安装后取消注释相关代码即可启用
class NotificationService extends ChangeNotifier {
  NotificationService();

  /// WebSocket 服务引用（在 main.dart 中通过外部设置）
  WebSocketService? _ws;
  set webSocketService(WebSocketService? ws) {
    _ws = ws;
    _setupListeners();
  }

  WebSocketService? get webSocketService => _ws;

  /// 活动通知列表
  final List<CapsuleNotification> _notifications = [];
  List<CapsuleNotification> get notifications =>
      List.unmodifiable(_notifications);

  /// 最大显示数量
  static const int maxVisible = 3;

  /// 消息监听器
  StreamSubscription? _messageSub;

  /// 自动消失定时器
  final Map<String, Timer> _dismissTimers = {};

  /// 设置事件监听
  void _setupListeners() {
    _messageSub?.cancel();
    if (_ws == null) return;
    _messageSub = _ws!.messageStream.listen(_handleMessage);

    // TODO: 安装 flutter_local_notifications 后取消注释
    // _systemNotification.onPermissionAction = (permissionId, reply) {
    //   _ws?.sendMessage({
    //     'type': 'permission.reply',
    //     'requestId': permissionId,
    //     'permissionId': permissionId,
    //     'reply': reply,
    //   });
    //   dismiss('permission-$permissionId');
    // };
    // _systemNotification.onNotificationTap = (sessionId) {
    //   debugPrint('[Notification] 点击通知打开会话: $sessionId');
    // };
  }

  /// 处理 WebSocket 消息，自动生成通知
  void _handleMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;

    switch (type) {
      case 'permission.request':
        _handlePermissionRequest(message);
        break;

      case 'tool.progress':
      case 'tool.update':
        _handleToolProgress(message);
        break;

      case 'task.status':
        _handleTaskStatus(message);
        break;

      case 'task.complete':
      case 'session.complete':
        _handleTaskComplete(message);
        break;

      case 'error':
        _handleError(message);
        break;
    }
  }

  /// 处理权限请求
  void _handlePermissionRequest(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String? ?? '';
    final permissionId = (message['requestId'] as String?) ??
        (message['permissionId'] as String?) ??
        '';
    final permission = message['permission'] as Map<String, dynamic>?;
    final dialog = message['dialog'] as Map<String, dynamic>?;

    final title = dialog?['title'] as String? ?? '请求权限';
    final description = dialog?['message'] as String? ??
        permission?['description'] as String? ??
        '';

    final projectName = message['projectName'] as String?;

    showPermissionRequest(
      sessionId: sessionId,
      permissionId: permissionId,
      title: title,
      description: description,
      projectName: projectName,
    );
  }

  /// 处理工具执行进度
  void _handleToolProgress(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String? ?? '';
    final tool = message['tool'] as String? ?? '工具';
    final status = message['status'] as String?;
    final title = message['title'] as String? ?? '执行 $tool';
    final progress = message['progress'] as int?;

    final id = 'tool-${sessionId}-${message['toolId'] ?? tool}';

    CapsuleStatus? capsuleStatus;
    switch (status) {
      case 'pending':
        capsuleStatus = CapsuleStatus.waiting;
        break;
      case 'running':
      case 'in_progress':
        capsuleStatus = CapsuleStatus.working;
        break;
      case 'completed':
      case 'done':
      case 'success':
        capsuleStatus = CapsuleStatus.completed;
        break;
      case 'error':
      case 'failed':
        capsuleStatus = CapsuleStatus.error;
        break;
    }

    if (capsuleStatus == CapsuleStatus.completed ||
        capsuleStatus == CapsuleStatus.error) {
      _updateOrShow(
        id: id,
        type: CapsuleType.toolExecution,
        sessionId: sessionId,
        title: title,
        subtitle: capsuleStatus == CapsuleStatus.completed ? '已完成' : '执行失败',
        status: capsuleStatus,
        progress: progress,
        duration: 2000,
        dismissible: true,
      );
    } else {
      _updateOrShow(
        id: id,
        type: CapsuleType.toolExecution,
        sessionId: sessionId,
        title: title,
        status: capsuleStatus,
        progress: progress,
        duration: 0,
        dismissible: false,
      );
    }
  }

  /// 处理任务状态
  void _handleTaskStatus(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String? ?? '';
    final sessionTitle = message['sessionTitle'] as String?;
    final status = message['status'] as String?;
    final currentTask = message['currentTask'] as String?;
    final progressData = message['progress'] as Map<String, dynamic>?;

    int? progress;
    if (progressData != null) {
      progress = (progressData['percentage'] as num?)?.toInt();
    }

    final id = 'task-$sessionId';

    CapsuleStatus? capsuleStatus;
    switch (status) {
      case 'idle':
        dismiss(id);
        return;
      case 'working':
        capsuleStatus = CapsuleStatus.working;
        break;
      case 'waiting':
        capsuleStatus = CapsuleStatus.waiting;
        break;
      case 'completed':
        capsuleStatus = CapsuleStatus.completed;
        break;
      case 'error':
        capsuleStatus = CapsuleStatus.error;
        break;
    }

    _updateOrShow(
      id: id,
      type: CapsuleType.sessionStatus,
      sessionId: sessionId,
      projectName: sessionTitle,
      title: currentTask ?? sessionTitle ?? '任务执行中',
      status: capsuleStatus,
      progress: progress,
      duration: 0,
      dismissible: false,
    );
  }

  /// 处理任务完成
  void _handleTaskComplete(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String? ?? '';
    final sessionTitle = message['sessionTitle'] as String?;
    final metrics = message['metrics'] as Map<String, dynamic>?;

    String? subtitle;
    if (metrics != null) {
      final duration = metrics['duration'] as int?;
      final cost = (metrics['cost'] as num?)?.toDouble();
      final parts = <String>[];
      if (duration != null) {
        parts.add('耗时 ${_formatDuration(duration)}');
      }
      if (cost != null) {
        parts.add('\$${cost.toStringAsFixed(4)}');
      }
      subtitle = parts.join(' · ');
    }

    showTaskComplete(
      sessionId: sessionId,
      projectName: sessionTitle,
      title: '任务完成',
      subtitle: subtitle,
    );
  }

  /// 处理错误
  void _handleError(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String? ?? '';
    final errorMessage = message['message'] as String? ?? '未知错误';
    final code = message['code'] as String?;

    showErrorAlert(
      sessionId: sessionId,
      title: '发生错误',
      error: errorMessage,
      code: code,
    );
  }

  /// 显示或更新通知
  void _updateOrShow({
    required String id,
    required CapsuleType type,
    required String sessionId,
    String? projectName,
    required String title,
    String? subtitle,
    CapsuleStatus? status,
    int? progress,
    int? badge,
    List<QuickAction> quickActions = const [],
    List<CapsuleAction> actions = const [],
    int? duration,
    bool dismissible = true,
    CapsulePriority priority = CapsulePriority.normal,
  }) {
    final existingIndex = _notifications.indexWhere((n) => n.id == id);
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final notification = CapsuleNotification(
      id: id,
      type: type,
      sessionId: sessionId,
      projectName: projectName,
      priority: priority,
      title: title,
      subtitle: subtitle,
      status: status,
      progress: progress,
      badge: badge,
      quickActions: quickActions,
      actions: actions,
      duration: duration,
      timestamp: timestamp,
      dismissible: dismissible,
    );

    if (existingIndex >= 0) {
      _notifications[existingIndex] = notification;
    } else {
      _notifications.insert(0, notification);
    }

    _scheduleAutoDismiss(id, duration);
    notifyListeners();
  }

  /// 显示权限请求通知（带快捷动作）
  void showPermissionRequest({
    required String sessionId,
    required String permissionId,
    required String title,
    required String description,
    String? projectName,
  }) {
    final id = 'permission-$permissionId';

    _updateOrShow(
      id: id,
      type: CapsuleType.permissionRequest,
      sessionId: sessionId,
      projectName: projectName,
      priority: CapsulePriority.high,
      title: title,
      subtitle: description,
      status: CapsuleStatus.waiting,
      duration: 0,
      dismissible: false,
      quickActions: [
        const QuickAction(
          id: 'once',
          label: '仅此一次',
          icon: 'looks_one',
          type: QuickActionType.once,
          reply: PermissionReply.once,
          primary: true,
        ),
        const QuickAction(
          id: 'always',
          label: '始终允许',
          icon: 'check_circle',
          type: QuickActionType.always,
          reply: PermissionReply.always,
        ),
        const QuickAction(
          id: 'reject',
          label: '拒绝',
          icon: 'close',
          type: QuickActionType.reject,
          reply: PermissionReply.reject,
        ),
      ],
    );

    // TODO: 安装 flutter_local_notifications 后取消注释
    // _systemNotification.showPermissionRequest(
    //   sessionId: sessionId,
    //   permissionId: permissionId,
    //   title: title,
    //   body: description,
    //   projectName: projectName,
    // );
  }

  /// 显示任务完成通知
  void showTaskComplete({
    required String sessionId,
    String? projectName,
    required String title,
    String? subtitle,
  }) {
    final id = 'complete-$sessionId-${DateTime.now().millisecondsSinceEpoch}';

    _updateOrShow(
      id: id,
      type: CapsuleType.taskComplete,
      sessionId: sessionId,
      projectName: projectName,
      priority: CapsulePriority.normal,
      title: title,
      subtitle: subtitle,
      status: CapsuleStatus.completed,
      duration: 8000,
      dismissible: true,
      quickActions: [
        const QuickAction(
          id: 'view',
          label: '查看详情',
          icon: 'visibility',
          type: QuickActionType.view,
          primary: true,
        ),
        const QuickAction(
          id: 'dismiss',
          label: '知道了',
          icon: 'check',
          type: QuickActionType.confirm,
        ),
      ],
    );

    // TODO: 安装 flutter_local_notifications 后取消注释
    // _systemNotification.showTaskComplete(
    //   sessionId: sessionId,
    //   title: title,
    //   body: subtitle,
    //   projectName: projectName,
    // );
  }

  /// 显示错误警告
  void showErrorAlert({
    required String sessionId,
    required String title,
    required String error,
    String? code,
    String? projectName,
  }) {
    final id = 'error-$sessionId-${DateTime.now().millisecondsSinceEpoch}';

    String subtitle = error;
    if (code != null) {
      subtitle = '[$code] $error';
    }

    _updateOrShow(
      id: id,
      type: CapsuleType.errorAlert,
      sessionId: sessionId,
      projectName: projectName,
      priority: CapsulePriority.urgent,
      title: title,
      subtitle: subtitle,
      status: CapsuleStatus.error,
      duration: 15000,
      dismissible: true,
      quickActions: [
        const QuickAction(
          id: 'view_error',
          label: '查看错误',
          icon: 'bug_report',
          type: QuickActionType.view,
          primary: true,
        ),
        const QuickAction(
          id: 'dismiss',
          label: '忽略',
          icon: 'close',
          type: QuickActionType.deny,
        ),
      ],
    );

    // TODO: 安装 flutter_local_notifications 后取消注释
    // _systemNotification.showErrorAlert(
    //   sessionId: sessionId,
    //   title: title,
    //   body: subtitle,
    //   projectName: projectName,
    // );
  }

  /// 显示会话状态通知
  void showSessionStatus({
    required String sessionId,
    String? projectName,
    required String title,
    String? subtitle,
    required CapsuleStatus status,
    int? progress,
  }) {
    final id = 'session-$sessionId';

    _updateOrShow(
      id: id,
      type: CapsuleType.sessionStatus,
      sessionId: sessionId,
      projectName: projectName,
      title: title,
      subtitle: subtitle,
      status: status,
      progress: progress,
      duration: status == CapsuleStatus.completed ? 3000 : 0,
      dismissible: status == CapsuleStatus.completed,
    );

    // TODO: 安装 flutter_local_notifications 后取消注释
    // if (status == CapsuleStatus.completed || status == CapsuleStatus.error) {
    //   _systemNotification.showSessionStatus(
    //     sessionId: sessionId,
    //     title: title,
    //     body: subtitle,
    //     projectName: projectName,
    //   );
    // }
  }

  /// 显示工具执行通知
  void showToolExecution({
    required String sessionId,
    String? projectName,
    required String toolName,
    required String status,
    String? title,
    int? progress,
  }) {
    final id = 'tool-${sessionId}-$toolName';

    CapsuleStatus? capsuleStatus;
    switch (status) {
      case 'pending':
        capsuleStatus = CapsuleStatus.waiting;
        break;
      case 'running':
        capsuleStatus = CapsuleStatus.working;
        break;
      case 'completed':
        capsuleStatus = CapsuleStatus.completed;
        break;
      case 'error':
        capsuleStatus = CapsuleStatus.error;
        break;
    }

    _updateOrShow(
      id: id,
      type: CapsuleType.toolExecution,
      sessionId: sessionId,
      projectName: projectName,
      title: title ?? '执行 $toolName',
      status: capsuleStatus,
      progress: progress,
      duration: capsuleStatus == CapsuleStatus.completed ? 2000 : 0,
      dismissible: capsuleStatus == CapsuleStatus.completed ||
          capsuleStatus == CapsuleStatus.error,
    );

    // TODO: 安装 flutter_local_notifications 后取消注释
    // _systemNotification.showToolProgress(
    //   sessionId: sessionId,
    //   toolName: toolName,
    //   status: status,
    //   title: title,
    //   progress: progress,
    // );
  }

  /// 处理权限请求快捷动作
  void handlePermissionAction(String notificationId, PermissionReply reply) {
    final permissionId = notificationId.replaceFirst('permission-', '');

    _ws?.sendMessage({
      'type': 'permission.reply',
      'requestId': permissionId,
      'permissionId': permissionId,
      'reply': reply.name,
    });

    dismiss(notificationId);
  }

  /// 中止会话
  void abortSession(String sessionId) {
    _ws?.sendMessage({
      'type': 'session.abort',
      'sessionId': sessionId,
    });

    dismissSession(sessionId);
  }

  /// 调度自动消失
  void _scheduleAutoDismiss(String id, int? durationMs) {
    _dismissTimers[id]?.cancel();

    if (durationMs != null && durationMs > 0) {
      _dismissTimers[id] = Timer(Duration(milliseconds: durationMs), () {
        dismiss(id);
      });
    }
  }

  /// 关闭指定通知
  void dismiss(String id) {
    final removed = _notifications.any((n) => n.id == id);
    if (!removed) return;

    _notifications.removeWhere((n) => n.id == id);
    _dismissTimers[id]?.cancel();
    _dismissTimers.remove(id);

    // TODO: 安装 flutter_local_notifications 后取消注释
    // _systemNotification.cancelByBusinessId(id);

    notifyListeners();
  }

  /// 关闭会话相关的所有通知
  void dismissSession(String sessionId) {
    final ids = _notifications
        .where((n) => n.sessionId == sessionId)
        .map((n) => n.id)
        .toList();

    for (final id in ids) {
      dismiss(id);
    }

    // TODO: 安装 flutter_local_notifications 后取消注释
    // _systemNotification.cancelSession(sessionId);
  }

  /// 关闭所有通知
  void clearAll() {
    _notifications.clear();
    for (final timer in _dismissTimers.values) {
      timer.cancel();
    }
    _dismissTimers.clear();

    // TODO: 安装 flutter_local_notifications 后取消注释
    // _systemNotification.cancelAll();

    notifyListeners();
  }

  /// 格式化持续时间
  String _formatDuration(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    if (seconds < 60) return '$seconds 秒';
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes < 60) return '$minutes 分 $remainingSeconds 秒';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return '$hours 小时 $remainingMinutes 分';
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    for (final timer in _dismissTimers.values) {
      timer.cancel();
    }
    _dismissTimers.clear();
    super.dispose();
  }
}
