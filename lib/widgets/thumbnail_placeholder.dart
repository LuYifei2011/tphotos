import 'package:flutter/material.dart';

/// 缩略图占位符状态
enum ThumbnailPlaceholderState {
  /// 加载中
  loading,

  /// 加载失败
  error,

  /// 空状态
  empty,
}

/// 统一的缩略图占位符组件
///
/// 为所有页面提供一致的加载、错误和空状态样式。
class ThumbnailPlaceholder extends StatelessWidget {
  /// 占位符状态
  final ThumbnailPlaceholderState state;

  /// 可选的自定义尺寸（loading 指示器）
  final double indicatorSize;

  /// 可选的自定义图标大小
  final double iconSize;

  /// 可选的自定义背景色
  final Color? backgroundColor;

  /// 可选的自定义消息
  final String? message;

  const ThumbnailPlaceholder({
    super.key,
    required this.state,
    this.indicatorSize = 16,
    this.iconSize = 24,
    this.backgroundColor,
    this.message,
  });

  /// 加载中占位符
  const ThumbnailPlaceholder.loading({
    super.key,
    this.indicatorSize = 16,
    this.iconSize = 24,
    this.backgroundColor,
    this.message,
  }) : state = ThumbnailPlaceholderState.loading;

  /// 错误占位符
  const ThumbnailPlaceholder.error({
    super.key,
    this.indicatorSize = 16,
    this.iconSize = 24,
    this.backgroundColor,
    this.message,
  }) : state = ThumbnailPlaceholderState.error;

  /// 空状态占位符
  const ThumbnailPlaceholder.empty({
    super.key,
    this.indicatorSize = 16,
    this.iconSize = 24,
    this.backgroundColor,
    this.message,
  }) : state = ThumbnailPlaceholderState.empty;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        backgroundColor ?? (isDark ? const Color(0xFF303030) : const Color(0xFFE0E0E0));

    return ColoredBox(
      color: bgColor,
      child: Center(
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (state) {
      case ThumbnailPlaceholderState.loading:
        return SizedBox(
          width: indicatorSize,
          height: indicatorSize,
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
      case ThumbnailPlaceholderState.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image,
              size: iconSize,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(
                message!,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        );
      case ThumbnailPlaceholderState.empty:
        return Icon(
          Icons.image_not_supported,
          size: iconSize,
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.3),
        );
    }
  }
}
