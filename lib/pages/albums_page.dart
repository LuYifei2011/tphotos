import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../api/tos_api.dart';
import '../models/album_models.dart';
import '../models/photo_list_models.dart';
import '../models/timeline_models.dart';
import '../widgets/adaptive_scrollbar.dart';
import '../widgets/date_section_grid.dart';
import '../widgets/date_section_state.dart';
import '../widgets/thumbnail_manager.dart';
import '../widgets/media_viewer_helper.dart';

/// 相册内容缓存
class _AlbumContentCache {
  final List<AlbumTimelineItem> timeline;
  final DateTime cachedAt;

  _AlbumContentCache({required this.timeline}) : cachedAt = DateTime.now();
}

/// 相册返回控制器，用于父页面查询和触发相册返回操作
class AlbumBackHandler {
  bool Function() _canGoBack = () => false;
  VoidCallback _goBack = () {};

  bool get canGoBack => _canGoBack();
  void goBack() => _goBack();

  void attach({
    required bool Function() canGoBack,
    required VoidCallback goBack,
  }) {
    _canGoBack = canGoBack;
    _goBack = goBack;
  }

  void detach() {
    _canGoBack = () => false;
    _goBack = () {};
  }
}

/// 相册页面
class AlbumsPage extends StatefulWidget {
  final TosAPI api;
  final AlbumBackHandler? backHandler;

  const AlbumsPage({super.key, required this.api, this.backHandler});

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> {
  // 相册列表
  List<AlbumInfo> _albums = [];
  bool _isLoadingAlbums = true;
  String? _errorMessage;

  // 当前选中的相册
  AlbumInfo? _currentAlbum;
  List<AlbumTimelineItem> _timeline = [];
  bool _isLoadingTimeline = false;
  String? _timelineError;

  // 滚动控制器
  final ScrollController _albumListScrollController = ScrollController();
  final ScrollController _timelineScrollController = ScrollController();

  // 缩略图 ValueNotifier
  final Map<String, ValueNotifier<Uint8List?>> _thumbNotifiers = {};
  final Map<String, int> _thumbStamps = {};

  // 日期分组状态管理
  final Map<int, DateSectionState<PhotoListData>> _dateSections = {};

  // 相册内容缓存
  final Map<int, _AlbumContentCache> _albumContentCache = {};

  // 时间线滚动上下文
  double _thumbFraction = 0.0;
  bool _showLabel = false;
  String? _currentGroupLabel;
  final Map<int, GlobalKey> _headerKeys = {};

  // 请求版本号，用于忽略过时的响应
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    widget.backHandler?.attach(
      canGoBack: () => _currentAlbum != null,
      goBack: _goBackToAlbumList,
    );
    _loadAlbums();
  }

