import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../models/photo_list_models.dart';
import '../models/timeline_models.dart';
import 'date_section_state.dart';
import 'photo_grid.dart';
import 'dart:typed_data';

/// 日期分组通用网格组件
///
/// 返回 `List<Widget>`, 包含 header 和内容 slivers，用于在 CustomScrollView 中扩展。
/// 统一处理照片和视频的分组加载逻辑，通过回调参数化。
class DateSectionGrid {
  final TimelineItem item;
  final DateSectionState<PhotoListData> state;
  final GlobalKey headerKey;

  /// 当 header 可见时的统一回调（调用方自行处理 mounted 检查与 fetch 触发）
  final Function(TimelineItem) onHeaderVisible;

  /// 点击照片/视频的回调
  final void Function(PhotoItem item, List<PhotoItem> allItems) onItemTap;

  /// 用于异步加载缩略图的回调
  final Future<void> Function(PhotoItem) ensureThumbLoaded;

  /// 缩略图 ValueNotifier 映射（共享引用）
  final Map<String, ValueNotifier<Uint8List?>> thumbNotifiers;

  /// 可选的网格布局代理
  final SliverGridDelegate? gridDelegate;

  /// 占位符数量计算函数（默认基于 itemCount）
  final int Function(int itemCount)? placeholderCountCalc;

  /// 日期标签空内容提示文本
  final String emptyLabel;

  /// VisibilityDetector key 前缀（用于区分照片/视频）
  final String keyPrefix;

  DateSectionGrid({
    required this.item,
    required this.state,
    required this.headerKey,
    required this.onHeaderVisible,
    required this.onItemTap,
    required this.ensureThumbLoaded,
    required this.thumbNotifiers,
    this.gridDelegate,
    this.placeholderCountCalc,
    this.emptyLabel = '该日期无内容',
    this.keyPrefix = 'dategroup',
  });

  /// 构建日期分组的 slivers 列表
  List<Widget> build(BuildContext context) {
    final dateLabel = _formatDateLabel(item);

    // Header: 使用 VisibilityDetector 在可见时触发 fetch
    final header = SliverToBoxAdapter(
      child: VisibilityDetector(
        key: Key('$keyPrefix-${item.timestamp}'),
        onVisibilityChanged: (info) {
          if (info.visibleFraction > 0.06) {
            Future.delayed(const Duration(milliseconds: 120), () {
              onHeaderVisible(item);
            });
          }
        },
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                key: headerKey,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      dateLabel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${item.photoCount})',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // 内容部分（根据加载状态显示不同的 sliver）
    if (!state.hasStarted) {
      return [header, const SliverToBoxAdapter(child: SizedBox(height: 100))];
    }

    final items = state.items;
    if (items.isEmpty && state.currentFuture != null) {
      // 已经开始但未完成：使用占位符
      final placeholderCount = placeholderCountCalc != null
          ? placeholderCountCalc!(item.photoCount)
          : item.photoCount;
      final placeholders = _createPlaceholderItems(
        placeholderCount,
        item.timestamp,
      );

      return [
        header,
        PhotoGrid(
          items: placeholders,
          onPhotoTap: (_) {},
          thumbNotifiers: thumbNotifiers,
          ensureThumbLoaded: (_) async {},
          gridDelegate: gridDelegate,
        ),
      ];
    }

    if (items.isEmpty) {
      return [
        header,
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Text(emptyLabel),
          ),
        ),
      ];
    }

    // 有 items：显示网格
    return [
      header,
      PhotoGrid(
        items: items,
        onPhotoTap: (p) => onItemTap(p, items),
        thumbNotifiers: thumbNotifiers,
        ensureThumbLoaded: ensureThumbLoaded,
        gridDelegate: gridDelegate,
      ),
    ];
  }

  /// 创建占位符 PhotoItem 列表
  List<PhotoItem> _createPlaceholderItems(int count, int timestamp) {
    return List.generate(
      count,
      (index) => PhotoItem(
        photoId: -1 - index - timestamp,
        type: 0,
        name: '',
        path: '',
        size: 0,
        timestamp: timestamp,
        time: '',
        date: '',
        width: 0,
        height: 0,
        isCollect: 0,
        thumbnailPath: '\$placeholder_${timestamp}_$index',
      ),
    );
  }

  String _formatDateLabel(TimelineItem item) {
    return '${item.year}-${item.month.toString().padLeft(2, '0')}-${item.day.toString().padLeft(2, '0')}';
  }
}
