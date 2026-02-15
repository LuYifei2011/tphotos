import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../api/tos_api.dart';
import '../models/photo_list_models.dart';
import '../models/timeline_models.dart';
import 'adaptive_scrollbar.dart';
import 'date_section_grid.dart';
import 'date_section_state.dart';
import 'media_viewer_helper.dart';
import 'thumbnail_manager.dart';

/// 通用时间线视图
///
/// 封装了以下功能：
/// - 时间线加载 & 错误/空/加载状态
/// - 按日期分组懒加载照片列表
/// - 缩略图加载（使用 ThumbnailManager）
/// - 滚动日期标签浮层
/// - AdaptiveScrollbar（桌面自适应滚动条）
/// - RefreshIndicator（下拉刷新）
/// - 点击照片 → MediaViewerHelper 打开查看器
///
/// 调用方只需提供 [loadTimeline] 和 [loadPhotosForDate] 两个回调。
class TimelineView extends StatefulWidget {
  /// 加载时间线数据
  final Future<List<TimelineItem>> Function() loadTimeline;

  /// 加载指定日期的照片列表
  final Future<PhotoListData> Function(TimelineItem item) loadPhotosForDate;

  /// 缩略图加载器（默认使用 api.photos.thumbnailBytes）
  final Future<List<int>> Function(String thumbnailPath) loadThumbnail;

  /// TosAPI 实例（用于 MediaViewerHelper）
  final TosAPI api;

  /// VisibilityDetector key 前缀
  final String keyPrefix;

  /// 空数据提示
  final String emptyLabel;

  /// 空日期提示
  final String emptyDateLabel;

  /// 若为 true，则照片 tap 时始终打开视频播放器
  final bool isVideoMode;

  const TimelineView({
    super.key,
    required this.loadTimeline,
    required this.loadPhotosForDate,
    required this.loadThumbnail,
    required this.api,
    this.keyPrefix = 'timeline',
    this.emptyLabel = '暂无内容',
    this.emptyDateLabel = '该日期无内容',
    this.isVideoMode = false,
  });

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  List<TimelineItem> _timeline = [];
  bool _loading = true;
  String? _error;

  final ScrollController _scrollController = ScrollController();
  final Map<int, DateSectionState<PhotoListData>> _sections = {};
  final Map<int, GlobalKey> _headerKeys = {};
  final Map<String, ValueNotifier<Uint8List?>> _thumbNotifiers = {};
  final Map<String, int> _thumbStamps = {};

  // 滚动日期标签
  double _thumbFraction = 0.0;
  bool _showLabel = false;
  Timer? _labelHideTimer;
  String? _currentGroupLabel;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _labelHideTimer?.cancel();
    _scrollController.dispose();
    for (final n in _thumbNotifiers.values) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.loadTimeline();
      if (!mounted) return;
      setState(() {
        _timeline = data;
        if (data.isNotEmpty) {
          _currentGroupLabel = _formatDateLabel(data.first);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    _sections.clear();
    _headerKeys.clear();
    _thumbFraction = 0.0;
    _showLabel = false;
    _currentGroupLabel = null;
    await _load();
  }

  // ---- 日期分组加载 ----

  void _startFetchForItem(TimelineItem item) {
    final key = item.timestamp;
    final state = _sections.putIfAbsent(key, () => DateSectionState(key));
    if (state.hasStarted) return;
    state.markStarted();
    _fetchPhotosForDate(item, state);
  }

  Future<void> _fetchPhotosForDate(
    TimelineItem item,
    DateSectionState<PhotoListData> state,
  ) async {
    if (!state.tryAddLoadingDate()) {
      await state.waitForOtherLoading();
      return;
    }

    try {
      final future = widget.loadPhotosForDate(item);
      state.setCurrentFuture(future);

      final data = await future;
      if (!mounted) return;

      setState(() {
        state.cacheItems(data, data.photoList);
      });
    } catch (e) {
      debugPrint('加载照片失败: $e');
    } finally {
      state.removeLoadingDate();
      state.clearCurrentFuture();
    }
  }

  // ---- 缩略图 ----

  ValueNotifier<Uint8List?> _thumbNotifierFor(String path) {
    return _thumbNotifiers.putIfAbsent(
      path,
      () => ValueNotifier<Uint8List?>(null),
    );
  }

  Future<void> _ensureThumbLoaded(PhotoItem item) async {
    final key = item.thumbnailPath;
    final notifier = _thumbNotifierFor(key);
    final targetStamp = item.timestamp;
    final previousStamp = _thumbStamps[key];
    final stampChanged = previousStamp != null && previousStamp != targetStamp;

    _thumbStamps[key] = targetStamp;

    if (stampChanged) {
      notifier.value = null;
    } else if (notifier.value != null) {
      return;
    }

    try {
      final bytes = await ThumbnailManager.instance.load(
        key,
        () => widget.loadThumbnail(item.thumbnailPath),
        stamp: targetStamp,
      );
      notifier.value = bytes;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('缩略图加载失败: $e');
      }
    }
  }

  // ---- 滚动日期标签 ----

  GlobalKey _headerKeyFor(int timestamp) {
    return _headerKeys.putIfAbsent(timestamp, () => GlobalKey());
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    final maxExtent = notification.metrics.maxScrollExtent;
    final nextFraction = maxExtent <= 0
        ? 0.0
        : (notification.metrics.pixels / maxExtent).clamp(0.0, 1.0);
    if ((nextFraction - _thumbFraction).abs() > 0.001) {
      setState(() => _thumbFraction = nextFraction);
    }

    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _showGroupLabelNow();
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _showGroupLabelNow();
    } else if (notification is ScrollEndNotification) {
      _scheduleHideGroupLabel();
    }
    _updateLabelFromScroll(notification.metrics);
    return false;
  }

