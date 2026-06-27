import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../services/project_service.dart';
import '../services/websocket_service.dart';
import '../services/notification_service.dart';
import '../widgets/capsule_notification.dart';
import 'connection_screen.dart';
import 'session_list_screen.dart';

/// 项目列表界面（首页）
///
/// 显示电脑端已打开的项目列表
/// - 每个项目卡片显示：名称、路径、会话数、分支、最后活跃时间
/// - 当前项目有特殊标记
/// - 点击项目进入会话列表
/// - 手机端无法创建新项目
class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  @override
  void initState() {
    super.initState();
    // 初始化后加载数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkConnection();
      _loadData();
    });
  }

  /// 检查连接状态
  void _checkConnection() {
    final ws = context.read<WebSocketService>();
    if (!ws.isReady) {
      // 未连接，跳转到连接界面
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ConnectionScreen()),
      );
    }
  }

  /// 加载数据
  Future<void> _loadData() async {
    final projectService = context.read<ProjectService>();
    await projectService.refresh();
  }

  /// 刷新数据
  Future<void> _handleRefresh() async {
    final projectService = context.read<ProjectService>();
    await projectService.refresh();
  }

  /// 进入项目会话列表
  void _enterProject(Project project) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionListScreen(project: project),
      ),
    );
  }

  /// 重新连接
  Future<void> _reconnect() async {
    final ws = context.read<WebSocketService>();
    if (!ws.isReady) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ConnectionScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            _buildMainContent(),
            // 胶囊通知层
            _buildCapsuleLayer(),
          ],
        ),
      ),
    );
  }

  /// 构建主内容
  Widget _buildMainContent() {
    return Column(
      children: [
        _buildAppBar(),
        Expanded(
          child: Consumer<ProjectService>(
            builder: (context, service, _) {
              if (service.isLoading && service.projects.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (service.error != null && service.projects.isEmpty) {
                return _buildErrorView(service.error!, service.clearError);
              }

              if (service.projects.isEmpty) {
                return _buildEmptyView();
              }

              return RefreshIndicator(
                onRefresh: _handleRefresh,
                color: const Color(0xFF4F8CFF),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: service.projects.length,
                  itemBuilder: (context, index) {
                    final project = service.projects[index];
                    return _ProjectCard(
                      project: project,
                      onTap: () => _enterProject(project),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 构建顶部应用栏
  Widget _buildAppBar() {
    return Consumer<WebSocketService>(
      builder: (context, ws, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              // Logo
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF4F8CFF), Color(0xFFA855F7)],
                  ),
                ),
                child: const Center(
                  child: Text(
                    'M',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '我的项目',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // 连接状态
              _buildConnectionStatus(ws),
              const SizedBox(width: 8),
              // 刷新按钮
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white70),
                onPressed: _handleRefresh,
              ),
              // 设置按钮
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white70),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ConnectionScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建连接状态指示器
  Widget _buildConnectionStatus(WebSocketService ws) {
    final isReady = ws.isReady;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isReady ? const Color(0xFF00D68F) : const Color(0xFFFFAA00))
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isReady ? const Color(0xFF00D68F) : const Color(0xFFFFAA00),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isReady ? '已连接' : '连接中',
            style: TextStyle(
              color: isReady ? const Color(0xFF00D68F) : const Color(0xFFFFAA00),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
              Icons.folder_off_outlined,
              size: 64,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            const Text(
              '暂无项目',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请在电脑端 MiMoCode 中打开项目',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: _handleRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建错误视图
  Widget _buildErrorView(String error, VoidCallback onRetry) {
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _handleRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: _reconnect,
                  icon: const Icon(Icons.link),
                  label: const Text('重新连接'),
                ),
              ],
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

        // 限制显示数量
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

/// 项目卡片
class _ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;

  const _ProjectCard({required this.project, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: project.isCurrent
            ? const Color(0x1400D68F) // 绿色半透明
            : const Color(0xFF1A1A25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: project.isCurrent
              ? const Color(0xFF00D68F)
              : Colors.transparent,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头部：项目名 + 当前标记
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            project.directory,
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
                    if (project.isCurrent) _buildCurrentBadge(),
                  ],
                ),
                const SizedBox(height: 12),
                // 统计信息
                Container(
                  padding: const EdgeInsets.only(top: 12),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Color(0x14FFFFFF), width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      _buildStat(
                        Icons.chat_bubble_outline,
                        '${project.sessionCount} 个会话',
                      ),
                      const SizedBox(width: 16),
                      _buildStat(
                        Icons.access_time,
                        _formatLastActive(project.lastActiveAt),
                      ),
                      if (project.branch != null &&
                          project.branch!.isNotEmpty) ...[
                        const SizedBox(width: 16),
                        _buildStat(
                          Icons.call_split,
                          project.branch!,
                        ),
                      ],
                      const Spacer(),
                      Icon(
                        Icons.chevron_right,
                        color: Colors.white.withValues(alpha: 0.3),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 当前项目标记
  Widget _buildCurrentBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF00D68F).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        '当前',
        style: TextStyle(
          color: Color(0xFF00D68F),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 构建统计项
  Widget _buildStat(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.white.withValues(alpha: 0.5)),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// 格式化最后活跃时间
  String _formatLastActive(int timestamp) {
    if (timestamp == 0) return '未知';
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = now - timestamp;
    final minutes = diff ~/ 60000;
    final hours = minutes ~/ 60;
    final days = hours ~/ 24;

    if (minutes < 1) return '刚刚';
    if (minutes < 60) return '$minutes 分钟前';
    if (hours < 24) return '$hours 小时前';
    if (days < 7) return '$days 天前';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${dt.month}/${dt.day}';
  }
}
