import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../api/tos_api.dart';
import '../models/folder_models.dart';
import '../models/photo_list_models.dart';

/// 文件夹内容缓存
class _FolderContentCache {
  final List<FolderInfo> folders;
  final List<PhotoItem> photos;
  final DateTime cachedAt;

  _FolderContentCache({
    required this.folders,
    required this.photos,
  }) : cachedAt = DateTime.now();
}

/// 文件夹页面
class FoldersPage extends StatefulWidget {
  final TosAPI api;
  
  const FoldersPage({Key? key, required this.api}) : super(key: key);

  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  List<FolderInfo> _folders = [];
  List<PhotoItem> _photos = [];  // 当前文件夹下的照片
  bool _isLoading = true;
  String? _errorMessage;
  
  // 缩略图缓存（文件夹和照片共用）
  final Map<String, Uint8List> _thumbnailCache = {};
  
  // 文件夹内容缓存（按路径存储）
  final Map<String, _FolderContentCache> _folderContentCache = {};
  
  // 当前文件夹路径（用于支持子文件夹导航）
  String _currentFolderPath = '/';
  String _currentRelativePath = '';  // 当前的相对路径（用于显示）
  
  // 面包屑导航历史（存储搜索路径和相对路径）
  final List<Map<String, String>> _pathHistory = [{'search': '/', 'relative': ''}];
  
