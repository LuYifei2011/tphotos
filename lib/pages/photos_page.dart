import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:saver_gallery/saver_gallery.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_control_panel/video_player_control_panel.dart';
import '../api/tos_api.dart';
import '../models/photo_list_models.dart';
import '../models/timeline_models.dart';
import '../widgets/adaptive_scrollbar.dart';
import '../widgets/date_section_grid.dart';
import '../widgets/date_section_state.dart';
import '../widgets/original_photo_manager.dart';
import '../widgets/thumbnail_manager.dart';
import 'settings_page.dart';
import 'folders_page.dart';
import 'albums_page.dart';
import 'face_page.dart';

// 主页各栏目
enum HomeSection {
  photos,
  videos,
  albums,
  folders,
  people,
  scenes,
  places,
  recent,
  favorites,
  shares,
}

// ThumbnailManager 已提取到 lib/widgets/thumbnail_manager.dart

// ---------- 原来的 PhotosPage（已整合 ThumbnailManager + thumb notifiers） ----------
class PhotosPage extends StatefulWidget {
  final TosAPI api;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  const PhotosPage({
    super.key,
    required this.api,
    required this.themeMode,
    required this.onToggleTheme,
  });

  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

// 时间线滚动上下文：封装滚动相关的状态和方法
class _TimelineScrollContext {
  final ScrollController controller = ScrollController();
  double thumbFraction = 0.0;
  bool showLabel = false;
  Timer? labelHideTimer;
  String? currentGroupLabel;
  final Map<int, GlobalKey> headerKeys = {};

  void dispose() {
    labelHideTimer?.cancel();
    controller.dispose();
  }

  void reset() {
    thumbFraction = 0.0;
    showLabel = false;
    currentGroupLabel = null;
    headerKeys.clear();
  }

  GlobalKey headerKeyFor(int timestamp) {
    return headerKeys.putIfAbsent(timestamp, () => GlobalKey());
  }
}

class _PhotosPageState extends State<PhotosPage> {
  HomeSection _section = HomeSection.photos;
  List<dynamic> _photos = [];
  // 视频 timeline 列表
  List<dynamic> _videos = [];
  bool _loading = true;
  String? _error;
  bool _videoLoading = false;
  String? _videoError;
  // 当前空间（1: 个人空间, 2: 公共空间）
  int _space = 1;
  // 启动默认空间（仅用于设置页显示与保存，不影响当前 _space）
  int _defaultSpace = 1;

  // 统一的日期分组状态管理（替代原有的 6 对独立 Map）
  final Map<int, DateSectionState<PhotoListData>> _photoSections = {};
  final Map<int, DateSectionState<PhotoListData>> _videoSections = {};

  // 缩略图的 ValueNotifier，用于局部更新，避免大量 FutureBuilder 重建
  final Map<String, ValueNotifier<Uint8List?>> _thumbNotifiers = {};
  final Map<String, int> _thumbStamps = {};

  String? _username;

  // 照片和视频的滚动上下文
  final _TimelineScrollContext _photoScroll = _TimelineScrollContext();
  final _TimelineScrollContext _videoScroll = _TimelineScrollContext();
  final PageController _pageController = PageController();

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

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

  @override
  void dispose() {
    _photoScroll.dispose();
    _videoScroll.dispose();
    _pageController.dispose();
    // dispose notifiers
    for (final n in _thumbNotifiers.values) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initSpace();
  }

