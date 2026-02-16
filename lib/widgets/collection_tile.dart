import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 集合形状枚举
enum CollectionShape {
  square, // 方形（带圆角）
  circle, // 圆形
}

/// 通用集合展示 Tile（支持 `ValueNotifier<Uint8List?>` 缩略图）
///
/// 适用于：相册、人物、场景、地点等集合入口展示。
/// 缩略图来源统一为 `ValueNotifier<Uint8List?>`，与 [ThumbnailManager] 对接。
class CollectionTile extends StatelessWidget {
  /// 显示标题
  final String title;

  /// 副标题（如 "123 张照片"）
  final String? subtitle;

  /// 缩略图数据 notifier 列表（1 张 = 单封面，2~4 张 = 2x2 网格）
  final List<ValueNotifier<Uint8List?>> thumbnailNotifiers;

  /// 无缩略图时的默认图标
  final IconData defaultIcon;

  /// 形状（方形/圆形）
  final CollectionShape shape;

  /// 方形圆角半径
  final double borderRadius;

  /// 点击回调
  final VoidCallback? onTap;

  /// 长按回调
  final VoidCallback? onLongPress;

  const CollectionTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.thumbnailNotifiers,
    this.defaultIcon = Icons.photo_library,
    this.shape = CollectionShape.square,
    this.borderRadius = 12.0,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: shape == CollectionShape.circle
          ? BorderRadius.circular(999)
          : BorderRadius.circular(borderRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 缩略图区域
          AspectRatio(aspectRatio: 1, child: _buildThumbnailArea(context)),

          const SizedBox(height: 8),

          // 标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),

          // 副标题
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildThumbnailArea(BuildContext context) {
    if (thumbnailNotifiers.isEmpty) {
      return _buildPlaceholder(context);
    }

    if (thumbnailNotifiers.length == 1 || shape == CollectionShape.circle) {
      // 单封面
      return _buildClipped(
        context,
        _buildSingleThumb(context, thumbnailNotifiers.first),
      );
    }

    // 多封面 2x2 网格（最多 4 张）
    final count = thumbnailNotifiers.length.clamp(0, 4);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: count,
        itemBuilder: (context, index) {
          return _buildSingleThumb(context, thumbnailNotifiers[index]);
        },
      ),
    );
  }

  Widget _buildClipped(BuildContext context, Widget child) {
    if (shape == CollectionShape.circle) {
      return ClipOval(child: child);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: child,
    );
  }

  Widget _buildSingleThumb(
    BuildContext context,
    ValueNotifier<Uint8List?> notifier,
  ) {
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: notifier,
      builder: (context, bytes, child) {
        if (bytes == null) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: shape == CollectionShape.circle
            ? BorderRadius.circular(999)
            : BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        defaultIcon,
        size: 48,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
      ),
    );
  }
}
