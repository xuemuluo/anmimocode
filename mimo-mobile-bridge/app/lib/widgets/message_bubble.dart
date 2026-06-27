import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/session.dart';
import 'tool_card.dart';

/// 消息气泡组件
///
/// 显示用户消息（右对齐，渐变背景）或 AI 消息（左对齐，卡片背景）
/// AI 消息支持 Markdown 渲染和工具执行卡片
class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  bool get isUser => message.role == MessageRole.user;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) _buildAvatar(),
          if (!isUser) const SizedBox(width: 10),
          Flexible(child: _buildContent()),
          if (isUser) const SizedBox(width: 10),
          if (isUser) _buildAvatar(),
        ],
      ),
    );
  }

  /// 构建头像
  Widget _buildAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isUser
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF00D68F), Color(0xFF00B894)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4F8CFF), Color(0xFFA855F7)],
              ),
      ),
      child: Center(
        child: Text(
          isUser ? 'U' : 'M',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// 构建消息内容
  Widget _buildContent() {
    final textContent = message.textContent;
    final toolParts = message.toolParts;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // 文本气泡
          if (textContent.isNotEmpty) _buildBubble(textContent),
          // 工具执行卡片
          ...toolParts.map((part) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ToolCard(part: part),
              )),
          // 时间戳
          if (message.createdAt > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
              child: Text(
                _formatTime(message.createdAt),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                textAlign: isUser ? TextAlign.right : TextAlign.left,
              ),
            ),
        ],
      ),
    );
  }

  /// 构建文本气泡
  Widget _buildBubble(String text) {
    if (isUser) {
      // 用户消息：渐变背景
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4F8CFF), Color(0xFFA855F7)],
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      );
    }

    // AI 消息：使用 Markdown 渲染
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A25),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: MarkdownBody(
        data: text,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.5,
          ),
          code: TextStyle(
            backgroundColor: Colors.black.withValues(alpha: 0.3),
            color: const Color(0xFFA855F7),
            fontSize: 13,
          ),
          codeblockDecoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
          ),
          codeblockPadding: const EdgeInsets.all(12),
          h1: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          h2: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          h3: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          listBullet: const TextStyle(color: Color(0xFF4F8CFF)),
          a: const TextStyle(color: Color(0xFF4F8CFF)),
          blockquoteDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: Color(0xFF4F8CFF), width: 3),
            ),
          ),
        ),
      ),
    );
  }

  /// 格式化时间
  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
