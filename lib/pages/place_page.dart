import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import '../api/tos_api.dart';
import '../models/geo_models.dart';
import '../widgets/adaptive_scrollbar.dart';
import '../widgets/collection_tile.dart';
import '../widgets/thumbnail_manager.dart';
import 'place_photos_page.dart';

class PlacePage extends StatefulWidget {
  final TosAPI api;
  final int space;

  const PlacePage({super.key, required this.api, required this.space});

  @override
  State<PlacePage> createState() => _PlacePageState();
}

class _PlacePageState extends State<PlacePage> {
  List<GeoItem> _places = [];
  bool _loading = true;
  String? _error;

  final ScrollController _scrollController = ScrollController();
  final Map<String, ValueNotifier<Uint8List?>> _thumbNotifiers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PlacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.space != widget.space) {
      _load();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final notifier in _thumbNotifiers.values) {
      notifier.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.api.geo.geoList(
        space: widget.space,
        pageIndex: 1,
        pageSize: 1000,
      );
      if (!res.code) {
        throw Exception(res.msg.isEmpty ? '加载失败' : res.msg);
      }
      setState(() {
        _places = res.data.photoGeo;
        _loading = false;
      });
      _preloadCovers();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载失败: $e';
          _loading = false;
        });
      }
    }
  }

  void _preloadCovers() {
    for (final place in _places.take(30)) {
      final cover = _coverPathFor(place);
      if (cover.isNotEmpty) {
        _ensureCoverLoaded(cover);
      }
    }
  }

  ValueNotifier<Uint8List?> _thumbNotifierFor(String path) {
    return _thumbNotifiers.putIfAbsent(
      path,
      () => ValueNotifier<Uint8List?>(null),
    );
  }

  String _coverPathFor(GeoItem place) {
    if (place.exhibition.isEmpty) return '';
    final first = place.exhibition.first;
    return first.thumbnailPath.isNotEmpty ? first.thumbnailPath : first.path;
  }

  Future<void> _ensureCoverLoaded(String thumbnailPath) async {
    if (thumbnailPath.isEmpty) return;
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
        debugPrint('地点封面加载失败: $thumbnailPath, $e');
      }
    }
  }

  void _onTapPlace(GeoItem place) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            PlacePhotosPage(api: widget.api, space: widget.space, place: place),
      ),
    );
  }

  String _placeName(GeoItem place) {
    if (place.name.isNotEmpty) return place.name;
    final parts = <String>[];
    if (place.country.isNotEmpty) parts.add(place.country);
    if (place.firstLevel.isNotEmpty) parts.add(place.firstLevel);
    if (place.secondLevel.isNotEmpty) parts.add(place.secondLevel);
    return parts.isEmpty ? '未知地点' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    final content = () {
      if (_loading) {
        return const Center(child: CircularProgressIndicator());
      }

      if (_error != null) {
        return _buildStatus(
          icon: Icons.error_outline,
          iconColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
          message: _error!,
          onRetry: _load,
        );
      }

      if (_places.isEmpty) {
        return _buildStatus(
          icon: Icons.place_outlined,
          iconColor: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.3),
          message: '暂无地点数据',
        );
      }

      return RefreshIndicator(
        onRefresh: _load,
        child: AdaptiveScrollbar(
          controller: _scrollController,
          child: GridView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.66,
            ),
            itemCount: _places.length,
            itemBuilder: (context, index) {
              final place = _places[index];
              final path = _coverPathFor(place);
              final notifiers = <ValueNotifier<Uint8List?>>[];
              if (path.isNotEmpty) {
                _ensureCoverLoaded(path);
                notifiers.add(_thumbNotifierFor(path));
              }

              return CollectionTile(
                title: _placeName(place),
                subtitle: '${place.count} 张照片',
                thumbnailNotifiers: notifiers,
                defaultIcon: Icons.place,
                shape: CollectionShape.square,
                onTap: () => _onTapPlace(place),
              );
            },
          ),
        ),
      );
    }();

    return SafeArea(child: content);
  }

  Widget _buildStatus({
    required IconData icon,
    required Color iconColor,
    required String message,
    VoidCallback? onRetry,
  }) {
    return RefreshIndicator(
      onRefresh: _load,
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