  // 请求版本号，用于忽略过时的响应
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders({bool forceRefresh = false}) async {
    // 强制刷新时清除当前路径的缓存
    if (forceRefresh) {
      _clearCache(_currentFolderPath);
    }
    
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
    
    // 递增版本号，标记新请求
    final currentVersion = ++_loadVersion;
    
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

  /// 预加载缩略图（文件夹和照片）
  Future<void> _preloadThumbnails() async {
    // 预加载文件夹缩略图
    for (final folder in _folders) {
      if (folder.hasThumbnail) {
        // 加载最多4个缩略图
        final thumbnails = folder.additional.thumbnail.take(4);
        for (final thumb in thumbnails) {
          final thumbnailPath = thumb.thumbnailPath;
          if (!_thumbnailCache.containsKey(thumbnailPath)) {
            try {
              final bytes = await widget.api.photos.thumbnailBytes(thumbnailPath);
              if (mounted) {
                setState(() {
                  _thumbnailCache[thumbnailPath] = Uint8List.fromList(bytes);
                });
              }
            } catch (e) {
              // 忽略缩略图加载失败
              debugPrint('加载文件夹缩略图失败: $thumbnailPath, $e');
            }
          }
        }
      }
    }
    
    // 预加载照片缩略图（前20张）
    final photosToPreload = _photos.take(20);
    for (final photo in photosToPreload) {
      final thumbnailPath = photo.thumbnailPath;
      if (!_thumbnailCache.containsKey(thumbnailPath)) {
        try {
          final bytes = await widget.api.photos.thumbnailBytes(thumbnailPath);
          if (mounted) {
            setState(() {
              _thumbnailCache[thumbnailPath] = Uint8List.fromList(bytes);
            });
          }
        } catch (e) {
          // 忽略缩略图加载失败
          debugPrint('加载照片缩略图失败: $thumbnailPath, $e');
        }
      }
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
    return WillPopScope(
      onWillPop: () async {
        // 如果在子目录，返回上一级而不是退出页面
        if (_pathHistory.length > 1) {
          _goBack();
          return false; // 阻止退出
        }
        return true; // 允许退出
      },
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Column(
        children: [
          // 面包屑导航
          _buildBreadcrumb(),
          
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
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
                          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
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
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '暂无内容',
                          style: TextStyle(fontSize: 16),
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

    return RefreshIndicator(
      onRefresh: () => _loadFolders(forceRefresh: true),
      child: Column(
        children: [
          // 面包屑导航（始终显示）
          _buildBreadcrumb(),
          
          // 混合内容（文件夹 + 照片）
          Expanded(
            child: CustomScrollView(
              slivers: [
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
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
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
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                        childAspectRatio: 1.0,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildPhotoTile(_photos[index]),
                        childCount: _photos.length,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
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
                color: isFirst 
                    ? Theme.of(context).colorScheme.primary
                    : null,
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
          _buildFolderThumbnail(folder),
          
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

  /// 构建文件夹缩略图
  Widget _buildFolderThumbnail(FolderInfo folder) {
    const size = 120.0;
    const borderRadius = 8.0;

    Widget content;

    if (folder.hasThumbnail) {
      final thumbnails = folder.additional.thumbnail.take(4).toList();
      
      if (thumbnails.length == 1) {
        // 单个缩略图，全屏显示
        content = _buildSingleThumbnail(thumbnails[0].thumbnailPath, size);
      } else {
        // 多个缩略图，使用2x2网格
        content = _buildMultipleThumbnails(thumbnails, size);
      }
    } else {
      // 无缩略图，显示默认图标
      content = _buildDefaultIcon();
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
      ),
    );
  }

  /// 构建单个缩略图
  Widget _buildSingleThumbnail(String thumbnailPath, double size) {
    final cachedBytes = _thumbnailCache[thumbnailPath];

    if (cachedBytes != null) {
      return Image.memory(
        cachedBytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildDefaultIcon();
        },
      );
    } else {
      return _buildPlaceholder(
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }
  }

  /// 构建多个缩略图（2x2网格）
  Widget _buildMultipleThumbnails(List<FolderThumbnail> thumbnails, double size) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 0.5,
        crossAxisSpacing: 0.5,
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        if (index < thumbnails.length) {
          final thumbnailPath = thumbnails[index].thumbnailPath;
          final cachedBytes = _thumbnailCache[thumbnailPath];

          if (cachedBytes != null) {
            return Image.memory(
              cachedBytes,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildGridPlaceholder();
              },
            );
          } else {
            return _buildGridPlaceholder(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ),
            );
          }
        } else {
          // 空位
          return _buildGridPlaceholder();
        }
      },
    );
  }

  /// 构建网格单元格占位
  Widget _buildGridPlaceholder({Widget? child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? Colors.grey[850] : Colors.grey[200],
      child: child != null ? Center(child: child) : null,
    );
  }

  /// 构建默认图标
  Widget _buildDefaultIcon() {
    return _buildPlaceholder(
      child: Icon(
        Icons.folder,
        size: 48,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
      ),
    );
  }

  /// 构建占位容器
  Widget _buildPlaceholder({required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 120,
      height: 120,
      color: isDark ? Colors.grey[800] : Colors.grey[300],
      child: Center(child: child),
    );
  }

  /// 构建照片瓦片
  Widget _buildPhotoTile(PhotoItem photo) {
    final thumbnailPath = photo.thumbnailPath;
    final cachedBytes = _thumbnailCache[thumbnailPath];

    return InkWell(
      onTap: () {
        // TODO: 打开照片详情
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[850]
              : Colors.grey[200],
        ),
        child: cachedBytes != null
            ? Image.memory(
                cachedBytes,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                  );
                },
              )
            : FutureBuilder<Uint8List>(
                future: _loadPhotoThumbnail(thumbnailPath),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Image.memory(
                      snapshot.data!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Icon(
                            Icons.broken_image,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                        );
                      },
                    );
                  } else if (snapshot.hasError) {
                    return Center(
                      child: Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
                      ),
                    );
                  } else {
                    return Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                      ),
                    );
                  }
                },
              ),
      ),
    );
  }

  /// 加载照片缩略图
  Future<Uint8List> _loadPhotoThumbnail(String thumbnailPath) async {
    if (_thumbnailCache.containsKey(thumbnailPath)) {
      return _thumbnailCache[thumbnailPath]!;
    }

    try {
      final bytes = await widget.api.photos.thumbnailBytes(thumbnailPath);
      if (mounted) {
        setState(() {
          _thumbnailCache[thumbnailPath] = Uint8List.fromList(bytes);
        });
      }
      return Uint8List.fromList(bytes);
    } catch (e) {
      throw Exception('加载缩略图失败: $e');
    }
  }
}