  Future<void> _initSpace() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt('space') ?? 2;
      _space = (v == 1) ? 1 : 2;
      _defaultSpace = _space;
      _username = prefs.getString('username');
    } catch (_) {
      _space = 1;
      _defaultSpace = 1;
      _username = null;
    }
    if (!mounted) return;
    setState(() {});
    await _load();
  }

  Future<void> _onSpaceChanged(int v) async {
    if (v != 1 && v != 2) return;
    if (v == _space) return;
    setState(() {
      _space = v;
      // 切换空间时清空缓存与进行中的状态
      _photoSections.clear();
      _videoSections.clear();
      _photoScroll.reset();
      _videoScroll.reset();
      // 重置缩略图 notifiers，避免跨空间污染 UI
      for (final n in _thumbNotifiers.values) {
        n.dispose();
      }
      _thumbNotifiers.clear();
      _thumbStamps.clear();
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('space', _space);
    } catch (_) {}
    await _load();
  }

  // 仅保存默认空间（不影响当前 _space）
  Future<void> _saveDefaultSpace(int v) async {
    if (v != 1 && v != 2) return;
    setState(() => _defaultSpace = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('space', v);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.api.photos.timeline(
        space: _space,
        fileType: 0,
        timelineType: 2,
        order: 'desc',
      );
      setState(() {
        _photos = res.data;
        _photoScroll.reset();
        if (res.data.isNotEmpty) {
          _photoScroll.currentGroupLabel = _formatDateLabel(res.data.first);
        }
      });
    } catch (e) {
      setState(() => _error = '加载失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadVideos() async {
    setState(() {
      _videoLoading = true;
      _videoError = null;
    });
    try {
      final res = await widget.api.photos.timeline(
        space: _space,
        fileType: 1, // 视频
        timelineType: 2,
        order: 'desc',
      );
      setState(() {
        _videos = res.data;
        _videoScroll.reset();
        if (res.data.isNotEmpty) {
          _videoScroll.currentGroupLabel = _formatDateLabel(res.data.first);
        }
      });
    } catch (e) {
      setState(() => _videoError = '加载失败: $e');
    } finally {
      if (mounted) setState(() => _videoLoading = false);
    }
  }

  Future<void> _logout() async {
    try {
      await widget.api.auth.logout();
    } catch (_) {}
    try {
      widget.api.dispose();
    } catch (_) {}
    if (!mounted) return;
    // 返回登录页
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  /// 开始为某一天触发 fetch（由 VisibilityDetector 在 header 可见时触发）
  void _startFetchForItem(TimelineItem item) {
    final key = item.timestamp;
    final state = _photoSections.putIfAbsent(key, () => DateSectionState(key));
    if (state.hasStarted) return;
    state.markStarted();
    _fetchPhotosForDate(item, state);
  }

  Future<void> _fetchPhotosForDate(
    TimelineItem item,
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

      // 当 fetch 返回后，可以检查是否需要自动加载下一天（填充不足）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeRequestNextIfNotFilled(item, data.photoList.length);
      });
    } catch (e) {
      debugPrint('加载照片失败: $e');
    } finally {
      state.removeLoadingDate();
      state.clearCurrentFuture();
    }
  }

  void _maybeRequestNextIfNotFilled(TimelineItem item, int itemCount) {
    final mq = MediaQuery.of(context);
    final width = mq.size.width;
    const maxCrossAxisExtent = 120.0;
    const crossAxisSpacing = 4.0;
    const mainAxisSpacing = 4.0;

    final crossCount = (width / maxCrossAxisExtent).floor().clamp(1, 100);
    final itemWidth =
        (width - (crossCount - 1) * crossAxisSpacing) / crossCount;
    final rows = (itemCount / crossCount).ceil();
    final gridHeight = rows * itemWidth + (rows - 1) * mainAxisSpacing;

    final viewportHeight =
        mq.size.height - kToolbarHeight - 60; // 60 是标题+padding 的估算

    if (gridHeight < viewportHeight * 0.8) {
      _triggerLoadForIndex(
        _photos.indexWhere(
              (e) => (e as TimelineItem).timestamp == item.timestamp,
            ) +
            1,
      );
    }
  }

  void _triggerLoadForIndex(int idx) {
    if (idx < 0 || idx >= _photos.length) return;
    final next = _photos[idx] as TimelineItem;
    _startFetchForItem(next);
  }

  Future<PhotoListData> _getOrLoadDatePhotos(TimelineItem item) async {
    // 注意：Timeline.timestamp 单位假设为秒；以年月日计算当日范围
    final start =
        DateTime(item.year, item.month, item.day).millisecondsSinceEpoch ~/
        1000;
    final end = start + 86400 - 1;
    final data = await widget.api.photos.photoListAll(
      space: _space,
      listType: 1,
      fileType: 0,
      startTime: start,
      endTime: end,
      pageSize: 200,
      timelineType: 2,
      order: 'desc',
    );
    return data;
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _drawerOpen = false;
  final FolderBackHandler _folderBackHandler = FolderBackHandler();
  final AlbumBackHandler _albumBackHandler = AlbumBackHandler();

  @override
  Widget build(BuildContext context) {
    // 侧栏打开时拦截返回并手动关闭侧栏，避免路由级返回抢占
    // 文件夹子目录时拦截返回并先回到上一级目录
    // 相册子页面时拦截返回并先回到相册列表
    // 照片主页允许系统返回（退出应用）
    final canPop =
        !_drawerOpen &&
        !(_section == HomeSection.folders && _folderBackHandler.canGoBack) &&
        !(_section == HomeSection.albums && _albumBackHandler.canGoBack) &&
        _section == HomeSection.photos;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return; // 已经 pop 了（如关闭 drawer），不做额外处理

        if (_drawerOpen) {
          _scaffoldKey.currentState?.closeDrawer();
          return;
        }

        // 先检查文件夹子页面是否需要返回上一级
        if (_section == HomeSection.folders && _folderBackHandler.canGoBack) {
          _folderBackHandler.goBack();
          return;
        }

        // 检查相册子页面是否需要返回相册列表
        if (_section == HomeSection.albums && _albumBackHandler.canGoBack) {
          _albumBackHandler.goBack();
          return;
        }

        // 不在照片页面时，切回照片页面
        if (_section != HomeSection.photos) {
          setState(() {
            _section = HomeSection.photos;
            _photoScroll.showLabel = false;
            _videoScroll.showLabel = false;
          });
          // 如果照片列表为空，重新加载
          if (_photos.isEmpty) {
            _load();
          }
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        onDrawerChanged: (isOpen) {
          setState(() => _drawerOpen = isOpen);
        },
        appBar: AppBar(
          title: Text(_titleForSection(_section)),
          actions: [
            PopupMenuButton<int>(
              tooltip: '切换空间',
              icon: Icon(_space == 1 ? Icons.person : Icons.people),
              onSelected: _onSpaceChanged,
              itemBuilder: (context) => [
                CheckedPopupMenuItem<int>(
                  value: 1,
                  checked: _space == 1,
                  child: const Text('个人空间'),
                ),
                CheckedPopupMenuItem<int>(
                  value: 2,
                  checked: _space == 2,
                  child: const Text('公共空间'),
                ),
              ],
            ),
            IconButton(
              tooltip: _themeTooltip(widget.themeMode),
              onPressed: widget.onToggleTheme,
              icon: Icon(_themeIcon(widget.themeMode)),
            ),
            IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
          ],
        ),
        drawer: Drawer(
          child: ListView(
            padding: const EdgeInsets.only(top: 48),
            children: [
              _menuTile('照片', Icons.photo, HomeSection.photos),
              _menuTile('视频', Icons.videocam, HomeSection.videos),
              _menuTile('相册', Icons.photo_album, HomeSection.albums),
              _menuTile('文件夹', Icons.folder, HomeSection.folders),
              _menuTile('人物', Icons.people, HomeSection.people),
              _menuTile('场景', Icons.landscape, HomeSection.scenes),
              _menuTile('地点', Icons.place, HomeSection.places),
              _menuTile('最近添加', Icons.fiber_new, HomeSection.recent),
              _menuTile('收藏', Icons.favorite, HomeSection.favorites),
              _menuTile('分享', Icons.share, HomeSection.shares),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('设置'),
                onTap: () {
                  Navigator.pop(context);
                  _openSettings();
                },
              ),
            ],
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  String _titleForSection(HomeSection s) {
    switch (s) {
      case HomeSection.photos:
        return '照片';
      case HomeSection.videos:
        return '视频';
      case HomeSection.albums:
        return '相册';
      case HomeSection.folders:
        return '文件夹';
      case HomeSection.people:
        return '人物';
      case HomeSection.scenes:
        return '场景';
      case HomeSection.places:
        return '地点';
      case HomeSection.recent:
        return '最近添加';
      case HomeSection.favorites:
        return '收藏';
      case HomeSection.shares:
        return '分享';
    }
  }

  ListTile _menuTile(String title, IconData icon, HomeSection section) {
    final selected = _section == section;
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(title),
      selected: selected,
      onTap: () {
        Navigator.pop(context);
        if (_section != section) {
          setState(() {
            _section = section;
            _photoScroll.showLabel = false;
            _videoScroll.showLabel = false;
          });
          if (section == HomeSection.photos && _photos.isEmpty) {
            _load();
          }
          if (section == HomeSection.videos && _videos.isEmpty) {
            _loadVideos();
          }
        }
      },
    );
  }

  Future<void> _openSettings() async {
    final connection = widget.api.baseUrl;
    final defaultSpace = _defaultSpace;
    final username = _username;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          connection: connection,
          username: username,
          defaultSpace: defaultSpace,
          onDefaultSpaceChanged: _handleDefaultSpaceChanged,
        ),
      ),
    );
  }

  Future<void> _handleDefaultSpaceChanged(int value) async {
    await _saveDefaultSpace(value);
    // 只保存默认空间设置，不影响当前运行时的空间
  }

  Widget _buildBody() {
    if (_section == HomeSection.photos) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_error != null) return Center(child: Text(_error!));
      final scrollChild = _photos.isEmpty
          ? ListView(
              controller: _photoScroll.controller,
              children: const [
                SizedBox(height: 200),
                Center(child: Text('暂无照片')),
              ],
            )
          : CustomScrollView(
              controller: _photoScroll.controller,
              slivers: [
                // For each date item we insert a header (SliverToBoxAdapter) and
                // either a loader/empty widget or a SliverGrid for photos.
                for (var raw in _photos)
                  ..._buildDateSlivers(raw as TimelineItem),
              ],
            );

      return Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              _photoSections.clear();
              _photoScroll.headerKeys.clear();
              await _load();
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (notif) =>
                  _handleScrollNotification(notif, _photoScroll, _photos),
              child: AdaptiveScrollbar(
                controller: _photoScroll.controller,
                child: scrollChild,
              ),
            ),
          ),
          _buildScrollLabelOverlay(_photoScroll),
        ],
      );
    }
    if (_section == HomeSection.videos) {
      if (_videoLoading)
        return const Center(child: CircularProgressIndicator());
      if (_videoError != null) return Center(child: Text(_videoError!));

      final scrollChild = _videos.isEmpty
          ? ListView(
              controller: _videoScroll.controller,
              children: const [
                SizedBox(height: 200),
                Center(child: Text('暂无视频')),
              ],
            )
          : CustomScrollView(
              controller: _videoScroll.controller,
              slivers: [
                for (var raw in _videos)
                  ..._buildVideoDateSlivers(raw as TimelineItem),
              ],
            );

      return Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              _videoSections.clear();
              _videoScroll.headerKeys.clear();
              await _loadVideos();
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (notif) =>
                  _handleScrollNotification(notif, _videoScroll, _videos),
              child: AdaptiveScrollbar(
                controller: _videoScroll.controller,
                child: scrollChild,
              ),
            ),
          ),
          _buildScrollLabelOverlay(_videoScroll),
        ],
      );
    }
    if (_section == HomeSection.folders) {
      return FoldersPage(api: widget.api, backHandler: _folderBackHandler);
    }
    if (_section == HomeSection.albums) {
      return AlbumsPage(api: widget.api, backHandler: _albumBackHandler);
    }
    if (_section == HomeSection.people) {
      return FacePage(api: widget.api, space: _space);
    }
    return Center(child: Text('TODO: ${_titleForSection(_section)}'));
  }

  // ---------------- 通用滚动处理方法 ----------------

  bool _handleScrollNotification(
    ScrollNotification notification,
    _TimelineScrollContext context,
    List<dynamic> items,
  ) {
    if (notification.metrics.axis != Axis.vertical) return false;

    final maxExtent = notification.metrics.maxScrollExtent;
    final nextFraction = maxExtent <= 0
        ? 0.0
        : (notification.metrics.pixels / maxExtent).clamp(0.0, 1.0);
    if ((nextFraction - context.thumbFraction).abs() > 0.001) {
      setState(() => context.thumbFraction = nextFraction);
    }

    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _showGroupLabelNow(context);
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _showGroupLabelNow(context);
    } else if (notification is ScrollEndNotification) {
      _scheduleHideGroupLabel(context);
    }
    _updateLabelFromScroll(notification.metrics, context, items);
    return false;
  }

  void _updateLabelFromScroll(
    ScrollMetrics metrics,
    _TimelineScrollContext context,
    List<dynamic> items,
  ) {
    double bestOffset = double.negativeInfinity;
    TimelineItem? bestItem;

    for (final raw in items) {
      final item = raw as TimelineItem;
      final key = context.headerKeyFor(item.timestamp);
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
      if (label != context.currentGroupLabel) {
        setState(() {
          context.currentGroupLabel = label;
        });
      }
    }
  }

  void _showGroupLabelNow(_TimelineScrollContext context) {
    context.labelHideTimer?.cancel();
    if (!context.showLabel) {
      setState(() => context.showLabel = true);
    }
  }

  void _scheduleHideGroupLabel(_TimelineScrollContext context) {
    context.labelHideTimer?.cancel();
    context.labelHideTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() => context.showLabel = false);
      }
    });
  }

  void _jumpToScrollFraction(double fraction, _TimelineScrollContext context) {
    if (!context.controller.hasClients) return;
    final maxExtent = context.controller.position.maxScrollExtent;
    final target = (fraction.clamp(0.0, 1.0)) * maxExtent;
    context.controller.jumpTo(target);
    setState(() => context.thumbFraction = fraction.clamp(0.0, 1.0));
  }

  Widget _buildScrollLabelOverlay(_TimelineScrollContext scrollContext) {
    final label = scrollContext.currentGroupLabel;
    if (label == null) return const SizedBox.shrink();
    final alignmentY = (scrollContext.thumbFraction.clamp(0.0, 1.0) * 2) - 1;
    final media = MediaQuery.of(context);
    final insetTop = 5.0;
    final insetBottom = media.viewPadding.bottom + (_isMobile ? 6.0 : 5.0);
    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.only(top: insetTop, bottom: insetBottom),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: scrollContext.showLabel ? 1.0 : 0.0,
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
                _jumpToScrollFraction(fraction, scrollContext);
              }

              return Align(
                alignment: Alignment(1.0, alignmentY.isNaN ? -1 : alignmentY),
                child: Padding(
                  padding: const EdgeInsets.only(right: 36.0),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _isMobile
                        ? (details) {
                            _showGroupLabelNow(scrollContext);
                            handleDrag(details.globalPosition);
                          }
                        : null,
                    onPanUpdate: _isMobile
                        ? (details) => handleDrag(details.globalPosition)
                        : null,
                    onPanEnd: _isMobile
                        ? (_) => _scheduleHideGroupLabel(scrollContext)
                        : null,
                    onTapDown: _isMobile
                        ? (details) {
                            _showGroupLabelNow(scrollContext);
                            handleDrag(details.globalPosition);
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

  String _formatDateLabel(TimelineItem item) {
    return '${item.year}-${item.month.toString().padLeft(2, '0')}-${item.day.toString().padLeft(2, '0')}';
  }

  // 构建每个日期对应的 sliver 片段（header + grid/loader）
  List<Widget> _buildDateSlivers(TimelineItem item) {
    final key = item.timestamp;
    final state = _photoSections.putIfAbsent(key, () => DateSectionState(key));

    return DateSectionGrid(
      item: item,
      state: state,
      headerKey: _photoScroll.headerKeyFor(item.timestamp),
      onHeaderVisible: (ti) {
        if (!mounted) return;
        _startFetchForItem(ti);
      },
      onItemTap: (p, allItems) {
        final startIndex = allItems.indexOf(p);
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                PhotoViewer(
                  photos: allItems,
                  initialIndex: startIndex < 0 ? 0 : startIndex,
                  api: widget.api,
                ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          ),
        );
      },
      thumbNotifiers: _thumbNotifiers,
      ensureThumbLoaded: _ensureThumbLoaded,
      keyPrefix: 'dategroup-photo',
      emptyLabel: '该日期无照片',
    ).build(context);
  }

  IconData _themeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
        return Icons.brightness_auto;
    }
  }

  String _themeTooltip(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色模式（点按切换）';
      case ThemeMode.dark:
        return '深色模式（点按切换）';
      case ThemeMode.system:
        return '跟随系统（点按切换）';
    }
  }

  // ---------------- 视频页逻辑（与照片类似，但 file_type=1） ----------------

  Future<PhotoListData> _getOrLoadDateVideos(TimelineItem item) async {
    // 注意：Timeline.timestamp 单位假设为秒；以年月日计算当日范围
    final start =
        DateTime(item.year, item.month, item.day).millisecondsSinceEpoch ~/
        1000;
    final end = start + 86400 - 1;
    final data = await widget.api.photos.photoListAll(
      space: _space,
      listType: 1,
      fileType: 1, // 视频
      startTime: start,
      endTime: end,
      pageSize: 200,
      timelineType: 2,
      order: 'desc',
    );
    return data;
  }

  void _startFetchForVideoItem(TimelineItem item) {
    final key = item.timestamp;
    final state = _videoSections.putIfAbsent(key, () => DateSectionState(key));
    if (state.hasStarted) return;
    state.markStarted();
    _fetchVideosForDate(item, state);
  }

  Future<void> _fetchVideosForDate(
    TimelineItem item,
    DateSectionState<PhotoListData> state,
  ) async {
    if (!state.tryAddLoadingDate()) {
      // 已有加载在途，等待其完成
      await state.waitForOtherLoading();
      return;
    }

    try {
      final future = _getOrLoadDateVideos(item);
      state.setCurrentFuture(future);

      final data = await future;
      if (!mounted) return;

      setState(() {
        state.cacheItems(data, data.photoList);
      });
    } catch (e) {
      debugPrint('加载视频失败: $e');
    } finally {
      state.removeLoadingDate();
      state.clearCurrentFuture();
    }
  }

  List<Widget> _buildVideoDateSlivers(TimelineItem item) {
    final key = item.timestamp;
    final state = _videoSections.putIfAbsent(key, () => DateSectionState(key));

    return DateSectionGrid(
      item: item,
      state: state,
      headerKey: _videoScroll.headerKeyFor(item.timestamp),
      onHeaderVisible: (ti) {
        if (!mounted) return;
        _startFetchForVideoItem(ti);
      },
      onItemTap: (p, allItems) {
        final startIndex = allItems.indexOf(p);
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                VideoPlayerPage(
                  videos: allItems,
                  initialIndex: startIndex < 0 ? 0 : startIndex,
                  api: widget.api,
                ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
          ),
        );
      },
      thumbNotifiers: _thumbNotifiers,
      ensureThumbLoaded: _ensureThumbLoaded,
      keyPrefix: 'videogroup',
      emptyLabel: '该日期无视频',
    ).build(context);
  }
}