  Future<void> _loadAlbums({bool forceRefresh = false}) async {
    // 递增版本号，使之前的异步请求失效
    final currentVersion = ++_loadVersion;

    setState(() {
      _isLoadingAlbums = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.api.photos.albumList();

      // 检查是否是最新请求的响应
      if (!mounted || currentVersion != _loadVersion) {
        return; // 忽略过时响应
      }

      if (response.code) {
        setState(() {
          _albums = response.data;
          _isLoadingAlbums = false;
        });

        // 预加载相册封面
        _preloadAlbumCovers();
      } else {
        setState(() {
          _errorMessage = response.msg.isEmpty ? '加载失败' : response.msg;
          _isLoadingAlbums = false;
        });
      }
    } catch (e) {
      // 检查是否是最新请求的响应
      if (!mounted || currentVersion != _loadVersion) {
        return; // 忽略过时响应
      }

      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoadingAlbums = false;
      });
    }
  }

  Future<void> _loadAlbumTimeline(AlbumInfo album,
      {bool forceRefresh = false}) async {
    // 强制刷新时清除当前相册的缓存
    if (forceRefresh) {
      _albumContentCache.remove(album.id);
    }

    // 递增版本号，使之前的异步请求失效
    final currentVersion = ++_loadVersion;

    // 检查缓存
    if (!forceRefresh && _albumContentCache.containsKey(album.id)) {
      final cached = _albumContentCache[album.id]!;
      setState(() {
        _timeline = cached.timeline;
        _isLoadingTimeline = false;
        _timelineError = null;
        if (_timeline.isNotEmpty) {
          _currentGroupLabel = _formatDateLabel(_timeline.first);
        }
      });
      return;
    }

    setState(() {
      _isLoadingTimeline = true;
      _timelineError = null;
    });

    try {
      final response = await widget.api.photos.albumTimeline(
        id: album.id,
        timelineType: 2,
        order: 'desc',
      );

      // 检查是否是最新请求的响应
      if (!mounted || currentVersion != _loadVersion) {
        return; // 忽略过时响应
      }

      if (response.code) {
        // 缓存结果
        _albumContentCache[album.id] = _AlbumContentCache(
          timeline: response.data,
        );

        setState(() {
          _timeline = response.data;
          _isLoadingTimeline = false;
          if (_timeline.isNotEmpty) {
            _currentGroupLabel = _formatDateLabel(_timeline.first);
          }
        });
      } else {
        setState(() {
          _timelineError = response.msg.isEmpty ? '加载失败' : response.msg;
          _isLoadingTimeline = false;
        });
      }
    } catch (e) {
      // 检查是否是最新请求的响应
      if (!mounted || currentVersion != _loadVersion) {
        return; // 忽略过时响应
      }

      setState(() {
        _timelineError = '加载失败: $e';
        _isLoadingTimeline = false;
      });
    }
  }

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
        () => widget.api.photos.thumbnailBytes(item.thumbnailPath),
        stamp: targetStamp,
      );
      notifier.value = bytes;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('缩略图加载失败: $e');
      }
    }
  }

  /// 预加载相册封面缩略图（前20个相册的第一张封面）
  void _preloadAlbumCovers() {
    for (final album in _albums.take(20)) {
      if (album.exhibition.isNotEmpty) {
        final firstCover = album.exhibition.first;
        _ensureAlbumCoverLoaded(firstCover.thumbnailPath);
      }
    }
  }

  Future<void> _ensureAlbumCoverLoaded(String thumbnailPath) async {
    final notifier = _thumbNotifierFor(thumbnailPath);
    if (notifier.value != null) return;

    try {
      final bytes = await ThumbnailManager.instance.load(
        thumbnailPath,
        () => widget.api.photos.thumbnailBytes(thumbnailPath),
      );
      notifier.value = bytes;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('相册封面加载失败: $thumbnailPath, $e');
      }
    }
  }

  /// 进入相册
  void _enterAlbum(AlbumInfo album) {
    setState(() {
      _currentAlbum = album;
      _dateSections.clear();
      _headerKeys.clear();
      _thumbFraction = 0.0;
      _showLabel = false;
    });
    _loadAlbumTimeline(album);
  }

  /// 返回相册列表
  void _goBackToAlbumList() {
    setState(() {
      _currentAlbum = null;
      _timeline = [];
      _timelineError = null;
      _dateSections.clear();
      _headerKeys.clear();
      _thumbFraction = 0.0;
      _showLabel = false;
      _currentGroupLabel = null;
    });
  }

  /// 开始为某一天触发 fetch
  void _startFetchForItem(AlbumTimelineItem item) {
    final key = item.timestamp;
    final state = _dateSections.putIfAbsent(key, () => DateSectionState(key));
    if (state.hasStarted) return;
    state.markStarted();
    _fetchPhotosForDate(item, state);
  }

  Future<void> _fetchPhotosForDate(
    AlbumTimelineItem item,
    DateSectionState<PhotoListData> state,
  ) async {
    if (!state.tryAddLoadingDate()) {
      // 已有加载在途，等待其完成
      await state.waitForOtherLoading();
      return;
    }

    try {
      final future = _getOrLoadDatePhotos(item);
      state.setCurrentFuture(future);

      final data = await future;
      if (!mounted) return;

      setState(() {
        state.cacheItems(data, data.photoList);
      });
    } catch (e) {
      debugPrint('加载相册照片失败: $e');
    } finally {
      state.removeLoadingDate();
      state.clearCurrentFuture();
    }
  }

  Future<PhotoListData> _getOrLoadDatePhotos(AlbumTimelineItem item) async {
    if (_currentAlbum == null) {
      throw Exception('当前没有选中的相册');
    }

    final response = await widget.api.photos.photosInAlbum(
      name: _currentAlbum!.name,
      startTime: item.timestamp,
      endTime: item.timestamp,
      pageIndex: 1,
      pageSize: 150,
      timelineType: 2,
      order: 'desc',
    );

    if (!response.code) {
      throw Exception('API Error: ${response.msg}');
    }

    return response.data;
  }

  GlobalKey _headerKeyFor(int timestamp) {
    return _headerKeys.putIfAbsent(timestamp, () => GlobalKey());
  }

  @override
  Widget build(BuildContext context) {
    if (_currentAlbum == null) {
      return _buildAlbumList();
    } else {
      return _buildAlbumTimeline();
    }
  }

  Widget _buildAlbumList() {
    if (_isLoadingAlbums) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return RefreshIndicator(
        onRefresh: () => _loadAlbums(forceRefresh: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height - 200,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Theme.of(context)
                        .colorScheme
                        .error
                        .withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _loadAlbums(forceRefresh: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_albums.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadAlbums(forceRefresh: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height - 200,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_album,
                    size: 64,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  const Text('暂无相册', style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadAlbums(forceRefresh: true),
      child: AdaptiveScrollbar(
        controller: _albumListScrollController,
        child: GridView.builder(
          controller: _albumListScrollController,
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.85,
          ),
          itemCount: _albums.length,
          itemBuilder: (context, index) => _buildAlbumTile(_albums[index]),
        ),
      ),
    );
  }

  Widget _buildAlbumTile(AlbumInfo album) {
    return InkWell(
      onTap: () => _enterAlbum(album),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 相册封面（2x2 网格或单张）
          Expanded(
            child: _buildAlbumCover(album),
          ),

          const SizedBox(height: 8),

          // 相册名称
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // 照片数量
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '${album.count} 张照片',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
          ),

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildAlbumCover(AlbumInfo album) {
    final exhibition = album.exhibition;

    if (exhibition.isEmpty) {
      // 没有封面，显示默认图标
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.photo_album,
          size: 48,
          color:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      );
    }

    if (exhibition.length == 1) {
      // 单张封面
      return _buildCoverImage(exhibition[0].thumbnailPath);
    }

    // 多张封面（2x2 网格，最多显示 4 张）
    final displayCount = exhibition.length.clamp(0, 4);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: displayCount,
        itemBuilder: (context, index) {
          return _buildCoverImage(exhibition[index].thumbnailPath);
        },
      ),
    );
  }

  Widget _buildCoverImage(String thumbnailPath) {
    final notifier = _thumbNotifierFor(thumbnailPath);

    // 确保缩略图已加载
    _ensureAlbumCoverLoaded(thumbnailPath);

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

        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      },
    );
  }

  Widget _buildAlbumTimeline() {
    return Column(
      children: [
        // 顶部导航栏
        _buildAlbumHeader(),

        // 时间线内容
        Expanded(
          child: _buildTimelineContent(),
        ),
      ],
    );
  }

  Widget _buildAlbumHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBackToAlbumList,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentAlbum?.name ?? '',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_currentAlbum?.count ?? 0} 张照片',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineContent() {
    if (_isLoadingTimeline) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_timelineError != null) {
      return RefreshIndicator(
        onRefresh: () => _loadAlbumTimeline(_currentAlbum!, forceRefresh: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height - 200,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Theme.of(context)
                        .colorScheme
                        .error
                        .withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _timelineError!,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () =>
                        _loadAlbumTimeline(_currentAlbum!, forceRefresh: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_timeline.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadAlbumTimeline(_currentAlbum!, forceRefresh: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height - 200,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo,
                    size: 64,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  const Text('该相册暂无照片', style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final scrollChild = CustomScrollView(
      controller: _timelineScrollController,
      slivers: [
        for (var item in _timeline) ..._buildDateSlivers(item),
      ],
    );

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => _loadAlbumTimeline(_currentAlbum!, forceRefresh: true),
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: AdaptiveScrollbar(
              controller: _timelineScrollController,
              child: scrollChild,
            ),
          ),
        ),
        _buildScrollLabelOverlay(),
      ],
    );
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
    AlbumTimelineItem? bestItem;

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
    if (!_showLabel) {
      setState(() => _showLabel = true);
    }
  }

  void _scheduleHideGroupLabel() {
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() => _showLabel = false);
      }
    });
  }

  Widget _buildScrollLabelOverlay() {
    final label = _currentGroupLabel;
    if (label == null) return const SizedBox.shrink();
    final alignmentY = (_thumbFraction.clamp(0.0, 1.0) * 2) - 1;

    return Positioned.fill(
      child: Padding(
        padding: const EdgeInsets.only(top: 5.0, bottom: 11.0),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: _showLabel ? 1.0 : 0.0,
          child: Align(
            alignment: Alignment(1.0, alignmentY.isNaN ? -1 : alignmentY),
            child: Padding(
              padding: const EdgeInsets.only(right: 36.0),
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
        ),
      ),
    );
  }

  String _formatDateLabel(AlbumTimelineItem item) {
    return '${item.year}-${item.month.toString().padLeft(2, '0')}-${item.day.toString().padLeft(2, '0')}';
  }

  List<Widget> _buildDateSlivers(AlbumTimelineItem item) {
    final key = item.timestamp;
    final state = _dateSections.putIfAbsent(key, () => DateSectionState(key));

    // 将 AlbumTimelineItem 转换为照片页面使用的 TimelineItem
    // 以便复用 DateSectionGrid widget
    final timelineItem = TimelineItem(
      year: item.year,
      month: item.month,
      day: item.day,
      timestamp: item.timestamp,
      photoCount: item.photoCount,
    );

    return DateSectionGrid(
      item: timelineItem,
      state: state,
      headerKey: _headerKeyFor(item.timestamp),
      onHeaderVisible: (ti) {
        if (!mounted) return;
        _startFetchForItem(item);
      },
      onItemTap: (p, allItems) {
        final startIndex = allItems.indexOf(p);
        MediaViewerHelper.openMediaViewer(
          context,
          items: allItems,
          initialIndex: startIndex < 0 ? 0 : startIndex,
          api: widget.api,
        );
      },
      thumbNotifiers: _thumbNotifiers,
      ensureThumbLoaded: _ensureThumbLoaded,
      keyPrefix: 'album-dategroup',
      emptyLabel: '该日期无照片',
    ).build(context);
  }

  @override
  void dispose() {
    widget.backHandler?.detach();
    _albumListScrollController.dispose();
    _timelineScrollController.dispose();
    for (final n in _thumbNotifiers.values) {
      n.dispose();
    }
    super.dispose();
  }
}
