import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../api/tos_api.dart';
import '../models/timeline_models.dart';
import '../models/photo_list_models.dart';

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

class PhotosPage extends StatefulWidget {
  final TosAPI api;
  const PhotosPage({super.key, required this.api});

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
  // 缩略图内存缓存（key: thumbnailPath）
  final Map<String, Uint8List> _thumbCache = {};

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

  Widget _buildTimelineItem(BuildContext context, int index) {
    final item = _photos[index] as TimelineItem;
    return _DateGroup(
      item: item,
      fetch: () => _getOrLoadDatePhotos(item),
      loadThumb: (p) => _loadThumbBytes(p),
      api: widget.api,
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titleForSection(_section)),
        actions: [
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
                child: Text('菜单', style: TextStyle(color: Colors.white, fontSize: 20)),
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
      leading: Icon(icon, color: selected ? Theme.of(context).colorScheme.primary : null),
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
      if (_loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_error != null) {
        return Center(child: Text(_error!));
      }
      return RefreshIndicator(
        onRefresh: () async {
          _datePhotoCache.clear();
          await _load();
        },
        child: _photos.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 200),
                  Center(child: Text('暂无照片')),
                ],
              )
            : ListView.builder(
                itemCount: _photos.length,
                itemBuilder: _buildTimelineItem,
              ),
      );
    }
    // 其他栏目暂为 TODO 占位
    return Center(child: Text('TODO: ${_titleForSection(_section)}'));
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
      final start = DateTime(item.year, item.month, item.day)
          .millisecondsSinceEpoch ~/ 1000;
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

  Future<Uint8List> _loadThumbBytes(String path) async {
    final cached = _thumbCache[path];
    if (cached != null) return cached;
    final bytes = await widget.api.photos.thumbnailBytes(path);
    final data = Uint8List.fromList(bytes);
    _thumbCache[path] = data;
    return data;
  }
}

class _DateGroup extends StatelessWidget {
  final TimelineItem item;
  final Future<PhotoListData> Function() fetch;
  final Future<Uint8List> Function(String) loadThumb;
  final TosAPI api;

  const _DateGroup({
    required this.item,
    required this.fetch,
    required this.loadThumb,
    required this.api,
  });

  String get _dateLabel =>
      '${item.year}-${item.month.toString().padLeft(2, '0')}-${item.day.toString().padLeft(2, '0')}';

  Widget _buildPhotoGrid(List<PhotoItem> items) {
    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemBuilder: (context, i) {
        final p = items[i];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PhotoViewer(
                  photo: p,
                  api: api,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              fit: StackFit.expand,
              children: [
                FutureBuilder<Uint8List>(
                  future: loadThumb(p.thumbnailPath),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
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
                    if (snap.hasError || snap.data == null) {
                      return const ColoredBox(
                        color: Color(0x11000000),
                        child: Center(child: Icon(Icons.broken_image)),
                      );
                    }
                    return Image.memory(snap.data!, fit: BoxFit.cover);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                  _dateLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 8),
                Text('(${item.photoCount})',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          FutureBuilder<PhotoListData>(
            future: fetch(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('加载失败：${snapshot.error}'),
                      ),
                      TextButton(
                        onPressed: () {
                          (context as Element).markNeedsBuild();
                        },
                        child: const Text('重试'),
                      )
                    ],
                  ),
                );
              }
              final data = snapshot.data!;
              final items = data.photoList;
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                  child: Text('该日期无照片'),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: _buildPhotoGrid(items),
              );
            },
          ),
        ],
      ),
    );
  }
}

class PhotoViewer extends StatefulWidget {
  final PhotoItem photo;
  final TosAPI api;

  const PhotoViewer({
    super.key,
    required this.photo,
    required this.api,
  });

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
      final bytes = await widget.api.photos.originalPhotoBytes(widget.photo.path);
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
      body: Container(
        color: Colors.black,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.white,
              size: 64,
            ),
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
        child: Text(
          '暂无图片',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    return FutureBuilder<Uint8List>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(
              color: Colors.white,
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
                const SizedBox(height: 16),
                const Text(
                  '图片加载失败',
                  style: TextStyle(color: Colors.white),
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
        return InteractiveViewer(
          child: Center(
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
            ),
          ),
        );
      },
    );
  }
}
