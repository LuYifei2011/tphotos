import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../api/tos_api.dart';
import '../models/folder_models.dart';
import '../models/photo_list_models.dart';
import '../widgets/adaptive_scrollbar.dart';
import '../widgets/folder_thumbnail.dart';
import '../widgets/photo_grid.dart';
import '../widgets/thumbnail_manager.dart';
import '../widgets/media_viewer_helper.dart';

/// 文件夹内容缓存
class _FolderContentCache {
  final List<FolderInfo> folders;
  final List<PhotoItem> photos;
  final DateTime cachedAt;

  _FolderContentCache({required this.folders, required this.photos})
    : cachedAt = DateTime.now();
}

/// 文件夹返回控制器，用于父页面查询和触发文件夹返回操作
class FolderBackHandler {
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

/// 文件夹页面
class FoldersPage extends StatefulWidget {
  final TosAPI api;
  final FolderBackHandler? backHandler;

  const FoldersPage({super.key, required this.api, this.backHandler});

  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  List<FolderInfo> _folders = [];
  List<PhotoItem> _photos = []; // 当前文件夹下的照片
  bool _isLoading = true;
  String? _errorMessage;

  // 滚动控制器
  final ScrollController _scrollController = ScrollController();

  // 缩略图 ValueNotifier，与 photos_page 共享 ThumbnailManager 缓存
  final Map<String, ValueNotifier<Uint8List?>> _thumbNotifiers = {};

  // 文件夹内容缓存（按路径存储）
  final Map<String, _FolderContentCache> _folderContentCache = {};

  // 当前文件夹路径（用于支持子文件夹导航）
  String _currentFolderPath = '/';
  String _currentRelativePath = ''; // 当前的相对路径（用于显示）

  // 面包屑导航历史（存储搜索路径和相对路径）
  final List<Map<String, String>> _pathHistory = [
    {'search': '/', 'relative': ''},
  ];

  // 请求版本号，用于忽略过时的响应
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    widget.backHandler?.attach(
      canGoBack: () => _pathHistory.length > 1,
      goBack: _goBack,
    );
    _loadFolders();
  }

