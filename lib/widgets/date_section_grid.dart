import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../models/photo_list_models.dart';
import '../models/timeline_models.dart';
import 'date_section_state.dart';

/// 日期分组通用网格组件
///
/// 返回 List(Widget), 包含 header 和内容 slivers，用于在 CustomScrollView 中扩展。
/// 统一处理照片和视频的分组加载逻辑，通过回调参数化：
/// - [onVisibilityChanged] - 当 header 可见时触发加载
/// - [buildGrid] - 自定义网格样式
class DateSectionGrid {
  final TimelineItem item;
  final DateSectionState<PhotoListData> state;
  final GlobalKey headerKey;

  /// 当 header 可见时回调，用于触发加载
  final Function(TimelineItem) onVisibilityChanged;

  /// 用于为某一天触发 fetch 的回调
  final Function(TimelineItem) onStartFetch;

  /// 加载数据的回调
  final Future<PhotoListData> Function(TimelineItem) loadData;

  /// 自定义网格构建（包含 PhotoItem 列表）
  /// 应返回 SliverGrid 或类似的 Sliver widget
  final Widget Function(List<PhotoItem>) buildGrid;

  /// 用于异步加载缩略图的回调
  final Future<void> Function(PhotoItem) ensureThumbLoaded;

  /// 占位符数量计算函数（默认基于 itemCount）
  final int Function(int itemCount)? placeholderCountCalc;

  DateSectionGrid({
    required this.item,
    required this.state,
    required this.headerKey,
    required this.onVisibilityChanged,
    required this.onStartFetch,
    required this.loadData,
    required this.buildGrid,
    required this.ensureThumbLoaded,
    this.placeholderCountCalc,
  });

  /// 构建日期分组的 slivers 列表
  List<Widget> build(BuildContext context) {
    final dateLabel = _formatDateLabel(item);

    // Header: 使用 VisibilityDetector 在可见时触发 fetch
    final header = SliverToBoxAdapter(
      child: VisibilityDetector(
        key: ValueKey('header_$dateLabel'),
        onVisibilityChanged: (info) {
          if (info.visibleFraction > 0.1 && !state.hasStarted) {
            onVisibilityChanged(item);
            onStartFetch(item);
          }
        },
        child: Container(
          key: headerKey,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            dateLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );

    // 内容部分（根据加载状态显示不同的 sliver）
    if (!state.hasStarted) {
      // 未开始：返回占位符
      return [header, const SliverToBoxAdapter(child: SizedBox(height: 100))];
    }

    final items = state.items;
    if (items.isEmpty && state.currentFuture != null) {
      // 已经开始但未完成：使用占位符
      final placeholderCount = placeholderCountCalc != null
          ? placeholderCountCalc!(state.itemCount)
          : state.itemCount;
      final placeholders = _createPlaceholderItems(
        placeholderCount,
        item.timestamp,
      );

      return [header, buildGrid(placeholders)];
    }

    if (items.isEmpty) {
      // 已加载但为空
      return [
        header,
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Text('该日期无内容'),
          ),
        ),
      ];
    }

    // 有 items：显示网格
    return [header, buildGrid(items)];
  }

  /// 创建占位符 PhotoItem 列表
  List<PhotoItem> _createPlaceholderItems(int count, int timestamp) {
    return List.generate(
      count,
      (index) => PhotoItem(
        photoId: 0,
        type: 0,
        name: '',
        path: '\$placeholder_${timestamp}_$index',
        size: 0,
        timestamp: timestamp,
        time: '',
        date: '',
        width: 0,
        height: 0,
        isCollect: 0,
        thumbnailPath: '',
      ),
    );
  }

  String _formatDateLabel(TimelineItem item) {
    return '${item.year}-${item.month.toString().padLeft(2, '0')}-${item.day.toString().padLeft(2, '0')}';
  }
}
