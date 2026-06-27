import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../models/session.dart';
import '../services/session_service.dart';
import '../services/notification_service.dart';
import '../widgets/capsule_notification.dart';
import 'chat_screen.dart';

/// 会话列表界面
///
/// 显示某项目下的所有会话，含"新建会话"按钮
/// 会话卡片显示：标题、预览、状态、消息数、Token数、费用
class SessionListScreen extends StatefulWidget {
  final Project project;

  const SessionListScreen({super.key, required this.project});

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSessions();
    });
  }

  /// 加载会话列表
  Future<void> _loadSessions() async {
    final sessionService = context.read<SessionService>();
    sessionService.setCurrentProject(widget.project.id);
    await sessionService.loadSessions(
      projectId: widget.project.id,
      directory: widget.project.directory,
    );
  }

  /// 刷新
  Future<void> _handleRefresh() async {
    await _loadSessions();
  }

  /// 新建会话
  Future<void> _createSession() async {
    final sessionService = context.read<SessionService>();
    final session = await sessionService.createSession(
      projectId: widget.project.id,
      workingDirectory: widget.project.directory,
    );
    if (session != null && mounted) {
      _enterChat(session);
    }
  }

  /// 进入对话界面
  void _enterChat(Session session) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          project: widget.project,
          session: session,
        ),
      ),
    );
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
                Expanded(
                  child: Consumer<SessionService>(
                    builder: (context, service, _) {
                      if (service.isLoading &&
                          service.currentSessions.isEmpty) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (service.error != null &&
                          service.currentSessions.isEmpty) {
                        return _buildErrorView(service.error!);
                      }

                      if (service.currentSessions.isEmpty) {
                        return _buildEmptyView();
                      }

                      return RefreshIndicator(
                        onRefresh: _handleRefresh,
                        color: const Color(0xFF4F8CFF),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: service.currentSessions.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return _buildNewSessionButton();
                            }
                            final session = service.currentSessions[index - 1];
                            return _SessionCard(
                              session: session,
                              onTap: () => _enterChat(session),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                Text(
                  widget.project.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.project.directory,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _handleRefresh,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            color: const Color(0xFF1A1A25),
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  _handleRefresh();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.white70, size: 18),
                    SizedBox(width: 8),
                    Text('刷新', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建新建会话按钮
  Widget _buildNewSessionButton() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      child: OutlinedButton.icon(
        onPressed: _createSession,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF4F8CFF),
          backgroundColor: const Color(0xFF4F8CFF).withValues(alpha: 0.05),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: const BorderSide(color: Color(0xFF4F8CFF), width: 1.5),
        ),
        icon: const Icon(Icons.add),
        label: const Text(
          '新建会话',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
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
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            const Text(
              '暂无会话',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击上方按钮创建新会话',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建错误视图
  Widget _buildErrorView(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Color(0xFFFF4757),
            ),
            const SizedBox(height: 16),
            const Text(
              '加载失败',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _handleRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
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

/// 会话卡片
class _SessionCard extends StatelessWidget {
  final Session session;
  final VoidCallback onTap;

  const _SessionCard({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isActive = session.status == SessionStatus.processing;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0x144F8CFF) // 蓝色半透明（活跃会话）
            : const Color(0xFF1A1A25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? const Color(0xFF4F8CFF) : Colors.transparent,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题行
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        session.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(session.updatedAt),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                // 预览
                if (session.preview != null && session.preview!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    session.preview!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                // 状态徽章
                const SizedBox(height: 10),
                _buildStatusBadge(),
                // 统计信息
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStat(Icons.chat_bubble_outline,
                        '${session.messageCount} 条'),
                    if (session.tokens != null) ...[
                      const SizedBox(width: 12),
                      _buildStat(Icons.token,
                          _formatNumber(session.tokens!.total)),
                    ],
                    if (session.cost != null) ...[
                      const SizedBox(width: 12),
                      _buildStat(Icons.attach_money,
                          '\$${session.cost!.toStringAsFixed(4)}'),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建状态徽章
  Widget _buildStatusBadge() {
    Color color;
    String label;

    switch (session.status) {
      case SessionStatus.processing:
        color = const Color(0xFF4F8CFF);
        label = '执行中';
        break;
      case SessionStatus.error:
        color = const Color(0xFFFF4757);
        label = '错误';
        break;
      case SessionStatus.idle:
        color = Colors.white.withValues(alpha: 0.3);
        label = '空闲';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (session.status == SessionStatus.processing)
            SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建统计项
  Widget _buildStat(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: Colors.white.withValues(alpha: 0.4)),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  /// 格式化数字（添加千分位）
  String _formatNumber(int num) {
    if (num < 1000) return num.toString();
    if (num < 1000000) return '${(num / 1000).toStringAsFixed(1)}K';
    return '${(num / 1000000).toStringAsFixed(1)}M';
  }

  /// 格式化时间
  String _formatTime(int timestamp) {
    if (timestamp == 0) return '';
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = now - timestamp;
    final minutes = diff ~/ 60000;
    final hours = minutes ~/ 60;
    final days = hours ~/ 24;

    if (minutes < 1) return '刚刚';
    if (minutes < 60) return '$minutes分钟前';
    if (hours < 24) return '$hours小时前';
    if (days < 7) return '$days天前';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${dt.month}/${dt.day}';
  }
}
