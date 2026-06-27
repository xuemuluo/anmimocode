import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/project.dart';
import 'websocket_service.dart';

/// 项目服务
///
/// 管理与 MiMoCode 的项目交互：
/// - 获取当前项目
/// - 列出已打开的项目
/// - 切换工作目录
class ProjectService extends ChangeNotifier {
  final WebSocketService _ws;

  ProjectService(this._ws) {
    _setupListeners();
  }

  /// 项目列表
  List<Project> _projects = [];
  List<Project> get projects => _projects;

  /// 当前活动项目
  Project? _currentProject;
  Project? get currentProject => _currentProject;

  /// 加载状态
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// 错误信息
  String? _error;
  String? get error => _error;

  /// 消息监听器
  StreamSubscription? _messageSub;

  /// 设置事件监听
  void _setupListeners() {
    _messageSub = _ws.messageStream.listen(_handleMessage);
  }

  /// 处理 WebSocket 消息
  void _handleMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;

    switch (type) {
      case 'project.current':
        _handleCurrentProject(message);
        break;

      case 'project.list':
        _handleProjectList(message);
        break;

      case 'project.changed':
        // 项目切换通知
        loadCurrentProject();
        break;
    }
  }

  /// 处理当前项目响应
  void _handleCurrentProject(Map<String, dynamic> message) {
    final projectData = message['project'] as Map<String, dynamic>?;
    if (projectData != null) {
      _currentProject = Project.fromJson(projectData).copyWith(isCurrent: true);

      // 更新项目列表中的当前标记
      _projects = _projects
          .map((p) => p.copyWith(isCurrent: p.id == _currentProject!.id))
          .toList();

      notifyListeners();
    }
  }

  /// 处理项目列表响应
  void _handleProjectList(Map<String, dynamic> message) {
    final projectsRaw = message['projects'] as List? ?? [];
    _projects = projectsRaw
        .map((p) => Project.fromJson(p as Map<String, dynamic>))
        .toList();

    // 如果有当前项目，标记
    if (_currentProject != null) {
      _projects = _projects
          .map((p) => p.copyWith(isCurrent: p.id == _currentProject!.id))
          .toList();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// 加载项目列表
  Future<List<Project>> loadProjects() async {
    if (!_ws.isReady) {
      _error = '未连接到服务器';
      notifyListeners();
      return _projects;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _ws.sendRequest({
        'type': 'project.list',
      });

      final projectsRaw = response['projects'] as List? ?? [];
      _projects = projectsRaw
          .map((p) => Project.fromJson(p as Map<String, dynamic>))
          .toList();

      _isLoading = false;
      notifyListeners();
      return _projects;
    } catch (e) {
      _isLoading = false;
      _error = '加载项目列表失败: $e';
      notifyListeners();
      return _projects;
    }
  }

  /// 加载当前项目
  Future<Project?> loadCurrentProject() async {
    if (!_ws.isReady) {
      _error = '未连接到服务器';
      notifyListeners();
      return _currentProject;
    }

    try {
      final response = await _ws.sendRequest({
        'type': 'project.current',
      });

      final projectData = response['project'] as Map<String, dynamic>?;
      if (projectData != null) {
        _currentProject = Project.fromJson(projectData).copyWith(isCurrent: true);
        _projects = _projects
            .map((p) => p.copyWith(isCurrent: p.id == _currentProject!.id))
            .toList();
        notifyListeners();
      }
      return _currentProject;
    } catch (e) {
      _error = '加载当前项目失败: $e';
      notifyListeners();
      return _currentProject;
    }
  }

  /// 切换工作目录
  ///
  /// 手机端仅支持在已打开的项目间切换，
  /// 通过发送 project.changeDir 请求服务器切换当前项目
  Future<bool> changeDirectory(String directory) async {
    if (!_ws.isReady) {
      _error = '未连接到服务器';
      notifyListeners();
      return false;
    }

    try {
      await _ws.sendRequest({
        'type': 'project.changeDir',
        'directory': directory,
      });

      // 切换成功后重新加载当前项目
      await loadCurrentProject();
      return true;
    } catch (e) {
      _error = '切换项目失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 刷新项目列表（同时刷新当前项目）
  Future<void> refresh() async {
    await Future.wait([
      loadProjects(),
      loadCurrentProject(),
    ]);
  }

  /// 根据 ID 查找项目
  Project? findById(String id) {
    try {
      return _projects.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 根据目录查找项目
  Project? findByDirectory(String directory) {
    try {
      return _projects.firstWhere((p) => p.directory == directory);
    } catch (_) {
      return null;
    }
  }

  /// 清除错误
  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }
}
