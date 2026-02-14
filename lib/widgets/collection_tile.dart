import 'package:flutter/material.dart';

/// 集合类型枚举
enum CollectionType {
  album,   // 相册
  folder,  // 文件夹
  people,  // 人物
  scene,   // 场景
  place,   // 地点
}

/// 集合形状枚举
enum CollectionShape {
  square,  // 方形（带圆角）
  circle,  // 圆形
}

/// 集合数据模型
class CollectionItem {
  /// 集合唯一标识
  final String id;

  /// 显示标题
  final String title;

  /// 缩略图 URL（可选）
  final String? thumbnailUrl;

  /// 集合内项目数量（可选）
  final int? itemCount;

  /// 默认图标（当无缩略图时使用）
  final IconData? defaultIcon;

  /// 集合类型
  final CollectionType type;

  CollectionItem({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.itemCount,
    this.defaultIcon,
    required this.type,
  });

  /// 获取默认图标（根据类型）
  IconData getDefaultIcon() {
    if (defaultIcon != null) return defaultIcon!;
    
    switch (type) {
      case CollectionType.album:
        return Icons.photo_library;
      case CollectionType.folder:
        return Icons.folder;
      case CollectionType.people:
        return Icons.person;
      case CollectionType.scene:
        return Icons.landscape;
      case CollectionType.place:
        return Icons.place;
    }
  }
}

/// 通用集合展示组件
class CollectionTile extends StatelessWidget {
  /// 集合数据
  final CollectionItem item;

  /// 形状（方形/圆形）
  final CollectionShape shape;

  /// 尺寸（宽高）
  final double size;

  /// 是否显示数量
  final bool showCount;

  /// 点击回调
  final VoidCallback? onTap;

  /// 长按回调
  final VoidCallback? onLongPress;

  /// 方形圆角半径
  final double borderRadius;

  /// 缩略图适应方式
  final BoxFit fit;

  const CollectionTile({
    Key? key,
    required this.item,
    this.shape = CollectionShape.square,
    this.size = 120.0,
    this.showCount = true,
    this.onTap,
    this.onLongPress,
    this.borderRadius = 8.0,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: shape == CollectionShape.circle
          ? BorderRadius.circular(size / 2)
          : BorderRadius.circular(borderRadius),
      child: Container(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 缩略图或默认图标
            _buildThumbnail(),
            
            const SizedBox(height: 8.0),
            
            // 标题
            _buildTitle(context),
            
            // 数量（可选）
            if (showCount && item.itemCount != null) ...[
              const SizedBox(height: 4.0),
              _buildCount(context),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建缩略图部分
  Widget _buildThumbnail() {
    final thumbnailWidget = item.thumbnailUrl != null
        ? _buildNetworkImage()
        : _buildDefaultIcon();

    return SizedBox(
      width: size,
      height: size,
      child: shape == CollectionShape.circle
          ? ClipOval(child: thumbnailWidget)
          : ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: thumbnailWidget,
            ),
    );
  }

  /// 构建网络图片
  Widget _buildNetworkImage() {
    return Image.network(
      item.thumbnailUrl!,
      width: size,
      height: size,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        // 加载失败时显示默认图标
        return _buildDefaultIcon();
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _buildPlaceholder(
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
              strokeWidth: 2.0,
            ),
          ),
        );
      },
    );
  }

  /// 构建默认图标
  Widget _buildDefaultIcon() {
    return _buildPlaceholder(
      child: Icon(
        item.getDefaultIcon(),
        size: size * 0.4,
        color: Colors.grey[600],
      ),
    );
  }

  /// 构建占位容器
  Widget _buildPlaceholder({required Widget child}) {
    return Container(
      width: size,
      height: size,
      color: Colors.grey[300],
      child: Center(child: child),
    );
  }

  /// 构建标题
  Widget _buildTitle(BuildContext context) {
    return Text(
      item.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 14.0,
        fontWeight: FontWeight.w500,
        color: Colors.black87,
      ),
    );
  }

  /// 构建数量显示
  Widget _buildCount(BuildContext context) {
    return Text(
      '${item.itemCount} 张',
      style: TextStyle(
        fontSize: 12.0,
        color: Colors.grey[600],
      ),
    );
  }
}

/// 集合网格组件
///
/// 用于批量展示多个集合，自动排列成网格布局。
///
/// 使用示例：
/// ```dart
/// CollectionGrid(
///   items: [
///     CollectionItem(...),
///     CollectionItem(...),
///   ],
///   crossAxisCount: 3,
///   shape: CollectionShape.square,
///   onTap: (item) => print('点击: ${item.title}'),
/// )
/// ```
class CollectionGrid extends StatelessWidget {
  /// 集合列表
  final List<CollectionItem> items;

  /// 每行数量
  final int crossAxisCount;

  /// 形状
  final CollectionShape shape;

  /// 是否显示数量
  final bool showCount;

  /// 点击回调
  final void Function(CollectionItem item)? onTap;

  /// 长按回调
  final void Function(CollectionItem item)? onLongPress;

  /// 网格间距
  final double spacing;

  /// 瓦片尺寸
  final double tileSize;

  const CollectionGrid({
    Key? key,
    required this.items,
    this.crossAxisCount = 3,
    this.shape = CollectionShape.square,
    this.showCount = true,
    this.onTap,
    this.onLongPress,
    this.spacing = 16.0,
    this.tileSize = 120.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.all(spacing),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: shape == CollectionShape.circle ? 1.0 : 0.85,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return CollectionTile(
          item: item,
          shape: shape,
          size: tileSize,
          showCount: showCount,
          onTap: onTap != null ? () => onTap!(item) : null,
          onLongPress: onLongPress != null ? () => onLongPress!(item) : null,
        );
      },
    );
  }
}
