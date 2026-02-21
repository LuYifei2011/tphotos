import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:saver_gallery/saver_gallery.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../api/tos_api.dart';
import '../models/photo_list_models.dart';
import '../models/timeline_models.dart';
import '../widgets/original_photo_manager.dart';
import '../widgets/thumbnail_manager.dart';
import '../widgets/timeline_view.dart';
import 'settings_page.dart';
import 'folders_page.dart';
import 'albums_page.dart';
import 'face_page.dart';
import 'scene_page.dart';
import 'place_page.dart';

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

  // 当前空间（1: 个人空间, 2: 公共空间）
  int _space = 1;
  // 启动默认空间（仅用于设置页显示与保存，不影响当前 _space）
  int _defaultSpace = 1;

  String? _username;

  // 用于在空间切换时强制重建 TimelineView
  int _spaceVersion = 0;

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
  }

  Future<void> _onSpaceChanged(int v) async {
    if (v != 1 && v != 2) return;
    if (v == _space) return;
    setState(() {
      _space = v;
      _spaceVersion++;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('space', _space);
    } catch (_) {}
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

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _drawerOpen = false;
  final FolderBackHandler _folderBackHandler = FolderBackHandler();

  @override
  Widget build(BuildContext context) {
    // 侧栏打开时拦截返回并手动关闭侧栏，避免路由级返回抢占
    // 文件夹子目录时拦截返回并先回到上一级目录
    // 照片主页允许系统返回（退出应用）
    final canPop =
        !_drawerOpen &&
        !(_section == HomeSection.folders && _folderBackHandler.canGoBack) &&
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

        // 不在照片页面时，切回照片页面
        if (_section != HomeSection.photos) {
          setState(() {
            _section = HomeSection.photos;
          });
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
          });
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
      return TimelineView(
        key: ValueKey('photo-$_space-$_spaceVersion'),
        loadTimeline: () => _loadPhotoTimeline(fileType: 0),
        loadPhotosForDate: (item) => _loadPhotosForDate(item, fileType: 0),
        loadThumbnail: (path) => widget.api.photos.thumbnailBytes(path),
        api: widget.api,
        keyPrefix: 'dategroup-photo',
        emptyLabel: '暂无照片',
        emptyDateLabel: '该日期无照片',
      );
    }
    if (_section == HomeSection.videos) {
      return TimelineView(
        key: ValueKey('video-$_space-$_spaceVersion'),
        loadTimeline: () => _loadPhotoTimeline(fileType: 1),
        loadPhotosForDate: (item) => _loadPhotosForDate(item, fileType: 1),
        loadThumbnail: (path) => widget.api.photos.thumbnailBytes(path),
        api: widget.api,
        keyPrefix: 'videogroup',
        emptyLabel: '暂无视频',
        emptyDateLabel: '该日期无视频',
        isVideoMode: true,
      );
    }
    if (_section == HomeSection.folders) {
      return FoldersPage(api: widget.api, backHandler: _folderBackHandler);
    }
    if (_section == HomeSection.albums) {
      return AlbumsPage(api: widget.api);
    }
    if (_section == HomeSection.people) {
      return FacePage(api: widget.api, space: _space);
    }
    if (_section == HomeSection.scenes) {
      return ScenePage(api: widget.api, space: _space);
    }
    if (_section == HomeSection.places) {
      return PlacePage(api: widget.api, space: _space);
    }
    return Center(child: Text('该页面尚未实现哦~\uD83D\uDE42'));
  }

  Future<List<TimelineItem>> _loadPhotoTimeline({required int fileType}) async {
    final res = await widget.api.photos.timeline(
      space: _space,
      fileType: fileType,
      timelineType: 2,
      order: 'desc',
    );
    return res.data;
  }

  Future<PhotoListData> _loadPhotosForDate(
    TimelineItem item, {
    required int fileType,
  }) async {
    final start =
        DateTime(item.year, item.month, item.day).millisecondsSinceEpoch ~/
        1000;
    final end = start + 86400 - 1;
    return widget.api.photos.photoListAll(
      space: _space,
      listType: 1,
      fileType: fileType,
      startTime: start,
      endTime: end,
      pageSize: 200,
      timelineType: 2,
      order: 'desc',
    );
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
  late final Player _player;
  late final VideoController _controller;
  // 已下载的临时文件缓存，用于保存功能
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
    _player = Player();
    _controller = VideoController(_player);
    _player.stream.error.listen((error) {
      if (kDebugMode) debugPrint('[VideoPlayer][ERR] $error');
      if (mounted) setState(() => _lastError = error);
    });
    _player.stream.completed.listen((completed) {
      if (!completed || !mounted) return;
      if (_index < widget.videos.length - 1) {
        _next();
      }
    });
    _applyDecodeSettingAndLoad();
  }

  Future<void> _applyDecodeSettingAndLoad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hwDecode = prefs.getBool('video_hardware_decode') ?? true;
      final hwdecValue = hwDecode ? 'auto' : 'no';
      if (kDebugMode) debugPrint('[VideoPlayer] hwdec=$hwdecValue');
      await ((_player.platform) as NativePlayer).setProperty(
        'hwdec',
        hwdecValue,
      );
    } catch (e) {
      if (kDebugMode)
        debugPrint('[VideoPlayer][WARN] setProperty hwdec failed: $e');
    }
    _loadCurrent();
  }

  @override
  void dispose() {
    _player.dispose();
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
      debugPrint('[VideoPlayer] stream index=$_index name=${item.name}');
    final uri = widget.api.photos.videoStreamUri(item.path);
    final headers = widget.api.photos.videoStreamHeaders();
    if (mounted) setState(() => _lastError = null);
    try {
      await _player.open(Media(uri.toString(), httpHeaders: headers));
      await _player.play();
      if (kDebugMode) debugPrint('[VideoPlayer] opened uri=$uri');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[VideoPlayer][ERR] open failed: $e\n$st');
      if (mounted) setState(() => _lastError = '$e');
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
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    // 桌面平台自定义控制栏（prev/play/next/volume/position/spacer/fullscreen）
    final desktopBottomBar = [
      IconButton(
        icon: const Icon(Icons.skip_previous, color: Colors.white),
        onPressed: _index > 0 ? _prev : null,
        disabledColor: Colors.white30,
        tooltip: '上一个',
      ),
      const MaterialDesktopPlayOrPauseButton(),
      IconButton(
        icon: const Icon(Icons.skip_next, color: Colors.white),
        onPressed: _index < widget.videos.length - 1 ? _next : null,
        disabledColor: Colors.white30,
        tooltip: '下一个',
      ),
      const MaterialDesktopVolumeButton(),
      const MaterialDesktopPositionIndicator(),
      const Spacer(),
      const MaterialDesktopFullscreenButton(),
    ];

    // 移动平台控制栏
    final mobileBottomBar = [
      IconButton(
        icon: const Icon(Icons.skip_previous),
        onPressed: _index > 0 ? _prev : null,
        color: Colors.white,
        disabledColor: Colors.white30,
        tooltip: '上一个',
      ),
      const MaterialPlayOrPauseButton(),
      IconButton(
        icon: const Icon(Icons.skip_next),
        onPressed: _index < widget.videos.length - 1 ? _next : null,
        color: Colors.white,
        disabledColor: Colors.white30,
        tooltip: '下一个',
      ),
      const MaterialPositionIndicator(),
      const Spacer(),
      const MaterialFullscreenButton(),
    ];

    Widget videoWidget;
    if (isDesktop) {
      videoWidget = MaterialDesktopVideoControlsTheme(
        normal: MaterialDesktopVideoControlsThemeData(
          bottomButtonBar: desktopBottomBar,
          toggleFullscreenOnDoublePress: true, // 双击全屏
        ),
        fullscreen: MaterialDesktopVideoControlsThemeData(
          bottomButtonBar: desktopBottomBar,
        ),
        child: Video(
          controller: _controller,
          controls: MaterialDesktopVideoControls,
          fill: Colors.black,
        ),
      );
    } else {
      videoWidget = MaterialVideoControlsTheme(
        normal: MaterialVideoControlsThemeData(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
          seekBarContainerHeight: 36,
          bottomButtonBar: mobileBottomBar,
          // ================== 手势开关 ==================
          seekGesture: true, // 水平滑动 seek
          brightnessGesture: true, // 左侧调节亮度
          volumeGesture: true, // 右侧调节音量
          seekOnDoubleTap: true, // 双击快进/快退
          speedUpOnLongPress: true, // 长按倍速
          speedUpFactor: 2.0, // 倍速倍数（可改 1.5 / 3.0 等）
          // ================== 灵敏度调节 ==================
          horizontalGestureSensitivity: 800, // 数值越大越不敏感（推荐 600~1200）
          verticalGestureSensitivity: 120, // 垂直滑动灵敏度
          // 可选：控制栏显示时是否仍响应手势（全屏推荐开启）
          gesturesEnabledWhileControlsVisible: true,
        ),
        fullscreen: MaterialVideoControlsThemeData(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 32),
          seekBarContainerHeight: 36,
          bottomButtonBar: mobileBottomBar,
          // 全屏时也保持手势
          gesturesEnabledWhileControlsVisible: true,
        ),
        child: Video(
          controller: _controller,
          controls: MaterialVideoControls,
          fill: Colors.black,
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
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
      body: Column(
        children: [
          Expanded(child: videoWidget),
          if (_lastError != null)
            ColoredBox(
              color: Colors.red.shade900,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _lastError!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _loadCurrent,
                      child: const Text(
                        '重试',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    TextButton(
                      onPressed: _openExternalPlayer,
                      child: const Text(
                        '外部播放器',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
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

// 使用 media_kit Video 组件播放视频

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

  /// 原图未加载完成时，用缩略图占位 + 加载指示器
  Widget _buildThumbnailPlaceholder(PhotoItem item) {
    // 1. 先尝试同步从内存缓存取缩略图
    final cachedThumb = ThumbnailManager.instance.getIfPresent(
      item.thumbnailPath,
    );
    if (cachedThumb != null) {
      return _thumbnailWithSpinner(cachedThumb);
    }

    // 2. 异步加载缩略图
    return FutureBuilder<Uint8List>(
      future: ThumbnailManager.instance.load(
        item.thumbnailPath,
        () => widget.api.photos.thumbnailBytes(item.thumbnailPath),
        stamp: item.timestamp,
      ),
      builder: (context, thumbSnap) {
        if (thumbSnap.hasData) {
          return _thumbnailWithSpinner(thumbSnap.data!);
        }
        // 缩略图也还没加载好，显示纯黑底 + 转圈
        return const ColoredBox(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        );
      },
    );
  }

  /// 缩略图 + 半透明加载指示器叠加
  Widget _thumbnailWithSpinner(Uint8List thumbBytes) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Image.memory(
          thumbBytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          width: double.infinity,
          height: double.infinity,
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(12),
          child: const CircularProgressIndicator(color: Colors.white),
        ),
      ],
    );
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

  Widget _buildNavButton(IconData icon, VoidCallback? onPressed) {
    return AnimatedOpacity(
      opacity: onPressed != null ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: Colors.black45,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
      ),
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            FocusableActionDetector(
              focusNode: _focusNode,
              autofocus: true,
              shortcuts: <ShortcutActivator, Intent>{
                const SingleActivator(LogicalKeyboardKey.arrowRight):
                    _nextIntent,
                const SingleActivator(LogicalKeyboardKey.arrowLeft):
                    _prevIntent,
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
                      final provider = _getOrCreateImageProvider(
                        p.path,
                        cached,
                      );
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
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              // 原图尚未加载完成，使用缩略图占位
                              return _buildThumbnailPlaceholder(p);
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
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
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
                              frameBuilder:
                                  (
                                    context,
                                    child,
                                    frame,
                                    wasSynchronouslyLoaded,
                                  ) {
                                    // 已同步加载或首帧已就绪，直接显示原图
                                    if (wasSynchronouslyLoaded ||
                                        frame != null) {
                                      return child;
                                    }
                                    // 字节已到达但解码尚未完成，继续显示缩略图防止空白
                                    return _buildThumbnailPlaceholder(p);
                                  },
                            );
                          },
                        ),
                      ),
                    );
                  },
                ), // PageView.builder
              ), // Listener
            ), // FocusableActionDetector
            if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) ...[
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _buildNavButton(
                    Icons.chevron_left,
                    _index > 0 ? () => _goTo(_index - 1) : null,
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _buildNavButton(
                    Icons.chevron_right,
                    _index < widget.photos.length - 1
                        ? () => _goTo(_index + 1)
                        : null,
                  ),
                ),
              ),
            ],
          ], // Stack children
        ), // Stack
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
