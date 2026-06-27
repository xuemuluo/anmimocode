import 'package:flutter/material.dart';

import '../models/session.dart';

/// 工具执行卡片组件
///
/// 显示工具名、执行状态、输出内容
class ToolCard extends StatelessWidget {
  final MessagePart part;

  const ToolCard({super.key, required this.part});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF222233),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: _getStatusColor(),
            width: 3,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            if (_hasOutput()) ...[
              const SizedBox(height: 8),
              _buildOutput(),
            ],
            if (_hasError()) ...[
              const SizedBox(height: 8),
              _buildError(),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建头部
  Widget _buildHeader() {
    return Row(
      children: [
        // 工具图标
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF4F8CFF).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Icon(
              _getToolIcon(),
              size: 14,
              color: const Color(0xFF4F8CFF),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // 工具名/标题
        Expanded(
          child: Text(
            part.toolTitle ?? part.toolName ?? '工具',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4F8CFF),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // 状态标签
        _buildStatusBadge(),
      ],
    );
  }

  /// 构建状态徽章
  Widget _buildStatusBadge() {
    final status = part.toolStatus ?? ToolStatus.pending;
    final color = _getStatusColor();
    final label = status.label;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: status == ToolStatus.running
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 8,
                  height: 8,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            )
          : Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
    );
  }

  /// 构建输出
  Widget _buildOutput() {
    final output = part.toolOutput ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        output,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: Colors.white.withValues(alpha: 0.7),
          height: 1.4,
        ),
        maxLines: 5,
      ),
    );
  }

  /// 构建错误信息
  Widget _buildError() {
    final error = part.toolError ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4757).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFFF4757).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: SelectableText(
        error,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: const Color(0xFFFF4757).withValues(alpha: 0.9),
          height: 1.4,
        ),
        maxLines: 5,
      ),
    );
  }

  /// 是否有输出
  bool _hasOutput() {
    return part.toolOutput != null && part.toolOutput!.isNotEmpty;
  }

  /// 是否有错误
  bool _hasError() {
    return part.toolError != null && part.toolError!.isNotEmpty;
  }

  /// 获取状态颜色
  Color _getStatusColor() {
    final status = part.toolStatus ?? ToolStatus.pending;
    switch (status) {
      case ToolStatus.pending:
        return const Color(0xFF8B8B9E);
      case ToolStatus.running:
        return const Color(0xFF4F8CFF);
      case ToolStatus.completed:
        return const Color(0xFF00D68F);
      case ToolStatus.error:
        return const Color(0xFFFF4757);
    }
  }

  /// 根据工具名获取图标
  IconData _getToolIcon() {
    final name = part.toolName ?? '';
    // 根据工具名匹配图标
    if (name.contains('read') || name.contains('file')) {
      return Icons.description_outlined;
    }
    if (name.contains('edit') || name.contains('write')) {
      return Icons.edit_outlined;
    }
    if (name.contains('bash') || name.contains('shell')) {
      return Icons.terminal;
    }
    if (name.contains('grep') || name.contains('search')) {
      return Icons.search;
    }
    if (name.contains('glob')) {
      return Icons.folder_open_outlined;
    }
    if (name.contains('task') || name.contains('todo')) {
      return Icons.task_alt;
    }
    if (name.contains('lsp')) {
      return Icons.code;
    }
    if (name.contains('web')) {
      return Icons.language;
    }
    return Icons.build_outlined;
  }
}
