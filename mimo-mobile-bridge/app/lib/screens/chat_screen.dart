import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../models/session.dart';
import '../services/session_service.dart';
import '../services/notification_service.dart';
import '../widgets/capsule_notification.dart';
import '../widgets/message_bubble.dart';

/// 对话界面
///
/// 显示消息流和工具执行卡片，底部输入框
/// 支持流式接收 AI 响应
class ChatScreen extends StatefulWidget {
  final Project project;
  final Session session;

  const ChatScreen({
    super.key,
    required this.project,
    required this.session,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMessages();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 加载消息历史
  Future<void> _loadMessages() async {
    final sessionService = context.read<SessionService>();
    await sessionService.loadMessages(sessionId: widget.session.id);
    _scrollToBottom();
  }

  /// 滚动到底部
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 发送消息
  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    _inputController.clear();

    final sessionService = context.read<SessionService>();
    final success = await sessionService.sendMessage(
      sessionId: widget.session.id,
      content: text,
    );

    if (success) {
      _scrollToBottom();
    }

    if (mounted) {
      setState(() {
        _isSending = false;
      });
    }
  }

  /// 中止当前会话
  Future<void> _abortSession() async {
    final sessionService = context.read<SessionService>();
    await sessionService.abortSession(widget.session.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildAppBar(),
                Expanded(child: _buildMessageList()),
                _buildInputArea(),
              ],
            ),
            // 胶囊通知层
            _buildCapsuleLayer(),
          ],
        ),
      ),
    );
  }

  /// 构建顶部应用栏
  Widget _buildAppBar() {
    final isProcessing =
        widget.session.status == SessionStatus.processing;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0x14FFFFFF), width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.session.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isProcessing) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF4F8CFF)),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  widget.project.name,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isProcessing)
            IconButton(
              icon: const Icon(Icons.stop, color: Color(0xFFFF4757)),
              onPressed: _abortSession,
              tooltip: '中止',
            ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            onPressed: () => _showMenu(context),
          ),
        ],
      ),
    );
  }

  /// 显示菜单
  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A25),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.refresh, color: Color(0xFF4F8CFF)),
              title: const Text('刷新消息'),
              onTap: () {
                Navigator.pop(context);
                _loadMessages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.stop, color: Color(0xFFFF4757)),
              title: const Text('中止当前任务'),
              onTap: () {
                Navigator.pop(context);
                _abortSession();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 构建消息列表
  Widget _buildMessageList() {
    return Consumer<SessionService>(
      builder: (context, service, _) {
        final messages = service.messagesFor(widget.session.id);

        if (messages.isEmpty) {
          return _buildEmptyView();
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            // 监听最后一条消息，自动滚动
            if (index == messages.length - 1) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToBottom();
              });
            }
            return MessageBubble(message: message);
          },
        );
      },
    );
  }

  /// 构建空视图
  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4F8CFF), Color(0xFFA855F7)],
                ),
              ),
              child: const Center(
                child: Icon(Icons.chat, color: Colors.white, size: 28),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '开始对话',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '向 AI 助手发送消息开始编码',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建输入区域
  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF12121A),
        border: Border(
          top: BorderSide(color: Color(0x14FFFFFF), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 输入框
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: _inputController,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: '输入消息...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // 发送按钮
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _isSending || _inputController.text.trim().isEmpty
                    ? LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.2),
                          Colors.white.withValues(alpha: 0.1),
                        ],
                      )
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF4F8CFF), Color(0xFFA855F7)],
                      ),
              ),
              child: IconButton(
                icon: _isSending
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withValues(alpha: 0.5)),
                        ),
                      )
                    : const Icon(Icons.arrow_upward, color: Colors.white),
                onPressed: _isSending ? null : _sendMessage,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建胶囊通知层
  Widget _buildCapsuleLayer() {
    return Consumer<NotificationService>(
      builder: (context, notifService, _) {
        final notifications = notifService.notifications;
        if (notifications.isEmpty) return const SizedBox.shrink();

        final visible =
            notifications.take(NotificationService.maxVisible).toList();

        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Column(
              children: visible
                  .map((notif) => CapsuleNotificationWidget(
                        data: notif,
                        service: notifService,
                        onDismiss: () => notifService.dismiss(notif.id),
                      ))
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}
