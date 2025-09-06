import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:path/path.dart' as p;
import '../api/tos_api.dart';
import '../models/timeline_models.dart';
import '../models/photo_list_models.dart';
import 'photos/photo_grid.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:video_player_control_panel/video_player_control_panel.dart';

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
  settings,
}

// ---------- ThumbnailManager: 并发限制 + 去重（in-flight dedupe）+ 内存 LRU 缓存 ----------
class ThumbnailManager {
  ThumbnailManager._internal();
  static final ThumbnailManager instance = ThumbnailManager._internal();

  /// 最大并发请求数，按需调整（4-8 常用）
  final int maxConcurrent = 6;
  int _running = 0;

  final Queue<_QueuedTask> _queue = Queue<_QueuedTask>();

  /// 正在进行的请求去重（key -> Future）
  final Map<String, Future<Uint8List>> _inFlight = {};

  /// 简单 LRU 内存缓存
  final int _memoryCapacity = 200;
  final LinkedHashMap<String, Uint8List> _memoryCache = LinkedHashMap();

  /// 对外接口：传入 key 与 fetcher（返回 List<int>）
  Future<Uint8List> load(
    String key,
    Future<List<int>> Function() fetcher,
  ) async {
    // 1) 内存缓存命中
    final mem = _memoryCache.remove(key);
    if (mem != null) {
      // 重新插入标记为最近使用
      _memoryCache[key] = mem;
      return mem;
    }

    // 2) 去重：如果已有请求在飞，就复用
    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;

    final completer = Completer<Uint8List>();
    _inFlight[key] = completer.future;

    _queue.add(
      _QueuedTask(key, () async {
        try {
          final list = await fetcher();
          final bytes = Uint8List.fromList(list);
          _putToMemory(key, bytes);
          if (!completer.isCompleted) completer.complete(bytes);
        } catch (e, st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        }
      }),
    );

    _schedule();

    return completer.future.whenComplete(() {
      _inFlight.remove(key);
    });
  }

  void _putToMemory(String key, Uint8List bytes) {
    if (_memoryCache.containsKey(key)) _memoryCache.remove(key);
    _memoryCache[key] = bytes;
    if (_memoryCache.length > _memoryCapacity) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
  }

  void _schedule() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      final task = _queue.removeFirst();
      _running++;
      task.run().whenComplete(() {
        _running--;
        // 继续调度队列
        _schedule();
      });
    }
  }

  void clearMemoryCache() => _memoryCache.clear();
}

