import 'package:flutter/material.dart';
import '../api/tos_api.dart';
import '../models/photo_list_models.dart';
import '../pages/photos_page.dart';

/// 媒体查看器辅助类
/// 提供统一的图片/视频查看入口，根据媒体类型自动选择合适的查看器
class MediaViewerHelper {
  /// 打开媒体查看器
  ///
  /// 参数：
  /// - [context]: BuildContext
  /// - [items]: 媒体列表（PhotoItem）
  /// - [initialIndex]: 初始显示的索引
  /// - [api]: TosAPI 实例
  ///
  /// 根据初始项目的类型自动选择：
  /// - type = 0: 图片查看器（PhotoViewer）
  /// - type = 1: 视频播放器（VideoPlayerPage）
  static Future<void> openMediaViewer(
    BuildContext context, {
    required List<PhotoItem> items,
    required int initialIndex,
    required TosAPI api,
  }) async {
    if (items.isEmpty) return;

    final validIndex = initialIndex.clamp(0, items.length - 1);
    final currentItem = items[validIndex];

    // 根据类型选择查看器
    if (currentItem.type == 1) {
      // 视频：过滤出所有视频
      final videos = items.where((item) => item.type == 1).toList();
      final videoIndex = videos.indexOf(currentItem);

      if (videoIndex >= 0) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => VideoPlayerPage(
              videos: videos,
              initialIndex: videoIndex,
              api: api,
            ),
          ),
        );
      }
    } else {
      // 图片（type = 0 或其他）：过滤出所有图片
      final photos = items.where((item) => item.type != 1).toList();
      final photoIndex = photos.indexOf(currentItem);

      if (photoIndex >= 0) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                PhotoViewer(photos: photos, initialIndex: photoIndex, api: api),
          ),
        );
      }
    }
  }

  /// 检查是否为视频
  static bool isVideo(PhotoItem item) {
    return item.type == 1;
  }

  /// 获取媒体类型的显示名称
  static String getMediaTypeName(PhotoItem item) {
    return isVideo(item) ? '视频' : '图片';
  }

  /// 获取媒体类型的图标
  static IconData getMediaTypeIcon(PhotoItem item) {
    return isVideo(item) ? Icons.play_circle_outline : Icons.photo;
  }
}
