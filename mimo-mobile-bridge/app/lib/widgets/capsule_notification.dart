import 'package:flutter/material.dart';

import '../models/notification.dart';
import '../services/notification_service.dart';

/// 胶囊通知组件
///
/// 类似 iOS Dynamic Island 的悬浮通知，支持展开/收起
/// - 收起状态：图标 + 标题 + 快捷动作按钮
/// - 展开状态：详情 + 进度条 + 所有按钮
class CapsuleNotificationWidget extends StatefulWidget {
  final CapsuleNotification data;
  final NotificationService? service;

  /// 点击通知的回调（用于切换会话等）
  final VoidCallback? onTap;

  /// 关闭通知的回调
  final VoidCallback? onDismiss;

  const CapsuleNotificationWidget({
    super.key,
    required this.data,
    this.service,
    this.onTap,
    this.onDismiss,
  });

  @override
  State<CapsuleNotificationWidget> createState() =>
      _CapsuleNotificationWidgetState();
}

class _CapsuleNotificationWidgetState extends State<CapsuleNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _expandAnimation;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
    widget.onTap?.call();
  }

  /// 处理快捷动作点击
  void _handleQuickAction(QuickAction action) {
    // 权限请求类型：通过通知服务发送回复
    if (widget.data.type == CapsuleType.permissionRequest &&
        action.reply != null) {
      widget.service?.handlePermissionAction(widget.data.id, action.reply!);
    }

    // 中止类型
    if (action.type == QuickActionType.abort) {
      widget.service?.abortSession(widget.data.sessionId);
    }

    // 查看详情：展开通知
    if (action.type == QuickActionType.view) {
      if (!_isExpanded) _toggleExpand();
      return;
    }

    // 忽略/确认：关闭通知
    if (action.type == QuickActionType.confirm ||
        action.type == QuickActionType.deny) {
      widget.onDismiss?.call();
    }
  }

  /// 处理标准动作点击
  void _handleAction(CapsuleAction action) {
    // 中止动作
    if (action.id == 'abort') {
      widget.service?.abortSession(widget.data.sessionId);
    }
    // 查看详情：保持展开
    if (action.id == 'details' || action.id == 'view') {
      if (!_isExpanded) _toggleExpand();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, _) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E1E2E), Color(0xFF2A2A3E)],
            ),
            borderRadius: BorderRadius.circular(_isExpanded ? 16 : 28),
            border: Border.all(color: _getBorderColor(), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_isExpanded ? 16 : 28),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toggleExpand,
                onLongPress: _showContextMenu,
                child: _isExpanded ? _buildExpanded() : _buildCollapsed(),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 获取边框颜色
  Color _getBorderColor() {
    switch (widget.data.status) {
      case CapsuleStatus.working:
        return const Color(0x4D4F8CFF); // 蓝色半透明
      case CapsuleStatus.waiting:
        return const Color(0x4DFFAA00); // 橙色半透明
      case CapsuleStatus.completed:
        return const Color(0x4D00D68F); // 绿色半透明
      case CapsuleStatus.error:
        return const Color(0x4DFF4757); // 红色半透明
      default:
        return const Color(0x14FFFFFF); // 白色低透明
    }
  }

  /// 构建收起状态
  Widget _buildCollapsed() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 主要内容行
          Row(
            children: [
              _buildStatusIcon(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.data.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.data.subtitle != null)
                      Text(
                        widget.data.subtitle!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // 进度指示器
              if (widget.data.progress != null) ...[
                const SizedBox(width: 8),
                _buildProgressIndicator(),
              ],
              // 角标
              if (widget.data.badge != null && widget.data.badge! > 0) ...[
                const SizedBox(width: 8),
                _buildBadge(),
              ],
            ],
          ),
          // 快捷动作按钮
          if (widget.data.quickActions.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildQuickActions(),
          ],
        ],
      ),
    );
  }

  /// 构建展开状态
  Widget _buildExpanded() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题行
          Row(
            children: [
              _buildStatusIcon(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.data.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (widget.data.subtitle != null)
                      Text(
                        widget.data.subtitle!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (widget.data.dismissible)
                IconButton(
                  icon: Icon(Icons.close,
                      color: Colors.white.withValues(alpha: 0.7), size: 18),
                  onPressed: widget.onDismiss,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          // 项目名称上下文
          if (widget.data.projectName != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.folder_outlined,
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.5)),
                const SizedBox(width: 4),
                Text(
                  widget.data.projectName!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
          // 进度条
          if (widget.data.progress != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (widget.data.progress! / 100).clamp(0.0, 1.0),
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF4F8CFF)),
                minHeight: 3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.data.progress!.toStringAsFixed(0)}%',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
          // 快捷动作按钮
          if (widget.data.quickActions.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildQuickActions(),
          ],
          // 标准动作按钮
          if (widget.data.actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: widget.data.actions.map((action) {
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _buildActionButton(action),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建状态图标
  Widget _buildStatusIcon() {
    IconData iconData;
    Color color;

    switch (widget.data.status) {
      case CapsuleStatus.working:
        iconData = Icons.sync;
        color = const Color(0xFF4F8CFF);
        break;
      case CapsuleStatus.waiting:
        iconData = Icons.hourglass_empty;
        color = const Color(0xFFFFAA00);
        break;
      case CapsuleStatus.completed:
        iconData = Icons.check_circle;
        color = const Color(0xFF00D68F);
        break;
      case CapsuleStatus.error:
        iconData = Icons.error;
        color = const Color(0xFFFF4757);
        break;
      default:
        iconData = Icons.info;
        color = Colors.white.withValues(alpha: 0.5);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: widget.data.status == CapsuleStatus.working
          ? SizedBox(
              key: ValueKey(widget.data.status),
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          : Icon(iconData, color: color, size: 18,
              key: ValueKey(widget.data.status)),
    );
  }

  /// 构建进度指示器（圆形小进度）
  Widget _buildProgressIndicator() {
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: ((widget.data.progress ?? 0) / 100).clamp(0.0, 1.0),
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4F8CFF)),
            strokeWidth: 2.5,
          ),
          Text(
            '${widget.data.progress?.toStringAsFixed(0) ?? 0}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建角标
  Widget _buildBadge() {
    final count = widget.data.badge!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4757),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 构建快捷动作按钮组
  Widget _buildQuickActions() {
    return Row(
      children: widget.data.quickActions.map((action) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: action == widget.data.quickActions.last ? 0 : 8,
            ),
            child: _buildQuickActionButton(action),
          ),
        );
      }).toList(),
    );
  }

  /// 构建单个快捷动作按钮
  Widget _buildQuickActionButton(QuickAction action) {
    final isPrimary = action.primary;
    final color = _getQuickActionColor(action.type, isPrimary);

    return ElevatedButton.icon(
      onPressed: () => _handleQuickAction(action),
      icon: _getQuickActionIcon(action, isPrimary),
      label: Text(
        action.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isPrimary ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: isPrimary ? Colors.white : Colors.white.withValues(alpha: 0.9),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        elevation: 0,
      ),
    );
  }

  /// 获取快捷动作图标
  Widget _getQuickActionIcon(QuickAction action, bool isPrimary) {
    final color = isPrimary ? Colors.white : Colors.white.withValues(alpha: 0.9);
    IconData iconData;

    switch (action.type) {
      case QuickActionType.confirm:
        iconData = Icons.check;
        break;
      case QuickActionType.deny:
      case QuickActionType.reject:
        iconData = Icons.close;
        break;
      case QuickActionType.once:
        iconData = Icons.looks_one_outlined;
        break;
      case QuickActionType.always:
        iconData = Icons.check_circle_outline;
        break;
      case QuickActionType.view:
        iconData = Icons.visibility_outlined;
        break;
      case QuickActionType.abort:
        iconData = Icons.stop_outlined;
        break;
    }

    return Icon(iconData, size: 14, color: color);
  }

  /// 获取快捷动作按钮颜色
  Color _getQuickActionColor(QuickActionType type, bool isPrimary) {
    if (isPrimary) {
      switch (type) {
        case QuickActionType.confirm:
        case QuickActionType.once:
        case QuickActionType.always:
          return const Color(0xFF4F8CFF);
        case QuickActionType.deny:
        case QuickActionType.reject:
        case QuickActionType.abort:
          return const Color(0xFFFF4757);
        case QuickActionType.view:
          return const Color(0xFF4F8CFF);
      }
    }

    // 非主要按钮：半透明背景
    switch (type) {
      case QuickActionType.deny:
      case QuickActionType.reject:
        return const Color(0x1AFF4757);
      case QuickActionType.always:
        return const Color(0x1A00D68F);
      default:
        return Colors.white.withValues(alpha: 0.08);
    }
  }

  /// 构建标准动作按钮
  Widget _buildActionButton(CapsuleAction action) {
    Color color;
    switch (action.type) {
      case CapsuleActionType.primary:
        color = const Color(0xFF4F8CFF);
        break;
      case CapsuleActionType.destructive:
        color = const Color(0xFFFF4757);
        break;
      case CapsuleActionType.secondary:
        color = Colors.white.withValues(alpha: 0.08);
        break;
    }

    return ElevatedButton(
      onPressed: () => _handleAction(action),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: action.type == CapsuleActionType.secondary
            ? Colors.white
            : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        elevation: 0,
      ),
      child: Text(
        action.label,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  /// 显示长按上下文菜单
  void _showContextMenu() {
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
              leading: const Icon(Icons.open_in_new, color: Color(0xFF4F8CFF)),
              title: const Text('切换到此会话'),
              onTap: () {
                Navigator.pop(context);
                widget.onTap?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off, color: Color(0xFFFFAA00)),
              title: const Text('静音此会话通知'),
              onTap: () {
                Navigator.pop(context);
                widget.service?.dismissSession(widget.data.sessionId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.clear, color: Color(0xFFFF4757)),
              title: const Text('清除此通知'),
              onTap: () {
                Navigator.pop(context);
                widget.onDismiss?.call();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
