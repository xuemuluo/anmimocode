import 'package:flutter/material.dart';

/// 权限确认弹窗
///
/// 显示操作类型、目标文件、所属项目、所属会话
/// 三个按钮：仅此一次（主色）、始终允许（绿色）、拒绝（红色）
class PermissionDialog extends StatefulWidget {
  /// 操作类型（如"写入文件"）
  final String actionType;

  /// 目标文件路径
  final String targetFile;

  /// 所属项目名称
  final String projectName;

  /// 所属会话标题
  final String sessionTitle;

  /// 详细描述（可选）
  final String? description;

  /// 是否为危险操作
  final bool isDangerous;

  const PermissionDialog({
    super.key,
    required this.actionType,
    required this.targetFile,
    required this.projectName,
    required this.sessionTitle,
    this.description,
    this.isDangerous = false,
  });

  /// 显示权限弹窗
  ///
  /// 返回 'once' | 'always' | 'reject' | null（用户关闭弹窗）
  static Future<String?> show(
    BuildContext context, {
    required String actionType,
    required String targetFile,
    required String projectName,
    required String sessionTitle,
    String? description,
    bool isDangerous = false,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PermissionDialog(
        actionType: actionType,
        targetFile: targetFile,
        projectName: projectName,
        sessionTitle: sessionTitle,
        description: description,
        isDangerous: isDangerous,
      ),
    );
  }

  @override
  State<PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<PermissionDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A25),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: widget.isDangerous
                  ? const Color(0xFFFF4757).withValues(alpha: 0.3)
                  : const Color(0xFFFFAA00).withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIcon(),
              const SizedBox(height: 16),
              _buildTitle(),
              const SizedBox(height: 8),
              _buildDescription(),
              const SizedBox(height: 20),
              _buildDetails(),
              const SizedBox(height: 20),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建图标
  Widget _buildIcon() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.isDangerous
              ? [const Color(0xFFFF4757), const Color(0xFFC0392B)]
              : [const Color(0xFFFFAA00), const Color(0xFFFF4757)],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.warning_amber_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  /// 构建标题
  Widget _buildTitle() {
    return Text(
      widget.isDangerous ? '危险操作确认' : '请求${widget.actionType}权限',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      textAlign: TextAlign.center,
    );
  }

  /// 构建描述
  Widget _buildDescription() {
    final desc = widget.description ??
        (widget.isDangerous
            ? 'AI 助手即将执行危险操作，请谨慎确认'
            : 'AI 助手想要${widget.actionType}，请确认是否允许');
    return Text(
      desc,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.7),
        fontSize: 13,
        height: 1.4,
      ),
      textAlign: TextAlign.center,
    );
  }

  /// 构建详情
  Widget _buildDetails() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildDetailRow('操作类型', widget.actionType),
          const Divider(height: 16, color: Color(0x14FFFFFF)),
          _buildDetailRow('目标文件', widget.targetFile),
          const Divider(height: 16, color: Color(0x14FFFFFF)),
          _buildDetailRow('所属项目', widget.projectName),
          const Divider(height: 16, color: Color(0x14FFFFFF)),
          _buildDetailRow('所属会话', widget.sessionTitle),
        ],
      ),
    );
  }

  /// 构建详情行
  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// 构建按钮组
  Widget _buildActions() {
    return Column(
      children: [
        // 仅此一次（主色）
        _buildButton(
          label: '✓ 仅此一次',
          color: const Color(0xFF4F8CFF),
          textColor: Colors.white,
          onTap: () => Navigator.of(context).pop('once'),
        ),
        const SizedBox(height: 10),
        // 始终允许（绿色）
        _buildButton(
          label: '始终允许此操作',
          color: const Color(0xFF00D68F).withValues(alpha: 0.15),
          textColor: const Color(0xFF00D68F),
          onTap: () => Navigator.of(context).pop('always'),
        ),
        const SizedBox(height: 10),
        // 拒绝（红色）
        _buildButton(
          label: '拒绝',
          color: const Color(0xFFFF4757).withValues(alpha: 0.1),
          textColor: const Color(0xFFFF4757),
          onTap: () => Navigator.of(context).pop('reject'),
        ),
      ],
    );
  }

  /// 构建单个按钮
  Widget _buildButton({
    required String label,
    required Color color,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