  Future<void> _loadFolders({bool forceRefresh = false}) async {
    // 强制刷新时清除当前路径的缓存
    if (forceRefresh) {
      _clearCache(_currentFolderPath);
    }

    // 递增版本号，使之前的异步请求失效
    final currentVersion = ++_loadVersion;

    // 检查缓存
    if (!forceRefresh && _folderContentCache.containsKey(_currentFolderPath)) {
      final cached = _folderContentCache[_currentFolderPath]!;
      setState(() {
        _folders = cached.folders;
        _photos = cached.photos;
        _isLoading = false;
        _errorMessage = null;
      });
      // 预加载缩略图
      _preloadThumbnails();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 同时请求文件夹和照片
      final results = await Future.wait([
        widget.api.photos.folderMode(
          folderName: _currentFolderPath,
          space: 2,
          sortType: 1,
          sortDirection: 'desc',
        ),
        widget.api.photos.photoListByFolder(
          space: 2,
          searchFolder: _currentFolderPath,
          sortType: 1,
          sortDirection: 'desc',
          pageIndex: 1,
          pageSize: 150,
        ),
      ]);

      // 检查是否是最新请求的响应
      if (!mounted || currentVersion != _loadVersion) {
        return; // 忽略过时响应
      }

      final folderResponse = results[0] as FolderModeResponse;
      final photoResponse = results[1] as PhotoListResponse;

      if (folderResponse.code && photoResponse.code) {
        final folders = folderResponse.data.photoDirInfo;
        final photos = photoResponse.data.photoList;

        // 缓存结果
        _folderContentCache[_currentFolderPath] = _FolderContentCache(
          folders: folders,
          photos: photos,
        );

        setState(() {
          _folders = folders;
          _photos = photos;
          _isLoading = false;
        });

        // 预加载缩略图
        _preloadThumbnails();
      } else {
        setState(() {
          _errorMessage = folderResponse.msg.isEmpty
              ? (photoResponse.msg.isEmpty ? '加载失败' : photoResponse.msg)
              : folderResponse.msg;
          _isLoading = false;
        });
      }
    } catch (e) {
      // 检查是否是最新请求的响应
      if (!mounted || currentVersion != _loadVersion) {
        return; // 忽略过时响应
      }

      setState(() {
        _errorMessage = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  ValueNotifier<Uint8List?> _thumbNotifierFor(String path) {
    return _thumbNotifiers.putIfAbsent(
      path,
      () => ValueNotifier<Uint8List?>(null),
    );
  }

  Future<void> _ensureThumbLoaded(String thumbnailPath) async {
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
        debugPrint('缩略图加载失败: $thumbnailPath, $e');
      }
    }
  }

  /// 预加载缩略图（照片）
  void _preloadThumbnails() {
    // 文件夹缩略图由 FolderThumbnailWidget 自动加载

    // 预加载照片缩略图（前20张）
    for (final photo in _photos.take(20)) {
      _ensureThumbLoaded(photo.thumbnailPath);
    }
  }

  /// 清除指定路径的缓存
  void _clearCache(String? path) {
    if (path != null) {
      _folderContentCache.remove(path);
    } else {
      _folderContentCache.clear();
    }
  }

  /// 进入子文件夹
  void _enterFolder(FolderInfo folder) {
    setState(() {
      _currentFolderPath = folder.searchPhotoDir;
      _currentRelativePath = folder.relativelyPath;
      _pathHistory.add({
        'search': folder.searchPhotoDir,
        'relative': folder.relativelyPath,
      });
    });
    _loadFolders();
  }

  /// 返回指定层级
  void _navigateToLevel(int level) {
    if (level < _pathHistory.length) {
      setState(() {
        _pathHistory.removeRange(level + 1, _pathHistory.length);
        final target = _pathHistory[level];
        _currentFolderPath = target['search']!;
        _currentRelativePath = target['relative']!;
      });
      _loadFolders();
    }
  }

  /// 返回上一级
  void _goBack() {
    if (_pathHistory.length > 1) {
      setState(() {
        _pathHistory.removeLast();
        final target = _pathHistory.last;
        _currentFolderPath = target['search']!;
        _currentRelativePath = target['relative']!;
      });
      _loadFolders();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildBody();
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Column(
        children: [
          // 面包屑导航
          _buildBreadcrumb(),

          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    if (_errorMessage != null) {
      return RefreshIndicator(
        onRefresh: () => _loadFolders(forceRefresh: true),
        child: Column(
          children: [
            // 面包屑导航
            _buildBreadcrumb(),

            Expanded(
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
                          color: Theme.of(
                            context,
                          ).colorScheme.error.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _loadFolders(forceRefresh: true),
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_folders.isEmpty && _photos.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadFolders(forceRefresh: true),
        child: Column(
          children: [
            // 面包屑导航
            _buildBreadcrumb(),

            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height - 200,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder_open,
                          size: 64,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        const Text('暂无内容', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadFolders(forceRefresh: true),
      child: Column(
        children: [
          // 面包屑导航（始终显示）
          _buildBreadcrumb(),

          // 混合内容（文件夹 + 照片）
          Expanded(
            child: AdaptiveScrollbar(
              controller: _scrollController,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: _buildContentSlivers(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建内容 slivers（文件夹 + 照片）
  List<Widget> _buildContentSlivers() {
    return [
      // 文件夹网格
      if (_folders.isNotEmpty) ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Text(
              '文件夹',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.68,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildFolderTile(_folders[index]),
              childCount: _folders.length,
            ),
          ),
        ),
      ],

      // 照片网格
      if (_photos.isNotEmpty) ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Text(
              '照片',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        PhotoGrid(
          items: _photos,
          onPhotoTap: (item) {
            MediaViewerHelper.openMediaViewer(
              context,
              items: _photos,
              initialIndex: _photos.indexOf(item),
              api: widget.api,
            );
          },
          thumbNotifiers: _thumbNotifiers,
          ensureThumbLoaded: (item) => _ensureThumbLoaded(item.thumbnailPath),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1.0,
          ),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      ],
    ];
  }

  /// 构建面包屑导航
  Widget _buildBreadcrumb() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 将相对路径分割成段
    final pathSegments = _currentRelativePath.isEmpty
        ? <String>[]
        : _currentRelativePath.split('/');

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // 返回按钮（仅在非根目录时显示）
          if (_pathHistory.length > 1)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _goBack,
              iconSize: 20,
              padding: const EdgeInsets.all(8),
            ),

          // 根目录/全部
          _buildBreadcrumbItem(
            label: '全部',
            icon: Icons.home,
            onTap: () => _navigateToLevel(0),
            isFirst: true,
          ),

          // 各级路径段
          for (int i = 0; i < pathSegments.length; i++) ...[
            _buildBreadcrumbSeparator(),
            _buildBreadcrumbItem(
              label: pathSegments[i],
              onTap: () => _navigateToLevel(i + 1),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建面包屑项
  Widget _buildBreadcrumbItem({
    required String label,
    IconData? icon,
    required VoidCallback onTap,
    bool isFirst = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isFirst ? FontWeight.w600 : FontWeight.normal,
                color: isFirst ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建面包屑分隔符
  Widget _buildBreadcrumbSeparator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(
        Icons.chevron_right,
        size: 16,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
      ),
    );
  }

  /// 构建单个文件夹瓦片
  Widget _buildFolderTile(FolderInfo folder) {
    return InkWell(
      onTap: () => _enterFolder(folder),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 缩略图或默认图标
          FolderThumbnailWidget(
            folder: folder,
            loadThumbnail: (path) => widget.api.photos.thumbnailBytes(path),
          ),

          const SizedBox(height: 8),

          // 标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              folder.showFolder,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.backHandler?.detach();
    _scrollController.dispose();
    for (final n in _thumbNotifiers.values) {
      n.dispose();
    }
    super.dispose();
  }
}
