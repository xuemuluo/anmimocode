import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/session.dart';
import 'websocket_service.dart';

/// 会话服务
///
/// 管理与 MiMoCode 的会话交互：
/// - 获取会话列表
/// - 创建新会话
/// - 获取会话详情
/// - 获取会话消息历史
/// - 发送消息（流式响应）
/// - 中止会话
/// - 删除会话
class SessionService extends ChangeNotifier {
  final WebSocketService _ws;

  SessionService(this._ws) {
    _setupListeners();
  }

  /// 所有已加载的会话（按项目分组）
  ///
  /// key: projectId (或 directory), value: 该项目下的会话列表
  final Map<String, List<Session>> _sessionsByProject = {};
  Map<String, List<Session>> get sessionsByProject => _sessionsByProject;

  /// 当前查看的会话列表（用于 SessionListScreen）
  List<Session> _currentSessions = [];
  List<Session> get currentSessions => _currentSessions;

  /// 当前加载的项目 ID
  String? _currentProjectId;
  String? get currentProjectId => _currentProjectId;

  /// 会话消息缓存（key: sessionId）
  final Map<String, List<Message>> _messagesBySession = {};
  List<Message> messagesFor(String sessionId) =>
      _messagesBySession[sessionId] ?? [];

  /// 会话状态缓存（key: sessionId）
  final Map<String, Session> _sessionMap = {};
  Session? sessionById(String id) => _sessionMap[id];

  /// 加载状态
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// 错误信息
  String? _error;
  String? get error => _error;

  /// 流式响应监听器
  StreamSubscription? _messageSub;

  /// 设置事件监听
  void _setupListeners() {
    _messageSub = _ws.messageStream.listen(_handleMessage);
  }

  /// 处理 WebSocket 消息
  void _handleMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;
    final sessionId = message['sessionId'] as String?;

