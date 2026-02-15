import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../api/tos_api.dart';
import '../models/face_models.dart';
import '../models/timeline_models.dart';
import '../models/photo_list_models.dart';
import '../widgets/date_section_grid.dart';
import '../widgets/date_section_state.dart';
import '../widgets/thumbnail_manager.dart';
import 'photos_page.dart';

class FacePhotosPage extends StatefulWidget {
  final TosAPI api;
  final int space;
  final FaceIndexItem face;

  const FacePhotosPage({
    super.key,
    required this.api,
    required this.space,
    required this.face,
  });

  @override
  State<FacePhotosPage> createState() => _FacePhotosPageState();
}

class _FacePhotosPageState extends State<FacePhotosPage> {
  List<TimelineItem> _timeline = [];
  bool _loading = true;
  String? _error;

  final ScrollController _scrollController = ScrollController();
  final Map<int, DateSectionState<PhotoListData>> _sections = {};
  final Map<int, GlobalKey> _headerKeys = {};
  final Map<String, ValueNotifier<Uint8List?>> _thumbNotifiers = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
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
      final res = await widget.api.face.faceTimeline(
        space: widget.space,
        faceId: widget.face.indexId,
        timelineType: 2,
        order: 'desc',
      );
      setState(() {
        _timeline = res.data;
      });
    } catch (e) {
      setState(() => _error = '加载失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScroll() {
    // 可以在这里实现滚动时的逻辑，比如更新日期标签
  }

  void _startFetchForItem(TimelineItem item) {
    final key = item.timestamp;
    final state = _sections.putIfAbsent(key, () => DateSectionState(key));
    if (state.hasStarted) return;
    state.markStarted();
    _fetchPhotosForDate(item, state);
  }

  Future<void> _fetchPhotosForDate(
    TimelineItem item,
    DateSectionState<PhotoListData> state,
  ) async {
    if (!state.tryAddLoadingDate()) {
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
      debugPrint('加载照片失败: $e');
    } finally {
      state.removeLoadingDate();
      state.clearCurrentFuture();
    }
  }

  Future<PhotoListData> _getOrLoadDatePhotos(TimelineItem item) async {
    return widget.api.face.faceListAll(
      space: widget.space,
      faceId: widget.face.indexId,
      startTime: item.timestamp,
      endTime: item.timestamp,
      timelineType: 2,
      order: 'desc',
    );
  }

  GlobalKey _headerKeyFor(int timestamp) {
    return _headerKeys.putIfAbsent(timestamp, () => GlobalKey());
  }

  List<Widget> _buildDateSlivers(TimelineItem item) {
    final key = item.timestamp;
    final state = _sections[key];
    final headerKey = _headerKeyFor(key);

    return DateSectionGrid(
      item: item,
      state: state ?? DateSectionState<PhotoListData>(key),
      headerKey: headerKey,
      onHeaderVisible: _startFetchForItem,
      onItemTap: (photo, allPhotos) {
        // 找到照片在所有照片中的索引
        final index = allPhotos.indexOf(photo);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => PhotoViewer(
              api: widget.api,
              photos: allPhotos,
              initialIndex: index >= 0 ? index : 0,
            ),
          ),
        );
      },
      ensureThumbLoaded: (photo) => _ensureThumbLoaded(photo),
      thumbNotifiers: _thumbNotifiers,
      keyPrefix: 'face_photo',
    ).build(context);
  }

  Future<void> _ensureThumbLoaded(PhotoItem photo) async {
    final path = photo.thumbnailPath;
    if (_thumbNotifiers.containsKey(path)) {
      return;
    }
    final notifier = ValueNotifier<Uint8List?>(null);
    _thumbNotifiers[path] = notifier;

    try {
      final bytes = await ThumbnailManager.instance.load(
        path,
        () => widget.api.photos.thumbnailBytes(path),
      );
      if (mounted) {
        notifier.value = bytes;
      }
    } catch (e) {
      debugPrint('加载缩略图失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.face.name.isEmpty ? '未命名' : widget.face.name),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _load,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _timeline.isEmpty
                  ? const Center(child: Text('暂无照片'))
                  : RefreshIndicator(
                      onRefresh: () async {
                        _sections.clear();
                        _headerKeys.clear();
                        await _load();
                      },
                      child: CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          for (var item in _timeline)
                            ..._buildDateSlivers(item),
                        ],
                      ),
                    ),
    );
  }
}
