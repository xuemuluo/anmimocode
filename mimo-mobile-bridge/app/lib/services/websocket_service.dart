import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket 连接状态
enum WebSocketConnectionState {
  /// 未连接
  disconnected,

  /// 连接中
  connecting,

  /// 已连接
  connected,

  /// 认证中（已连接，正在发送配对码）
  authenticating,

  /// 认证完成，可正常通信
  ready,

  /// 出错
  error,
}

/// WebSocket 服务
///
/// 管理与电脑端 MiMoCode 插件的 WebSocket 连接，提供：
/// - 连接管理（连接、断开、自动重连）
/// - 配对码认证
/// - JSON 消息收发
/// - 流式消息接收
/// - 请求-响应匹配（基于 id 字段）
class WebSocketService {
  /// 默认端口（与电脑端插件配置一致）
  static const int defaultPort = 8765;

  /// 连接超时时间
  static const Duration connectTimeout = Duration(seconds: 10);

  /// 重连间隔
  static const Duration reconnectInterval = Duration(seconds: 3);

  /// 最大重连次数
  static const int maxReconnectAttempts = 5;

  WebSocketChannel? _channel;

  /// 当前连接状态
  WebSocketConnectionState _state = WebSocketConnectionState.disconnected;
  WebSocketConnectionState get state => _state;

  /// 当前连接信息
  String _host = '';
  int _port = defaultPort;
  String _pairingCode = '';
  String get host => _host;
  int get port => _port;
  String get pairingCode => _pairingCode;

  /// 是否已就绪（已连接且认证完成）
  bool get isReady => _state == WebSocketConnectionState.ready;

  /// 是否已连接
  bool get isConnected =>
      _state == WebSocketConnectionState.connected ||
      _state == WebSocketConnectionState.authenticating ||
      _state == WebSocketConnectionState.ready;

  /// 重连计数
  int _reconnectAttempts = 0;

  /// 是否允许自动重连
  bool _autoReconnect = true;

  /// 消息流控制器
  ///
  /// 所有从服务器收到的消息都会通过这个流广播
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  /// 状态变化控制器
  final StreamController<WebSocketConnectionState> _stateController =
      StreamController.broadcast();
  Stream<WebSocketConnectionState> get stateStream => _stateController.stream;