class _QueuedTask {
  final String key;
  final Future<void> Function() run;
  _QueuedTask(this.key, this.run);
}

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
  // 每日照片缓存（key: 当日的 timestamp，值：该日的照片列表数据）
  final Map<int, PhotoListData> _datePhotoCache = {};
  final Set<int> _loadingDates = {};
  final PageController _pageController = PageController();

  // 缩略图的 ValueNotifier，用于局部更新，避免大量 FutureBuilder 重建
  final Map<String, ValueNotifier<Uint8List?>> _thumbNotifiers = {};

  // per-date UI state for sliver-based lazy building
  final Map<int, bool> _dateStarted = {}; // key -> whether fetch started
  final Map<int, List<PhotoItem>> _dateItems =
      {}; // key -> loaded items (if loaded)
  final Map<int, Future<PhotoListData>> _dateFutures = {};

  // 视频页对应日期缓存
  final Map<int, PhotoListData> _videoDateCache = {};
  final Set<int> _videoLoadingDates = {};
  final Map<int, bool> _videoDateStarted = {};
  final Map<int, List<PhotoItem>> _videoDateItems = {};
  final Map<int, Future<PhotoListData>> _videoDateFutures = {};

  ValueNotifier<Uint8List?> _thumbNotifierFor(String path) {
    return _thumbNotifiers.putIfAbsent(
      path,
      () => ValueNotifier<Uint8List?>(null),
    );
  }

  Future<void> _ensureThumbLoaded(String path) async {
    final notifier = _thumbNotifierFor(path);
    if (notifier.value != null) return; // 已经有缓存或正在加载完成
    try {
      final bytes = await ThumbnailManager.instance.load(
        path,
        () => widget.api.photos.thumbnailBytes(path),
      );
      // 不把 bytes 再存一份到页面级缓存，直接通知 UI
      notifier.value = bytes;
    } catch (e) {
      // 不要在失败时频繁抛出 setState，保持占位图显示即可
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    // dispose notifiers
    for (final n in _thumbNotifiers.values) {
      n.dispose();
    }
    super.dispose();
  }

  // 供扩展调用：更新视频日期条目，集中管理 setState，避免在 extension 异步回调里直接使用 setState 造成警告
  void updateVideoDateItems(int key, List<PhotoItem> list) {
    if (!mounted) return;
    setState(() {
      _videoDateItems[key] = list;
    });
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
    } catch (_) {
      _space = 1;
      _defaultSpace = 1;
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
      _datePhotoCache.clear();
      _dateStarted.clear();
      _dateItems.clear();
      _dateFutures.clear();
      // 重置缩略图 notifiers，避免跨空间污染 UI
      for (final n in _thumbNotifiers.values) {
        n.dispose();
      }
      _thumbNotifiers.clear();
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
    if (_dateStarted[key] == true) return;
    _dateStarted[key] = true;
    final future = _getOrLoadDatePhotos(item);
    _dateFutures[key] = future;
    future
        .then((data) {
          if (!mounted) return;
          setState(() {
            _dateItems[key] = data.photoList;
          });
          // 当 fetch 返回后，可以检查是否需要自动加载下一天（填充不足）
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _maybeRequestNextIfNotFilled(item, data.photoList.length);
          });
        })
        .catchError((_) {
          // keep started flag true so retry can be triggered by user
        })
        .whenComplete(() {
          _dateFutures.remove(key);
        });
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
    final key = item.timestamp;
    final cached = _datePhotoCache[key];
    if (cached != null) return cached;
    if (_loadingDates.contains(key)) {
      // 如果已有请求在进行，等待其完成
      while (_loadingDates.contains(key)) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _datePhotoCache[key]!;
    }
    _loadingDates.add(key);
    try {
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
      _datePhotoCache[key] = data;
      return data;
    } finally {
      _loadingDates.remove(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  '菜单',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
            ),
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
            _menuTile('设置', Icons.settings, HomeSection.settings),
          ],
        ),
      ),
      body: _buildBody(),
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
      case HomeSection.settings:
        return '设置';
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

  Widget _buildBody() {
    if (_section == HomeSection.photos) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_error != null) return Center(child: Text(_error!));

      return RefreshIndicator(
        onRefresh: () async {
          _datePhotoCache.clear();
          _dateStarted.clear();
          _dateItems.clear();
          _dateFutures.clear();
          await _load();
        },
        child: _photos.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 200),
                  Center(child: Text('暂无照片')),
                ],
              )
            : CustomScrollView(
                slivers: [
                  // For each date item we insert a header (SliverToBoxAdapter) and
                  // either a loader/empty widget or a SliverGrid for photos.
                  for (var raw in _photos)
                    ..._buildDateSlivers(raw as TimelineItem),
                ],
              ),
      );
    }
    if (_section == HomeSection.videos) {
      if (_videoLoading)
        return const Center(child: CircularProgressIndicator());
      if (_videoError != null) return Center(child: Text(_videoError!));
      return RefreshIndicator(
        onRefresh: () async {
          _videos.clear();
          await _loadVideos();
        },
        child: _videos.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 200),
                  Center(child: Text('暂无视频')),
                ],
              )
            : CustomScrollView(
                slivers: [
                  for (var raw in _videos)
                    ..._buildVideoDateSlivers(raw as TimelineItem),
                ],
              ),
      );
    }
    if (_section == HomeSection.settings) {
      return _buildSettings();
    }
    return Center(child: Text('TODO: ${_titleForSection(_section)}'));
  }

  // 构建每个日期对应的 sliver 片段（header + grid/loader）
  List<Widget> _buildDateSlivers(TimelineItem item) {
    final key = item.timestamp;
    final dateLabel =
        '${item.year}-${item.month.toString().padLeft(2, '0')}-${item.day.toString().padLeft(2, '0')}';

    // header: 使用 VisibilityDetector 在可见时触发 fetch
    final header = SliverToBoxAdapter(
      child: VisibilityDetector(
        key: Key('dategroup-${item.timestamp}'),
        onVisibilityChanged: (info) {
          if (info.visibleFraction > 0.06) {
            Future.delayed(const Duration(milliseconds: 120), () {
              if (!mounted) return;
              _startFetchForItem(item);
            });
          }
        },
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
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

    // 内容部分（根据是否 started/loaded 显示不同的 sliver）
    if (_dateStarted[key] != true) {
      // 未开始：占位（避免一次性构建大量内容）
      return [header, const SliverToBoxAdapter(child: SizedBox(height: 100))];
    }

    final items = _dateItems[key];
    if (items == null && _dateFutures[key] != null) {
      // 已经开始但未完成：显示 loader
      return [
        header,
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      ];
    }

    if (items == null || items.isEmpty) {
      // 已加载但为空，或 safety fallback
      return [
        header,
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Text('该日期无照片'),
          ),
        ),
      ];
    }

    // 有 items：使用 PhotoGrid 组件
    return [
      header,
      PhotoGrid(
        items: items,
        onPhotoTap: (p) {
          final startIndex = items.indexOf(p);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PhotoViewer(
                photos: items,
                initialIndex: startIndex < 0 ? 0 : startIndex,
                api: widget.api,
              ),
            ),
          );
        },
        thumbNotifiers: _thumbNotifiers,
        ensureThumbLoaded: _ensureThumbLoaded,
      ),
    ];
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
}

