import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../api/tos_api.dart';
import '../models/album_models.dart';
import '../widgets/adaptive_scrollbar.dart';
import '../widgets/collection_tile.dart';
import '../widgets/thumbnail_manager.dart';
import 'album_detail_page.dart';

/// 相册列表页面
///
/// 纯列表展示，点击相册通过 Navigator.push 打开 [AlbumDetailPage]。
class AlbumsPage extends StatefulWidget {
  final TosAPI api;

  const AlbumsPage({super.key, required this.api});

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> {
  List<AlbumInfo> _albums = [];
  bool _loading = true;
  String? _error;

  final ScrollController _scrollController = ScrollController();
  final Map<String, ValueNotifier<Uint8List?>> _thumbNotifiers = {};

  // 请求版本号，用于忽略过时的响应
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final n in _thumbNotifiers.values) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAlbums({bool forceRefresh = false}) async {
    final currentVersion = ++_loadVersion;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await widget.api.photos.albumList();

      if (!mounted || currentVersion != _loadVersion) return;

      if (response.code) {
        setState(() {
          _albums = response.data;
          _loading = false;
        });
        _preloadAlbumCovers();
      } else {
        setState(() {
          _error = response.msg.isEmpty ? '加载失败' : response.msg;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted || currentVersion != _loadVersion) return;
      setState(() {
        _error = '加载失败: $e';
        _loading = false;
      });
    }
  }

  ValueNotifier<Uint8List?> _thumbNotifierFor(String path) {
    return _thumbNotifiers.putIfAbsent(
      path,
      () => ValueNotifier<Uint8List?>(null),
    );
  }

  void _preloadAlbumCovers() {
    for (final album in _albums.take(20)) {
      for (final cover in album.exhibition.take(4)) {
        _ensureCoverLoaded(cover.thumbnailPath);
      }
    }
  }

  Future<void> _ensureCoverLoaded(String thumbnailPath) async {
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

  void _openAlbum(AlbumInfo album) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailPage(api: widget.api, album: album),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildStatus(
        icon: Icons.error_outline,
        iconColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
        message: _error!,
        onRetry: () => _loadAlbums(forceRefresh: true),
      );
    }

    if (_albums.isEmpty) {
      return _buildStatus(
        icon: Icons.photo_album,
        iconColor: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.3),
        message: '暂无相册',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadAlbums(forceRefresh: true),
      child: AdaptiveScrollbar(
        controller: _scrollController,
        child: GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.72,
          ),
          itemCount: _albums.length,
          itemBuilder: (context, index) {
            final album = _albums[index];
            // 为每张封面准备 notifier 并确保加载
            final notifiers = album.exhibition.take(4).map((e) {
              _ensureCoverLoaded(e.thumbnailPath);
              return _thumbNotifierFor(e.thumbnailPath);
            }).toList();

            return CollectionTile(
              title: album.name,
              subtitle: '${album.count} 张照片',
              thumbnailNotifiers: notifiers,
              defaultIcon: Icons.photo_album,
              onTap: () => _openAlbum(album),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatus({
    required IconData icon,
    required Color iconColor,
    required String message,
    VoidCallback? onRetry,
  }) {
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
}