  /// 错误流控制器
  final StreamController<String> _errorController =
      StreamController.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  /// 待处理的请求：key 为请求 id，value 为 Completer
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};

  /// 流式消息流控制器（按 sessionId 分组）
  ///
  /// key: sessionId, value: 该会话的事件流
  final Map<String, StreamController<Map<String, dynamic>>> _sessionStreams =
      {};

  /// 获取指定会话的事件流
  Stream<Map<String, dynamic>> sessionStream(String sessionId) {
    _sessionStreams[sessionId] ??= StreamController.broadcast();
    return _sessionStreams[sessionId]!.stream;
  }

  /// 订阅会话事件（返回流，关闭时自动清理）
  Stream<Map<String, dynamic>> subscribeSession(String sessionId) {
    return sessionStream(sessionId);
  }

  /// 更新状态
  void _setState(WebSocketConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) _stateController.add(newState);
  }

  /// 连接到服务器
  ///
  /// [host] 服务器 IP 地址
  /// [port] 端口号，默认 8765
  /// [pairingCode] 配对码，用于认证
  Future<void> connect({
    required String host,
    int port = defaultPort,
    required String pairingCode,
  }) async {
    if (_state == WebSocketConnectionState.connecting ||
        _state == WebSocketConnectionState.authenticating) {
      return;
    }

    _host = host;
    _port = port;
    _pairingCode = pairingCode;
    _autoReconnect = true;
    _reconnectAttempts = 0;

    await _doConnect();
  }

  /// 实际执行连接
  Future<void> _doConnect() async {
    _setState(WebSocketConnectionState.connecting);

    try {
      final uri = Uri.parse('ws://$_host:$_port');
      _channel = WebSocketChannel.connect(uri);

      // 监听消息
      _channel!.stream.listen(
        _onData,
        onError: (error) => _onError(error.toString()),
        onDone: _onDone,
      );

      _setState(WebSocketConnectionState.connected);

      // 发送配对码认证
      await _authenticate();
    } catch (e) {
      _onError('连接失败: $e');
    }
  }

  /// 发送配对码进行认证
  Future<void> _authenticate() async {
    _setState(WebSocketConnectionState.authenticating);

    try {
      // 发送认证消息
      _sendRaw({
        'type': 'auth',
        'pairingCode': _pairingCode,
        'client': 'mimo_mobile',
        'version': '0.1.0',
      });

      // 等待服务器响应（带超时）
      // 认证响应会在 _onData 中处理
      // 这里仅设置超时检查
      Future.delayed(const Duration(seconds: 5), () {
        if (_state == WebSocketConnectionState.authenticating) {
          _onError('认证超时');
        }
      });
    } catch (e) {
      _onError('认证失败: $e');
    }
  }

  /// 处理收到的消息
  void _onData(dynamic data) {
    if (data is String) {
      try {
        final message = jsonDecode(data) as Map<String, dynamic>;
        _handleMessage(message);
      } catch (e) {
        // 非 JSON 消息或解析失败，忽略
      }
    }
  }

  /// 处理消息分发
  void _handleMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;

    // 处理认证响应
    if (type == 'auth.success' || type == 'auth.ok') {
      _setState(WebSocketConnectionState.ready);
      _reconnectAttempts = 0;
    } else if (type == 'auth.failed' || type == 'auth.error') {
      _onError('认证失败: ${message['message'] ?? '配对码错误'}');
      _autoReconnect = false;
      disconnect();
      return;
    }

    // 广播到全局消息流
    if (!_messageController.isClosed) {
      _messageController.add(message);
    }

    // 处理请求-响应匹配
    final id = message['id'] as String?;
    if (id != null && _pendingRequests.containsKey(id)) {
      final completer = _pendingRequests.remove(id)!;
      if (type == 'error') {
        completer.completeError(
          WebSocketServiceException(
            code: message['code'] as String? ?? 'UNKNOWN',
            message: message['message'] as String? ?? '未知错误',
          ),
        );
      } else {
        completer.complete(message);
      }
    }

    // 按会话路由消息
    final sessionId = message['sessionId'] as String?;
    if (sessionId != null && _sessionStreams.containsKey(sessionId)) {
      _sessionStreams[sessionId]!.add(message);
    }
  }

  /// 错误处理
  void _onError(String error) {
    if (!_errorController.isClosed) {
      _errorController.add(error);
    }
    _setState(WebSocketConnectionState.error);
    _scheduleReconnect();
  }

  /// 连接断开处理
  void _onDone() {
    if (_state == WebSocketConnectionState.ready ||
        _state == WebSocketConnectionState.connected) {
      _setState(WebSocketConnectionState.disconnected);
    }
    _scheduleReconnect();
  }

  /// 调度重连
  void _scheduleReconnect() {
    if (!_autoReconnect) return;
    if (_reconnectAttempts >= maxReconnectAttempts) {
      _errorController.add('已达到最大重连次数 ($maxReconnectAttempts)');
      return;
    }

    _reconnectAttempts++;
    Future.delayed(reconnectInterval, () {
      if (_autoReconnect && _state != WebSocketConnectionState.ready) {
        _doConnect();
      }
    });
  }

  /// 发送原始消息（不等待响应）
  void _sendRaw(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  /// 发送消息（不等待响应）
  void sendMessage(Map<String, dynamic> message) {
    _sendRaw(message);
  }

  /// 发送请求并等待响应
  ///
  /// 自动生成 id 字段，返回响应消息
  Future<Map<String, dynamic>> sendRequest(
    Map<String, dynamic> message, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!isReady) {
      throw WebSocketServiceException(
        code: 'NOT_CONNECTED',
        message: 'WebSocket 未连接或未认证',
      );
    }

    final id = message['id'] as String? ?? _generateId();
    final request = {...message, 'id': id};

    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    _sendRaw(request);

    // 超时处理
    Future.delayed(timeout, () {
      if (_pendingRequests.containsKey(id)) {
        _pendingRequests.remove(id);
        if (!completer.isCompleted) {
          completer.completeError(
            WebSocketServiceException(
              code: 'TIMEOUT',
              message: '请求超时',
            ),
          );
        }
      }
    });

    return completer.future;
  }

  /// 生成唯一请求 ID
  String _generateId() {
    return 'req_${DateTime.now().millisecondsSinceEpoch}_'
        '${_pendingRequests.length}';
  }

  /// 主动断开连接
  void disconnect() {
    _autoReconnect = false;
    _channel?.sink.close();
    _channel = null;
    _setState(WebSocketConnectionState.disconnected);
  }

  /// 清理会话流
  void disposeSession(String sessionId) {
    _sessionStreams[sessionId]?.close();
    _sessionStreams.remove(sessionId);
  }

  /// 释放资源
  void dispose() {
    _autoReconnect = false;
    _channel?.sink.close();
    _channel = null;
    _messageController.close();
    _stateController.close();
    _errorController.close();
    for (final controller in _sessionStreams.values) {
      controller.close();
    }
    _sessionStreams.clear();
    _pendingRequests.clear();
  }
}

/// WebSocket 服务异常
class WebSocketServiceException implements Exception {
  final String code;
  final String message;

  const WebSocketServiceException({
    required this.code,
    required this.message,
  });

  @override
  String toString() => 'WebSocketServiceException($code): $message';
}