  void _updateLabelFromScroll(ScrollMetrics metrics) {
    double bestOffset = double.negativeInfinity;
    TimelineItem? bestItem;

    for (final item in _timeline) {
      final key = _headerKeyFor(item.timestamp);
      final ctx = key.currentContext;
      if (ctx == null) continue;
      final render = ctx.findRenderObject();
      if (render == null) continue;
      final viewport = RenderAbstractViewport.of(render);
      final offsetToReveal = viewport.getOffsetToReveal(render, 0).offset;
      if (offsetToReveal <= metrics.pixels + 1.0 &&
          offsetToReveal > bestOffset) {
        bestOffset = offsetToReveal;
        bestItem = item;
      }
    }

    if (bestItem != null) {
      final label = _formatDateLabel(bestItem);
      if (label != _currentGroupLabel) {
        setState(() {
          _currentGroupLabel = label;
        });
      }
    }
  }

  void _showGroupLabelNow() {
    _labelHideTimer?.cancel();
    if (!_showLabel) {
      setState(() => _showLabel = true);
    }
  }

  void _scheduleHideGroupLabel() {
    _labelHideTimer?.cancel();
    _labelHideTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() => _showLabel = false);
      }
    });
  }

  void _jumpToScrollFraction(double fraction) {
    if (!_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final target = (fraction.clamp(0.0, 1.0)) * maxExtent;
    _scrollController.jumpTo(target);
    setState(() => _thumbFraction = fraction.clamp(0.0, 1.0));
  }

  String _formatDateLabel(TimelineItem item) {
    return '${item.year}-${item.month.toString().padLeft(2, '0')}-${item.day.toString().padLeft(2, '0')}';
  }

  // ---- 构建 ----

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildStatusView(
        icon: Icons.error_outline,
        iconColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
        message: _error!,
        onRetry: _refresh,
      );
    }

    if (_timeline.isEmpty) {
      return _buildStatusView(
        icon: Icons.photo,
        iconColor: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.3),
        message: widget.emptyLabel,
      );
    }

    final scrollChild = CustomScrollView(
      controller: _scrollController,
      slivers: [for (var item in _timeline) ..._buildDateSlivers(item)],
    );

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _refresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: AdaptiveScrollbar(
              controller: _scrollController,
              child: scrollChild,
            ),
          ),
        ),
        _buildScrollLabelOverlay(),
      ],
    );
  }

  Widget _buildStatusView({
    required IconData icon,
    required Color iconColor,
    required String message,
    VoidCallback? onRetry,
  }) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height - 200,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 64, color: iconColor),
                const SizedBox(height: 16),
                Text(message, style: const TextStyle(fontSize: 16)),
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDateSlivers(TimelineItem item) {
    final key = item.timestamp;
    final state = _sections.putIfAbsent(key, () => DateSectionState(key));

    return DateSectionGrid(
      item: item,
      state: state,
      headerKey: _headerKeyFor(item.timestamp),
      onHeaderVisible: (ti) {
        if (!mounted) return;
        _startFetchForItem(ti);
      },
      onItemTap: (p, allItems) {
        MediaViewerHelper.openMediaViewer(
          context,
          items: allItems,
          initialIndex: allItems.indexOf(p).clamp(0, allItems.length - 1),
          api: widget.api,
        );
      },
      thumbNotifiers: _thumbNotifiers,
      ensureThumbLoaded: _ensureThumbLoaded,
      keyPrefix: widget.keyPrefix,
      emptyLabel: widget.emptyDateLabel,
    ).build(context);
  }

  Widget _buildScrollLabelOverlay() {
    final label = _currentGroupLabel;
    if (label == null) return const SizedBox.shrink();
    final alignmentY = (_thumbFraction.clamp(0.0, 1.0) * 2) - 1;
    final media = MediaQuery.of(context);
    const insetTop = 5.0;
    final insetBottom = media.viewPadding.bottom + (_isMobile ? 6.0 : 5.0);

    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.only(top: insetTop, bottom: insetBottom),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: _showLabel ? 1.0 : 0.0,
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final maxHeight = constraints.maxHeight;
              RenderBox? box;
              void handleDrag(Offset globalPosition) {
                if (!_isMobile) return;
                box ??= ctx.findRenderObject() as RenderBox?;
                if (box == null) return;
                final local = box!.globalToLocal(globalPosition);
                final fraction = (local.dy / maxHeight)
                    .clamp(0.0, 1.0)
                    .toDouble();
                _jumpToScrollFraction(fraction);
              }

              return Align(
                alignment: Alignment(1.0, alignmentY.isNaN ? -1 : alignmentY),
                child: Padding(
                  padding: const EdgeInsets.only(right: 36.0),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _isMobile
                        ? (d) {
                            _showGroupLabelNow();
                            handleDrag(d.globalPosition);
                          }
                        : null,
                    onPanUpdate: _isMobile
                        ? (d) => handleDrag(d.globalPosition)
                        : null,
                    onPanEnd: _isMobile
                        ? (_) => _scheduleHideGroupLabel()
                        : null,
                    onTapDown: _isMobile
                        ? (d) {
                            _showGroupLabelNow();
                            handleDrag(d.globalPosition);
                          }
                        : null,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