// ---------------- 视频播放页 ----------------
class VideoPlayerPage extends StatefulWidget {
  final List<PhotoItem> videos;
  final int initialIndex;
  final TosAPI api;

  const VideoPlayerPage({
    super.key,
    required this.videos,
    required this.initialIndex,
    required this.api,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late int _index;
  // 为避免引入过多复杂逻辑：单实例播放器，切换时重新初始化
  VideoPlayerController? _controller;
  Future<void>? _initFuture;
  // 已下载的临时文件缓存，避免重复写入
  final Map<String, Future<File>> _tempFileCache = {};
  String? _lastError;
  bool _saving = false; // 保存状态
  String _userHome() =>
      Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.systemTemp.path;

  Future<File> _fallbackDesktopCopy(File src) async {
    final home = _userHome();
    final targetDir = Directory(p.join(home, 'Videos', 'TPhotos'));
    if (!await targetDir.exists()) await targetDir.create(recursive: true);
    var dst = File(p.join(targetDir.path, p.basename(src.path)));
    if (await dst.exists()) {
      final base = p.basenameWithoutExtension(src.path);
      final ext = p.extension(src.path);
      dst = File(
        p.join(
          targetDir.path,
          '${base}_${DateTime.now().millisecondsSinceEpoch}$ext',
        ),
      );
    }
    return src.copy(dst.path);
  }

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.videos.length - 1);
    _loadCurrent();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<File> _downloadToTemp(PhotoItem item) {
    if (kDebugMode) debugPrint('[VideoPlayer] download temp for ${item.path}');
    return _tempFileCache.putIfAbsent(item.path, () async {
      try {
        final bytes = await widget.api.photos.originalPhotoBytes(item.path);
        final ext = _inferVideoExtension(item.name);
        final dir = Directory(
          p.join(Directory.systemTemp.path, 'tphotos_videos'),
        );
        if (!await dir.exists()) await dir.create(recursive: true);
        final file = File(
          p.join(dir.path, '${_sanitizeFileNameWithoutExt(item.name)}$ext'),
        );
        await file.writeAsBytes(bytes, flush: true);
        if (kDebugMode)
          debugPrint(
            '[VideoPlayer] temp ok path=${file.path} size=${bytes.length}',
          );
        return file;
      } catch (e, st) {
        if (kDebugMode)
          debugPrint('[VideoPlayer][ERR] download temp failed: $e\n$st');
        rethrow;
      }
    });
  }

  String _inferVideoExtension(String name) {
    final lower = name.toLowerCase();
    for (final e in ['.mp4', '.mov', '.mkv', '.webm']) {
      if (lower.endsWith(e)) return e;
    }
    return '.mp4';
  }

  String _sanitizeFileNameWithoutExt(String name) {
    final base = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    return base.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }

  Future<void> _loadCurrent() async {
    final item = widget.videos[_index];
    if (kDebugMode)
      debugPrint('[VideoPlayer] load index=$_index name=${item.name}');
    _controller?.dispose();
    _controller = null;
    setState(() {});
    try {
      final file = await _downloadToTemp(item);
      if (!mounted) return;
      final c = VideoPlayerController.file(file);
      _controller = c;
      _initFuture = c.initialize().then((_) {
        c.play();
        c.setLooping(true);
        _lastError = null;
        if (mounted) setState(() {});
        if (kDebugMode)
          debugPrint(
            '[VideoPlayer] init file ok dur=${c.value.duration} size=${c.value.size} src=${file.path}',
          );
      });
    } catch (e, st) {
      _lastError = '初始化失败: $e\n$st';
      if (mounted) setState(() {});
      if (kDebugMode) debugPrint('[VideoPlayer][ERR] init failed: $e');
    }
  }

  void _next() {
    if (_index >= widget.videos.length - 1) return;
    setState(() => _index++);
    _loadCurrent();
  }

  void _prev() {
    if (_index <= 0) return;
    setState(() => _index--);
    _loadCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.videos[_index];
    final heroTag = 'photo_hero_${item.path}';
    return Scaffold(
      appBar: AppBar(
        title: Text('${item.name} (${_index + 1}/${widget.videos.length})'),
        actions: [
          IconButton(
            tooltip: '保存到本地',
            onPressed: _saving ? null : _saveCurrent,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt),
          ),
        ],
      ),
      body: Center(
        child: Hero(
          tag: heroTag,
          child: _controller == null
              ? const ColoredBox(
                  color: Colors.black,
                  child: Center(child: CircularProgressIndicator()),
                )
              : FutureBuilder<void>(
                  future: _initFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const ColoredBox(
                        color: Colors.black,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (!_controller!.value.isInitialized) {
                      return _buildVideoError();
                    }
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final aspect = _controller!.value.aspectRatio == 0
                            ? 16 / 9
                            : _controller!.value.aspectRatio;
                        return Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth,
                              maxHeight: constraints.maxHeight,
                            ),
                            child: AspectRatio(
                              aspectRatio: aspect,
                              child: JkVideoControlPanel(
                                _controller!,
                                showClosedCaptionButton: false,
                                showFullscreenButton: true,
                                showVolumeButton: true,
                                bgColor: Colors.black,
                                onPrevClicked: _index <= 0
                                    ? null
                                    : () {
                                        _prev();
                                      },
                                onNextClicked:
                                    _index >= widget.videos.length - 1
                                    ? null
                                    : () {
                                        _next();
                                      },
                                onPlayEnded: () {
                                  if (_index < widget.videos.length - 1) {
                                    _next();
                                  } else {
                                    _controller!.seekTo(Duration.zero);
                                    _controller!.pause();
                                  }
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _saveCurrent() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final item = widget.videos[_index];
      final file = await _downloadToTemp(item);
      if (kDebugMode)
        debugPrint(
          '[VideoPlayer] save file path=${file.path} size=${await file.length()}',
        );
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // 桌面平台：插件不可用，采用复制到用户 Pictures 目录
        final copied = await _fallbackDesktopCopy(file);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('已保存到: ${copied.path}')));
        }
        return;
      }
      try {
        final result = await SaverGallery.saveFile(
          filePath: file.path,
          fileName: p.basename(file.path),
          skipIfExists: false,
          androidRelativePath: 'Movies/TPhotos',
        );
        if (!mounted) return;
        final success = result.isSuccess;
        if (kDebugMode)
          debugPrint('[VideoPlayer] save result success=$success raw=$result');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? '已保存到相册' : '保存失败(${result.errorMessage ?? '未知错误'})',
            ),
          ),
        );
      } on MissingPluginException catch (e) {
        if (kDebugMode)
          debugPrint('[VideoPlayer][MissingPlugin] $e => fallback');
        final copied = await _fallbackDesktopCopy(file);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('插件缺失，已保存到: ${copied.path}')));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VideoPlayer][ERR] save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildVideoError() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 56),
          const SizedBox(height: 12),
          const Text('视频初始化失败'),
          const SizedBox(height: 8),
          if (_lastError != null)
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _lastError!,
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              ElevatedButton.icon(
                onPressed: _loadCurrent,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
              ElevatedButton.icon(
                onPressed: _openExternalPlayer,
                icon: const Icon(Icons.open_in_new),
                label: const Text('外部播放器'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openExternalPlayer() async {
    try {
      final item = widget.videos[_index];
      final file = await _downloadToTemp(item);
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', file.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [file.path]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('外部打开失败: $e')));
    }
  }
}

// 已用 JkVideoControlPanel 替换旧的 _ControlsOverlay

class PhotoViewer extends StatefulWidget {
  final List<PhotoItem> photos;
  final int initialIndex;
  final TosAPI api;

  const PhotoViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.api,
  });

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _controller;
  late int _index;
  final FocusNode _focusNode = FocusNode();
  String? _lastSavedPath; // 仅桌面平台使用
  bool _isZoomed = false; // 跟踪图片是否处于放大状态
  final Map<int, TransformationController> _transformControllers =
      {}; // 每个页面的变换控制器
  int _pointerCount = 0; // 屏幕上的手指数量

  static final LinkedHashMap<String, ImageProvider<Object>>
  _imageProviderCache =
      LinkedHashMap<
        String,
        ImageProvider<Object>
      >(); // 缓存 ImageProvider，保留解码后的图片

  // Keyboard intents
  static final _nextIntent = NextPhotoIntent();
  static final _prevIntent = PrevPhotoIntent();
  static final _escapeIntent = EscapeViewerIntent();
  static final _saveIntent = SavePhotoIntent();
  static final _deleteIntent = DeletePhotoIntent();

  @override
  void initState() {
    super.initState();
    debugPrint('[PhotoViewer] initState - Current cache status:');
    debugPrint(
      '[PhotoViewer]   - Memory cache size: ${OriginalPhotoManager.instance.memoryCacheSize}',
    );
    debugPrint(
      '[PhotoViewer]   - ImageProvider cache size: ${_imageProviderCache.length}',
    );
    _index = widget.initialIndex.clamp(0, widget.photos.length - 1);
    _controller = PageController(initialPage: _index);
    // 初始预取
    _prefetchAround(_index);
    // 确保获取键盘焦点
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    debugPrint('[PhotoViewer] dispose - Cache status before dispose:');
    debugPrint(
      '[PhotoViewer]   - Memory cache size: ${OriginalPhotoManager.instance.memoryCacheSize}',
    );
    debugPrint(
      '[PhotoViewer]   - ImageProvider cache size: ${_imageProviderCache.length}',
    );
    _controller.dispose();
    _focusNode.dispose();
    // 清理所有 transformation controllers
    for (final controller in _transformControllers.values) {
      controller.dispose();
    }
    _transformControllers.clear();
    super.dispose();
  }

  Future<Uint8List> _loadOriginal(PhotoItem item) {
    debugPrint('[PhotoViewer] _loadOriginal called for: ${item.path}');
    return OriginalPhotoManager.instance.load(
      item.path,
      () => widget.api.photos.originalPhotoBytes(item.path),
      stamp: item.timestamp,
    );
  }

  void _prefetchAround(int idx) {
    debugPrint('[PhotoViewer] Prefetching around index: $idx');
    void prefetch(int i) {
      if (i < 0 || i >= widget.photos.length) return;
      final p = widget.photos[i];
      debugPrint('[PhotoViewer] Prefetch index $i: ${p.path}');

      // 加载字节数据并预解码，需在使用 context 前检查 mounted
      unawaited(() async {
        try {
          final bytes = await _loadOriginal(p);
          if (!mounted) return;
          final provider = _getOrCreateImageProvider(p.path, bytes);
          debugPrint('[PhotoViewer] Precaching image for: ${p.path}');
          await precacheImage(provider, context);
          debugPrint('[PhotoViewer] ✓ Precache completed for: ${p.path}');
        } catch (e, _) {
          debugPrint('[PhotoViewer] Prefetch error for ${p.path}: $e');
        }
      }());
    }

    prefetch(idx);
    prefetch(idx + 1);
    prefetch(idx - 1);
  }

  ImageProvider<Object> _getOrCreateImageProvider(
    String path,
    Uint8List bytes,
  ) {
    final existing = _imageProviderCache.remove(path);
    if (existing != null) {
      _imageProviderCache[path] = existing;
      return existing;
    }

    debugPrint(
      '[PhotoViewer] Creating ImageProvider for: $path (${bytes.length} bytes)',
    );

    final screenWidth =
        MediaQuery.of(context).size.width *
        MediaQuery.of(context).devicePixelRatio;
    final maxDimension = screenWidth.toInt() * 2;

    final baseProvider = MemoryImage(bytes);
    final ImageProvider<Object> provider = bytes.length > 5 * 1024 * 1024
        ? ResizeImage(baseProvider, width: maxDimension, allowUpscaling: false)
        : baseProvider;

    _imageProviderCache[path] = provider;
    while (_imageProviderCache.length > 40) {
      final evicted = _imageProviderCache.keys.first;
      _imageProviderCache.remove(evicted);
      debugPrint('[PhotoViewer] Evicted ImageProvider for: $evicted');
    }

    return provider;
  }

  void _goTo(int idx) {
    if (idx < 0 || idx >= widget.photos.length) return;
    _controller.animateToPage(
      idx,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  // 获取或创建指定索引的 TransformationController
  TransformationController _getTransformController(int index) {
    return _transformControllers.putIfAbsent(index, () {
      final controller = TransformationController();
      controller.addListener(() {
        // 实时检测缩放状态
        final scale = controller.value.getMaxScaleOnAxis();
        final shouldBeZoomed = scale > 1.01;
        if (_isZoomed != shouldBeZoomed) {
          setState(() => _isZoomed = shouldBeZoomed);
        }
      });
      return controller;
    });
  }

  // 构建带缩放的 InteractiveViewer
  // panEnabled 仅在放大时启用，避免与 PageView 争投单指手势
  Widget _buildInteractiveImage(int pageIndex, Widget child) {
    return InteractiveViewer(
      transformationController: _getTransformController(pageIndex),
      panEnabled: _isZoomed, // 未放大时禁止平移，让 PageView 处理单指滑动
      scaleEnabled: true,
      minScale: 0.5,
      maxScale: 5,
      child: Center(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.photos[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('${current.name}  (${_index + 1}/${widget.photos.length})'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
            IconButton(
              tooltip: '打开所在文件夹',
              onPressed: _openSavedFolder,
              icon: const Icon(Icons.folder_open),
            ),
          IconButton(
            tooltip: '下载 (Ctrl/Cmd+S)',
            onPressed: _saveCurrent,
            icon: const Icon(Icons.download),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ColoredBox(
        color: Colors.black,
        child: FocusableActionDetector(
          focusNode: _focusNode,
          autofocus: true,
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.arrowRight): _nextIntent,
            const SingleActivator(LogicalKeyboardKey.arrowLeft): _prevIntent,
            const SingleActivator(LogicalKeyboardKey.escape): _escapeIntent,
            const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                _saveIntent,
            const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
                _saveIntent,
            const SingleActivator(LogicalKeyboardKey.delete): _deleteIntent,
          },
          actions: <Type, Action<Intent>>{
            NextPhotoIntent: CallbackAction<NextPhotoIntent>(
              onInvoke: (_) {
                _goTo(_index + 1);
                return null;
              },
            ),
            PrevPhotoIntent: CallbackAction<PrevPhotoIntent>(
              onInvoke: (_) {
                _goTo(_index - 1);
                return null;
              },
            ),
            EscapeViewerIntent: CallbackAction<EscapeViewerIntent>(
              onInvoke: (_) {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
                return null;
              },
            ),
            SavePhotoIntent: CallbackAction<SavePhotoIntent>(
              onInvoke: (_) {
                _saveCurrent();
                return null;
              },
            ),
            DeletePhotoIntent: CallbackAction<DeletePhotoIntent>(
              onInvoke: (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('删除功能未实现：需要后端删除接口')),
                );
                return null;
              },
            ),
          },
          child: Listener(
            onPointerDown: (_) {
              _pointerCount++;
              if (_pointerCount >= 2) setState(() {}); // 双指触摸时立即禁用 PageView
            },
            onPointerUp: (_) {
              _pointerCount--;
              if (_pointerCount < 2) setState(() {}); // 手指抬起后恢复
            },
            onPointerCancel: (_) {
              _pointerCount--;
              if (_pointerCount < 2) setState(() {});
            },
            child: PageView.builder(
              controller: _controller,
              physics: (_isZoomed || _pointerCount >= 2)
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: widget.photos.length,
              onPageChanged: (i) {
                setState(() {
                  _index = i;
                  final controller = _transformControllers[i];
                  if (controller != null) {
                    _isZoomed = controller.value.getMaxScaleOnAxis() > 1.01;
                  } else {
                    _isZoomed = false;
                  }
                });
                _prefetchAround(i);
              },
              itemBuilder: (context, i) {
                final p = widget.photos[i];
                final heroTag = 'photo_hero_${p.path}';
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                debugPrint(
                  '[PhotoViewer][$timestamp] itemBuilder called for index $i: ${p.path}',
                );

                // 检查是否有缓存的 ImageProvider（已预解码）
                final cachedProvider = _imageProviderCache[p.path];
                if (cachedProvider != null) {
                  return _buildInteractiveImage(
                    i,
                    Hero(
                      tag: heroTag,
                      child: Image(
                        image: cachedProvider,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  );
                }

                // 同步检查内存缓存，命中则创建 ImageProvider
                final cached = OriginalPhotoManager.instance.getIfPresent(
                  p.path,
                );
                if (cached != null) {
                  final provider = _getOrCreateImageProvider(p.path, cached);
                  return _buildInteractiveImage(
                    i,
                    Hero(
                      tag: heroTag,
                      child: Image(
                        image: provider,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  );
                }

                // 未命中内存缓存，使用 FutureBuilder 异步加载
                return _buildInteractiveImage(
                  i,
                  Hero(
                    tag: heroTag,
                    child: FutureBuilder<Uint8List>(
                      future: _loadOriginal(p),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const ColoredBox(
                            color: Colors.black,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          );
                        }
                        if (snapshot.hasError || snapshot.data == null) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.broken_image,
                                  color: Colors.white,
                                  size: 64,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '加载失败',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  onPressed: () => setState(() {}),
                                  child: const Text('重试'),
                                ),
                              ],
                            ),
                          );
                        }
                        final provider = _getOrCreateImageProvider(
                          p.path,
                          snapshot.data!,
                        );
                        return Image(
                          image: provider,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        );
                      },
                    ),
                  ),
                );
              },
            ), // PageView.builder
          ), // Listener
        ),
      ),
    );
  }

  Future<void> _saveCurrent() async {
    final photo = widget.photos[_index];
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('正在保存...')));
      final data = await _loadOriginal(photo);
      // 选择保存策略：移动端 -> 系统相册；桌面端 -> 用户图片目录
      if (Platform.isAndroid || Platform.isIOS) {
        // 使用 saver_gallery：Android 保存到 Pictures/TPhotos，且保留原始扩展名（避免 .png.jpg）
        final fileName = _safeFileName(photo.name); // 保留已有扩展；无扩展则补 .jpg
        final result = await SaverGallery.saveImage(
          data,
          quality: 100,
          fileName: fileName,
          androidRelativePath: 'Pictures/TPhotos',
          skipIfExists: false,
        );
        if (!mounted) return;
        // saver_gallery 返回 SaveResult
        final success = (result.isSuccess == true);
        if (success) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已保存到系统相册')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '保存失败: ${result.errorMessage ?? result.toString()}',
              ),
            ),
          );
        }
      } else {
        // 桌面：保存到用户图片目录
        final picturesDir = _getUserPicturesDir();
        if (picturesDir == null) {
          // 退化到临时目录
          final dir = Directory(p.join(Directory.systemTemp.path, 'tphotos'));
          if (!await dir.exists()) await dir.create(recursive: true);
          final filePath = p.join(dir.path, _ensureExtension(photo.name));
          await File(filePath).writeAsBytes(data, flush: true);
          _lastSavedPath = filePath;
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('已保存到: $filePath')));
          return;
        }
        final appDir = Directory(p.join(picturesDir.path, 'TPhotos'));
        if (!await appDir.exists()) await appDir.create(recursive: true);
        final filePath = p.join(appDir.path, _ensureExtension(photo.name));
        await File(filePath).writeAsBytes(data, flush: true);
        _lastSavedPath = filePath;
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已保存到: $filePath')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  Future<void> _openSavedFolder() async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    final path = _lastSavedPath;
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先下载保存一张图片')));
      return;
    }
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isLinux) {
        final dir = p.dirname(path);
        await Process.run('xdg-open', [dir]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('打开文件夹失败: $e')));
    }
  }

  // 获取用户图片目录（桌面平台）
  Directory? _getUserPicturesDir() {
    try {
      if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null)
          return Directory(p.join(userProfile, 'Pictures'));
      } else if (Platform.isMacOS) {
        final home = Platform.environment['HOME'];
        if (home != null) return Directory(p.join(home, 'Pictures'));
      } else if (Platform.isLinux) {
        final home = Platform.environment['HOME'];
        if (home != null) {
          // XDG 图片目录，若无则默认 ~/Pictures
          final xdg = Platform.environment['XDG_PICTURES_DIR'];
          if (xdg != null && xdg.isNotEmpty) return Directory(xdg);
          return Directory(p.join(home, 'Pictures'));
        }
      }
    } catch (_) {}
    return null;
  }

  String _safeFileName(String name) {
    final base = _ensureExtension(name);
    // 移除不合法字符
    final sanitized = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return sanitized;
  }

  String _ensureExtension(String name) {
    if (name.contains('.')) return name;
    return '$name.jpg';
  }
}

// ---- Keyboard Intents ----
class NextPhotoIntent extends Intent {
  const NextPhotoIntent();
}

class PrevPhotoIntent extends Intent {
  const PrevPhotoIntent();
}

class EscapeViewerIntent extends Intent {
  const EscapeViewerIntent();
}

class SavePhotoIntent extends Intent {
  const SavePhotoIntent();
}

class DeletePhotoIntent extends Intent {
  const DeletePhotoIntent();
}