// ---------------- 视频页逻辑（与照片类似，但 file_type=1） ----------------
extension _VideosSection on _PhotosPageState {
  Future<PhotoListData> _getOrLoadDateVideos(TimelineItem item) async {
    final key = item.timestamp;
    final cached = _videoDateCache[key];
    if (cached != null) return cached;
    if (_videoLoadingDates.contains(key)) {
      while (_videoLoadingDates.contains(key)) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _videoDateCache[key]!;
    }
    _videoLoadingDates.add(key);
    try {
      final start =
          DateTime(item.year, item.month, item.day).millisecondsSinceEpoch ~/
          1000;
      final end = start + 86400 - 1;
      final data = await widget.api.photos.photoListAll(
        space: _space,
        listType: 1,
        fileType: 1,
        startTime: start,
        endTime: end,
        pageSize: 200,
        timelineType: 2,
        order: 'desc',
      );
      _videoDateCache[key] = data;
      return data;
    } finally {
      _videoLoadingDates.remove(key);
    }
  }

  void _startFetchForVideoItem(TimelineItem item) {
    final key = item.timestamp;
    if (_videoDateStarted[key] == true) return;
    _videoDateStarted[key] = true;
    final future = _getOrLoadDateVideos(item);
    _videoDateFutures[key] = future;
    future
        .then((data) {
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            updateVideoDateItems(key, data.photoList);
          });
        })
        .whenComplete(() => _videoDateFutures.remove(key));
  }

  List<Widget> _buildVideoDateSlivers(TimelineItem item) {
    final key = item.timestamp;
    final dateLabel =
        '${item.year}-${item.month.toString().padLeft(2, '0')}-${item.day.toString().padLeft(2, '0')}';

    final header = SliverToBoxAdapter(
      child: VisibilityDetector(
        key: Key('videogroup-${item.timestamp}'),
        onVisibilityChanged: (info) {
          if (info.visibleFraction > 0.06) {
            Future.delayed(const Duration(milliseconds: 120), () {
              if (!mounted) return;
              _startFetchForVideoItem(item);
            });
          }
        },
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
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

    if (_videoDateStarted[key] != true) {
      return [header, const SliverToBoxAdapter(child: SizedBox(height: 100))];
    }

    final items = _videoDateItems[key];
    if (items == null && _videoDateFutures[key] != null) {
      return [
        header,
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      ];
    }
    if (items == null || items.isEmpty) {
      return [
        header,
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Text('该日期无视频'),
          ),
        ),
      ];
    }

    return [
      header,
      PhotoGrid(
        items: items,
        onPhotoTap: (p) {
          final startIndex = items.indexOf(p);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoPlayerPage(
                videos: items,
                initialIndex: startIndex < 0 ? 0 : startIndex,
                api: widget.api,
              ),
            ),
          );
        },
        thumbNotifiers: _thumbNotifiers,
        ensureThumbLoaded: _ensureThumbLoaded,
      ),
    ];
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
        child: _controller == null
            ? const CircularProgressIndicator()
            : FutureBuilder<void>(
                future: _initFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const CircularProgressIndicator();
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
                              onNextClicked: _index >= widget.videos.length - 1
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

// ---------------- 设置页（仅“默认空间”） ----------------
extension on _PhotosPageState {
  Future<void> _onDefaultSpaceChanged(int v) async {
    return _saveDefaultSpace(v);
  }

  Widget _buildSettings() {
    return ListView(
      children: [
        const ListTile(
          title: Text('默认空间'),
          subtitle: Text('用于决定启动时加载的空间，也会立即应用到当前页面'),
        ),
        RadioListTile<int>(
          value: 1,
          groupValue: _defaultSpace,
          onChanged: (v) {
            if (v != null) _onDefaultSpaceChanged(v);
          },
          title: const Text('个人空间'),
          secondary: const Icon(Icons.person),
        ),
        RadioListTile<int>(
          value: 2,
          groupValue: _defaultSpace,
          onChanged: (v) {
            if (v != null) _onDefaultSpaceChanged(v);
          },
          title: const Text('公共空间'),
          secondary: const Icon(Icons.people),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            '提示：该设置仅影响下次启动时的默认空间，不会改变当前已加载的空间。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

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

  // 简易原图缓存与去重
  final int _memoryCapacity = 40;
  final LinkedHashMap<String, Uint8List> _memoryCache = LinkedHashMap();
  final Map<String, Future<Uint8List>> _inFlight = {};
  // Keyboard intents
  // 定义快捷键意图，配合 Shortcuts/Actions 使用
  // 置于 State 内仅为就近管理
  static final _nextIntent = NextPhotoIntent();
  static final _prevIntent = PrevPhotoIntent();
  static final _escapeIntent = EscapeViewerIntent();
  static final _saveIntent = SavePhotoIntent();
  static final _deleteIntent = DeletePhotoIntent();

  @override
  void initState() {
    super.initState();
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
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<Uint8List> _loadOriginal(String path) {
    // 内存命中
    final mem = _memoryCache.remove(path);
    if (mem != null) {
      _memoryCache[path] = mem; // LRU 触达
      return Future.value(mem);
    }
    // 去重
    final inflight = _inFlight[path];
    if (inflight != null) return inflight;

    final future = widget.api.photos.originalPhotoBytes(path).then((bytes) {
      final data = Uint8List.fromList(bytes);
      _putToMemory(path, data);
      return data;
    });
    _inFlight[path] = future;
    return future.whenComplete(() => _inFlight.remove(path));
  }

  void _putToMemory(String key, Uint8List bytes) {
    if (_memoryCache.containsKey(key)) _memoryCache.remove(key);
    _memoryCache[key] = bytes;
    if (_memoryCache.length > _memoryCapacity) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
  }

  void _prefetchAround(int idx) {
    void prefetch(int i) {
      if (i < 0 || i >= widget.photos.length) return;
      final p = widget.photos[i];
      unawaited(
        _loadOriginal(p.path).catchError((e, st) {
          debugPrint('Prefetch error for ${p.path}: $e');
          return Uint8List(0); // 返回空以满足签名
        }),
      );
    }

    prefetch(idx);
    prefetch(idx + 1);
    prefetch(idx - 1);
  }

  void _goTo(int idx) {
    if (idx < 0 || idx >= widget.photos.length) return;
    _controller.animateToPage(
      idx,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
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
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.photos.length,
            onPageChanged: (i) {
              setState(() => _index = i);
              _prefetchAround(i);
            },
            itemBuilder: (context, i) {
              final p = widget.photos[i];
              return FutureBuilder<Uint8List>(
                future: _loadOriginal(p.path),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
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
                  return InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    child: Center(
                      child: Image.memory(snapshot.data!, fit: BoxFit.contain),
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
    final photo = widget.photos[_index];
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('正在保存...')));
      final data = await _loadOriginal(photo.path);
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
