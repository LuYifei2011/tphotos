import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../models/folder_models.dart';
import 'thumbnail_manager.dart';

/// 文件夹缩略图组件
///
/// 支持：
/// - 单张照片全屏显示
/// - 2-4 张照片 2x2 网格显示
/// - 无缩略图时显示文件夹默认图标
/// - 集成 ThumbnailManager 自动加载和缓存
class FolderThumbnailWidget extends StatefulWidget {
  /// 文件夹信息
  final FolderInfo folder;

  /// 缩略图加载函数（通过 API 获取二进制数据）
  final Future<List<int>> Function(String thumbnailPath) loadThumbnail;

  /// 缩略图尺寸
  final double size;

  /// 圆角半径
  final double borderRadius;

  const FolderThumbnailWidget({
    super.key,
    required this.folder,
    required this.loadThumbnail,
    this.size = 120.0,
    this.borderRadius = 8.0,
  });

  @override
  State<FolderThumbnailWidget> createState() => _FolderThumbnailWidgetState();
}

class _FolderThumbnailWidgetState extends State<FolderThumbnailWidget> {
  final Map<String, ValueNotifier<Uint8List?>> _notifiers = {};

  ValueNotifier<Uint8List?> _notifierFor(String path) {
    return _notifiers.putIfAbsent(
      path,
      () => ValueNotifier<Uint8List?>(null),
    );
  }

  Future<void> _ensureLoaded(String thumbnailPath) async {
    final notifier = _notifierFor(thumbnailPath);
    if (notifier.value != null) return;

    try {
      final bytes = await ThumbnailManager.instance.load(
        thumbnailPath,
        () => widget.loadThumbnail(thumbnailPath),
      );
      if (mounted) {
        notifier.value = bytes;
      }
    } catch (e) {
      debugPrint('文件夹缩略图加载失败: $thumbnailPath, $e');
    }
  }

  @override
  void dispose() {
    for (final n in _notifiers.values) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (widget.folder.hasThumbnail) {
      final thumbnails = widget.folder.additional.thumbnail.take(4).toList();

      if (thumbnails.length == 1) {
        content = _buildSingleThumbnail(thumbnails[0].thumbnailPath);
      } else {
        content = _buildMultipleThumbnails(thumbnails);
      }
    } else {
      content = _buildDefaultIcon(context);
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: content,
      ),
    );
  }

  Widget _buildSingleThumbnail(String thumbnailPath) {
    final notifier = _notifierFor(thumbnailPath);
    _ensureLoaded(thumbnailPath);

    return ValueListenableBuilder<Uint8List?>(
      valueListenable: notifier,
      builder: (context, bytes, _) {
        if (bytes != null) {
          return Image.memory(
            bytes,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildDefaultIcon(context);
            },
          );
        } else {
          return _buildPlaceholder(
            context,
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        }
      },
    );
  }

  Widget _buildMultipleThumbnails(List<FolderThumbnail> thumbnails) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 0.5,
        crossAxisSpacing: 0.5,
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        if (index < thumbnails.length) {
          final thumbnailPath = thumbnails[index].thumbnailPath;
          final notifier = _notifierFor(thumbnailPath);
          _ensureLoaded(thumbnailPath);

          return ValueListenableBuilder<Uint8List?>(
            valueListenable: notifier,
            builder: (context, bytes, _) {
              if (bytes != null) {
                return Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildGridPlaceholder(context);
                  },
                );
              } else {
                return _buildGridPlaceholder(
                  context,
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.3),
                    ),
                  ),
                );
              }
            },
          );
        } else {
          return _buildGridPlaceholder(context);
        }
      },
    );
  }

  static Widget _buildGridPlaceholder(BuildContext context, {Widget? child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? Colors.grey[850] : Colors.grey[200],
      child: child != null ? Center(child: child) : null,
    );
  }

  static Widget _buildDefaultIcon(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? Colors.grey[800] : Colors.grey[300],
      child: Center(
        child: Icon(
          Icons.folder,
          size: 48,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  static Widget _buildPlaceholder(
    BuildContext context, {
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? Colors.grey[800] : Colors.grey[300],
      child: Center(child: child),
    );
  }
}