    switch (type) {
      // 流式文本片段
      case 'chunk':
      case 'message.part.delta':
        _handleChunk(message);
        break;

      // 工具执行更新
      case 'tool.update':
      case 'tool.execution.update':
      case 'tool.progress':
        _handleToolUpdate(message);
        break;

      // 步骤完成
      case 'step.finish':
        _handleStepFinish(message);
        break;

      // 会话完成
      case 'done':
      case 'prompt.done':
        _handleDone(message);
        break;

      // 错误
      case 'error':
        _handleError(message);
        break;

      // 事件订阅
      case 'event':
        _handleEvent(message);
        break;

      // 会话状态更新
      case 'session.status':
      case 'session.status.update':
        _handleSessionStatus(message);
        break;
    }
  }

  /// 处理流式文本片段
  void _handleChunk(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String?;
    final partId = message['partId'] as String?;
    final content = message['content'] as String? ?? message['delta'] as String?;

    if (sessionId == null || content == null) return;

    final messages = _messagesBySession[sessionId];
    if (messages == null || messages.isEmpty) return;

    // 找到最后一条 AI 消息
    final lastMessage = messages.last;
    if (lastMessage.role != MessageRole.assistant) return;

    // 查找或创建对应的文本部分
    final parts = List<MessagePart>.from(lastMessage.parts);
    var found = false;
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.type == MessagePartType.text &&
          (partId == null || part.id == partId)) {
        parts[i] = part.copyWith(text: part.text + content);
        found = true;
        break;
      }
    }

    if (!found && partId != null) {
      parts.add(MessagePart.text(id: partId, text: content));
    }

    messages[messages.length - 1] = lastMessage.copyWith(parts: parts);
    notifyListeners();
  }

  /// 处理工具执行更新
  void _handleToolUpdate(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String?;
    final partId = message['partId'] as String? ?? message['toolId'] as String?;
    if (sessionId == null || partId == null) return;

    final messages = _messagesBySession[sessionId];
    if (messages == null || messages.isEmpty) return;

    final lastMessage = messages.last;
    final parts = List<MessagePart>.from(lastMessage.parts);

    // 查找是否已存在该工具部分
    var found = false;
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].type == MessagePartType.tool && parts[i].id == partId) {
        parts[i] = parts[i].copyWith(
          toolName: message['tool'] as String? ?? parts[i].toolName,
          toolStatus: ToolStatusExtension.fromString(message['status'] as String?),
          toolTitle: message['title'] as String? ?? parts[i].toolTitle,
          toolOutput: message['output']?.toString() ?? parts[i].toolOutput,
          toolError: message['error']?.toString() ?? parts[i].toolError,
        );
        found = true;
        break;
      }
    }

    if (!found) {
      parts.add(MessagePart.tool(
        id: partId,
        toolName: message['tool'] as String? ?? 'unknown',
        status: ToolStatusExtension.fromString(message['status'] as String?),
        title: message['title'] as String?,
        input: message['input'] is Map
            ? Map<String, dynamic>.from(message['input'] as Map)
            : null,
        output: message['output']?.toString(),
        error: message['error']?.toString(),
      ));
    }

    messages[messages.length - 1] = lastMessage.copyWith(parts: parts);
    notifyListeners();
  }

  /// 处理步骤完成
  void _handleStepFinish(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String?;
    if (sessionId == null) return;

    final tokens = message['tokens'];
    final cost = message['cost'];

    final messages = _messagesBySession[sessionId];
    if (messages == null || messages.isEmpty) return;

    final lastMessage = messages.last;
    TokenUsage? tokenUsage;
    if (tokens is Map) {
      tokenUsage = TokenUsage.fromJson(Map<String, dynamic>.from(tokens));
    }

    messages[messages.length - 1] = lastMessage.copyWith(
      tokens: tokenUsage ?? lastMessage.tokens,
      cost: cost is num ? cost.toDouble() : lastMessage.cost,
    );
    notifyListeners();
  }

  /// 处理会话完成
  void _handleDone(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String?;
    if (sessionId == null) return;

    // 更新会话状态为空闲
    final session = _sessionMap[sessionId];
    if (session != null) {
      _sessionMap[sessionId] =
          session.copyWith(status: SessionStatus.idle);
      _updateSessionInList(sessionId, _sessionMap[sessionId]!);
    }

    notifyListeners();
  }

  /// 处理错误
  void _handleError(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String?;
    final errorMessage = message['message'] as String? ?? '未知错误';

    if (sessionId != null) {
      final session = _sessionMap[sessionId];
      if (session != null) {
        _sessionMap[sessionId] =
            session.copyWith(status: SessionStatus.error);
        _updateSessionInList(sessionId, _sessionMap[sessionId]!);
      }
    }

    _error = errorMessage;
    notifyListeners();
  }

  /// 处理事件推送
  void _handleEvent(Map<String, dynamic> message) {
    final event = message['event'] as Map<String, dynamic>?;
    if (event == null) return;

    final eventType = event['type'] as String?;
    final properties = event['properties'] as Map<String, dynamic>?;
    if (properties == null) return;

    final sessionId = properties['sessionID'] as String?;
    if (sessionId == null) return;

    switch (eventType) {
      case 'session.updated':
        final info = properties['info'] as Map<String, dynamic>?;
        if (info != null) {
          final session = Session.fromJson(info);
          _sessionMap[sessionId] = session;
          _updateSessionInList(sessionId, session);
          notifyListeners();
        }
        break;

      case 'session.status':
        final status = properties['status'];
        final session = _sessionMap[sessionId];
        if (session != null && status is Map) {
          final statusType = status['type'] as String?;
          _sessionMap[sessionId] = session.copyWith(
            status: SessionStatusExtension.fromString(statusType),
          );
          _updateSessionInList(sessionId, _sessionMap[sessionId]!);
          notifyListeners();
        }
        break;

      case 'message.updated':
        final info = properties['info'] as Map<String, dynamic>?;
        if (info != null) {
          final msg = Message.fromJson(info);
          _addOrUpdateMessage(sessionId, msg);
          notifyListeners();
        }
        break;

      case 'message.part.updated':
        final part = properties['part'] as Map<String, dynamic>?;
        if (part != null) {
          _handleToolUpdate({
            'sessionId': sessionId,
            'partId': part['id'] ?? part['partId'],
            'tool': part['tool'],
            'status': part['status'],
            'title': part['title'],
            'output': part['output'],
            'error': part['error'],
            'input': part['input'],
          });
        }
        break;

      case 'message.part.delta':
        _handleChunk({
          'sessionId': sessionId,
          'partId': properties['partID'],
          'content': properties['delta'],
        });
        break;
    }
  }

  /// 处理会话状态更新
  void _handleSessionStatus(Map<String, dynamic> message) {
    final sessionId = message['sessionId'] as String?;
    final status = message['status'];
    if (sessionId == null || status == null) return;

    final session = _sessionMap[sessionId];
    if (session != null) {
      String? statusType;
      if (status is String) {
        statusType = status;
      } else if (status is Map) {
        statusType = status['type'] as String?;
      }
      _sessionMap[sessionId] =
          session.copyWith(status: SessionStatusExtension.fromString(statusType));
      _updateSessionInList(sessionId, _sessionMap[sessionId]!);
      notifyListeners();
    }
  }

  /// 更新会话列表中的会话
  void _updateSessionInList(String sessionId, Session session) {
    for (final entry in _sessionsByProject.entries) {
      final sessions = entry.value;
      for (var i = 0; i < sessions.length; i++) {
        if (sessions[i].id == sessionId) {
          sessions[i] = session;
          if (entry.key == _currentProjectId) {
            _currentSessions = List.from(sessions);
          }
          return;
        }
      }
    }
  }

  /// 添加或更新消息
  void _addOrUpdateMessage(String sessionId, Message message) {
    final messages = _messagesBySession.putIfAbsent(sessionId, () => []);
    var found = false;
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].id == message.id) {
        messages[i] = message;
        found = true;
        break;
      }
    }
    if (!found) {
      messages.add(message);
    }
  }

  /// 设置当前查看的项目
  void setCurrentProject(String projectId) {
    _currentProjectId = projectId;
    _currentSessions = List.from(_sessionsByProject[projectId] ?? []);
    notifyListeners();
  }

  /// 加载指定项目的会话列表
  Future<List<Session>> loadSessions({
    required String projectId,
    String? directory,
    int limit = 50,
    String? search,
  }) async {
    if (!_ws.isReady) {
      _error = '未连接到服务器';
      notifyListeners();
      return _sessionsByProject[projectId] ?? [];
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _ws.sendRequest({
        'type': 'session.list',
        'directory': directory,
        'limit': limit,
        if (search != null) 'search': search,
      });

      final sessionsRaw = response['sessions'] as List? ?? [];
      final sessions = sessionsRaw
          .map((s) => Session.fromJson(s as Map<String, dynamic>))
          .toList();

      _sessionsByProject[projectId] = sessions;
      for (final session in sessions) {
        _sessionMap[session.id] = session;
      }

      _currentProjectId = projectId;
      _currentSessions = sessions;
      _isLoading = false;
      notifyListeners();
      return sessions;
    } catch (e) {
      _isLoading = false;
      _error = '加载会话列表失败: $e';
      notifyListeners();
      return _sessionsByProject[projectId] ?? [];
    }
  }

  /// 创建新会话
  Future<Session?> createSession({
    required String projectId,
    String? title,
    String? workingDirectory,
  }) async {
    if (!_ws.isReady) {
      _error = '未连接到服务器';
      notifyListeners();
      return null;
    }

    try {
      final response = await _ws.sendRequest({
        'type': 'session.create',
        if (title != null) 'title': title,
        if (workingDirectory != null) 'directory': workingDirectory,
      });

      final sessionData = response['session'] as Map<String, dynamic>?;
      if (sessionData == null) return null;

      final session = Session.fromJson(sessionData).copyWith(projectId: projectId);
      _sessionMap[session.id] = session;

      final list = _sessionsByProject.putIfAbsent(projectId, () => []);
      list.insert(0, session);
      if (_currentProjectId == projectId) {
        _currentSessions = List.from(list);
      }

      notifyListeners();
      return session;
    } catch (e) {
      _error = '创建会话失败: $e';
      notifyListeners();
      return null;
    }
  }

  /// 加载会话消息历史
  Future<List<Message>> loadMessages({
    required String sessionId,
    int limit = 100,
    String? before,
  }) async {
    if (!_ws.isReady) {
      return _messagesBySession[sessionId] ?? [];
    }

    try {
      final response = await _ws.sendRequest({
        'type': 'session.messages',
        'sessionId': sessionId,
        'limit': limit,
        if (before != null) 'before': before,
      });

      final messagesRaw = response['messages'] as List? ?? [];
      final messages = messagesRaw
          .map((m) => Message.fromJson(m as Map<String, dynamic>))
          .toList();

      _messagesBySession[sessionId] = messages;
      notifyListeners();
      return messages;
    } catch (e) {
      _error = '加载消息失败: $e';
      notifyListeners();
      return _messagesBySession[sessionId] ?? [];
    }
  }

  /// 发送消息（流式响应）
  ///
  /// 会立即在消息列表中添加用户消息和占位的 AI 消息，
  /// 后续通过流式事件更新 AI 消息内容
  Future<bool> sendMessage({
    required String sessionId,
    required String content,
    String? agent,
  }) async {
    if (!_ws.isReady) {
      _error = '未连接到服务器';
      notifyListeners();
      return false;
    }

    final messages = _messagesBySession.putIfAbsent(sessionId, () => []);

    // 添加用户消息
    final userMessageId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final userMessage = Message(
      id: userMessageId,
      sessionId: sessionId,
      role: MessageRole.user,
      parts: [MessagePart.text(id: '${userMessageId}_p1', text: content)],
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    messages.add(userMessage);

    // 添加占位的 AI 消息
    final assistantMessageId = 'ai_${DateTime.now().millisecondsSinceEpoch}';
    final assistantMessage = Message(
      id: assistantMessageId,
      sessionId: sessionId,
      role: MessageRole.assistant,
      parts: [],
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    messages.add(assistantMessage);

    // 更新会话状态为处理中
    final session = _sessionMap[sessionId];
    if (session != null) {
      _sessionMap[sessionId] =
          session.copyWith(status: SessionStatus.processing);
      _updateSessionInList(sessionId, _sessionMap[sessionId]!);
    }

    notifyListeners();

    // 发送到服务器
    try {
      _ws.sendMessage({
        'type': 'chat',
        'sessionId': sessionId,
        'content': content,
        if (agent != null) 'agent': agent,
        'requestId': assistantMessageId,
      });
      return true;
    } catch (e) {
      _error = '发送消息失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 中止会话
  Future<bool> abortSession(String sessionId) async {
    if (!_ws.isReady) return false;

    try {
      await _ws.sendRequest({
        'type': 'session.abort',
        'sessionId': sessionId,
      });

      final session = _sessionMap[sessionId];
      if (session != null) {
        _sessionMap[sessionId] =
            session.copyWith(status: SessionStatus.idle);
        _updateSessionInList(sessionId, _sessionMap[sessionId]!);
        notifyListeners();
      }
      return true;
    } catch (e) {
      _error = '中止会话失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 删除会话
  Future<bool> deleteSession(String sessionId) async {
    if (!_ws.isReady) return false;

    try {
      await _ws.sendRequest({
        'type': 'session.delete',
        'sessionId': sessionId,
      });

      _sessionMap.remove(sessionId);
      _messagesBySession.remove(sessionId);

      for (final entry in _sessionsByProject.entries) {
        entry.value.removeWhere((s) => s.id == sessionId);
      }

      if (_currentProjectId != null) {
        _currentSessions =
            List.from(_sessionsByProject[_currentProjectId] ?? []);
      }

      notifyListeners();
      return true;
    } catch (e) {
      _error = '删除会话失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 清除错误
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// 清除指定会话的消息缓存
  void clearMessages(String sessionId) {
    _messagesBySession.remove(sessionId);
    notifyListeners();
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }
}
