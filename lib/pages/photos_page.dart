import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../api/tos_api.dart';
import '../models/timeline_models.dart';
import '../models/photo_list_models.dart';
import 'package:visibility_detector/visibility_detector.dart';

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
  bool _loading = true;
  String? _error;
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.api.photos.timeline(
        space: 2,
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
        space: 2,
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
            // debounce by small delay to avoid频繁触发
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

    // 有 items：构建 SliverGrid
    final grid = SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((context, i) {
          final p = items[i];
          // 当将来滚动到接近末尾时可以触发下一日加载
          if (i == items.length - 1) {
            // 这里不做分页，只保留触发下一日期加载的 hook
            // 可选：如果你的 API 支持分页，这里可以触发加载更多
          }

          final notifier = _thumbNotifiers.putIfAbsent(
            p.thumbnailPath,
            () => ValueNotifier<Uint8List?>(null),
          );
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PhotoViewer(photo: p, api: widget.api),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ValueListenableBuilder<Uint8List?>(
                    valueListenable: notifier,
                    builder: (context, bytes, _) {
                      if (bytes == null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _ensureThumbLoaded(p.thumbnailPath);
                        });
                        return const ColoredBox(
                          color: Color(0x11000000),
                          child: Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      return Image.memory(bytes, fit: BoxFit.cover);
                    },
                  ),
                ],
              ),
            ),
          );
        }, childCount: items.length),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 120,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
      ),
    );

    return [header, grid];
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

class PhotoViewer extends StatefulWidget {
  final PhotoItem photo;
  final TosAPI api;

  const PhotoViewer({super.key, required this.photo, required this.api});

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  Future<Uint8List>? _imageFuture;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOriginalImage();
  }

  Future<void> _loadOriginalImage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await widget.api.photos.originalPhotoBytes(
        widget.photo.path,
      );
      setState(() {
        _imageFuture = Future.value(Uint8List.fromList(bytes));
      });
    } catch (e) {
      setState(() => _error = '加载失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.photo.name),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOriginalImage,
          ),
        ],
      ),
      body: Container(color: Colors.black, child: _buildContent()),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 64),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadOriginalImage,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_imageFuture == null) {
      return const Center(
        child: Text('暂无图片', style: TextStyle(color: Colors.white)),
      );
    }
    return FutureBuilder<Uint8List>(
      future: _imageFuture,
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
                const Icon(Icons.broken_image, color: Colors.white, size: 64),
                const SizedBox(height: 16),
                const Text('图片加载失败', style: TextStyle(color: Colors.white)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadOriginalImage,
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }
        return InteractiveViewer(
          child: Center(
            child: Image.memory(snapshot.data!, fit: BoxFit.contain),
          ),
        );
      },
    );
  }
}
