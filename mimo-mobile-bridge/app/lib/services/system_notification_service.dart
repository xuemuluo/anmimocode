import 'dart:async';

import 'package:flutter/foundation.dart';

class SystemNotificationService extends ChangeNotifier {
  static final SystemNotificationService _instance =
      SystemNotificationService._();
  factory SystemNotificationService() => _instance;
  SystemNotificationService._();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Function(String? sessionId)? onNotificationTap;
  Function(String permissionId, String reply)? onPermissionAction;

  int _idCounter = 0;
  final Map<String, int> _idMap = {};
  final Map<String, List<int>> _sessionNotifications = {};

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    debugPrint('[SystemNotification] 系统通知服务已初始化（简化模式）');
  }

  Future<void> showPermissionRequest({
    required String sessionId,
    required String permissionId,
    required String title,
    required String body,
    String? projectName,
    String? sessionTitle,
  }) async {
    if (!_initialized) return;
    debugPrint('[SystemNotification] 权限请求: $title - $body');
  }

  Future<void> showTaskComplete({
    required String sessionId,
    required String title,
    String? body,
    String? projectName,
  }) async {
    if (!_initialized) return;
    debugPrint('[SystemNotification] 任务完成: $title');
  }

  Future<void> showErrorAlert({
    required String sessionId,
    required String title,
    required String body,
    String? projectName,
  }) async {
    if (!_initialized) return;
    debugPrint('[SystemNotification] 错误: $title - $body');
  }

  Future<void> showToolProgress({
    required String sessionId,
    required String toolName,
    required String status,
    String? title,
    int? progress,
  }) async {
    if (!_initialized) return;
    debugPrint('[SystemNotification] 工具进度: $toolName - $status');
  }

  Future<void> showSessionStatus({
    required String sessionId,
    required String title,
    String? body,
    String? projectName,
  }) async {
    if (!_initialized) return;
    debugPrint('[SystemNotification] 会话状态: $title');
  }

  void cancelByBusinessId(String businessId) {}
  void cancelById(int notificationId) {}

  void cancelSession(String sessionId) {
    _sessionNotifications.remove(sessionId);
  }

  Future<void> cancelAll() async {
    _idMap.clear();
    _sessionNotifications.clear();
  }

  Future<void> updateBadge(int count) async {}

  @override
  void dispose() {
    cancelAll();
    super.dispose();
  }
}
