import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../api/tos_api.dart';
import '../models/face_models.dart';
import 'face_photos_page.dart';

class FacePage extends StatefulWidget {
  final TosAPI api;
  final int space;

  const FacePage({
    super.key,
    required this.api,
    required this.space,
  });

  @override
  State<FacePage> createState() => _FacePageState();
}

class _FacePageState extends State<FacePage> {
  List<FaceIndexItem> _faces = [];
  bool _loading = true;
  String? _error;
  final Map<String, Image?> _thumbCache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.space != widget.space) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.api.face.faceIndex(
        space: widget.space,
        pageIndex: 1,
        pageSize: 1000,
      );
      setState(() {
        _faces = res.data.faceIndexList;
      });
    } catch (e) {
      setState(() => _error = '加载失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Image?> _loadThumb(String thumbPath) async {
    if (_thumbCache.containsKey(thumbPath)) {
      return _thumbCache[thumbPath];
    }
    try {
      final bytes = await widget.api.face.faceThumbnailBytes(thumbPath);
      final img = Image.memory(
        Uint8List.fromList(bytes),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
      _thumbCache[thumbPath] = img;
      if (mounted) setState(() {});
      return img;
    } catch (e) {
      debugPrint('加载缩略图失败: $e');
      _thumbCache[thumbPath] = null;
      return null;
    }
  }

  void _onTapFace(FaceIndexItem face) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FacePhotosPage(
          api: widget.api,
          space: widget.space,
          face: face,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
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
      );
    }

    if (_faces.isEmpty) {
      return const Center(child: Text('暂无人脸数据'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      itemCount: _faces.length,
      itemBuilder: (context, index) {
        final face = _faces[index];
        return _FaceCard(
          face: face,
          onTap: () => _onTapFace(face),
          loadThumb: _loadThumb,
        );
      },
    );
  }
}

class _FaceCard extends StatefulWidget {
  final FaceIndexItem face;
  final VoidCallback onTap;
  final Future<Image?> Function(String) loadThumb;

  const _FaceCard({
    required this.face,
    required this.onTap,
    required this.loadThumb,
  });

  @override
  State<_FaceCard> createState() => _FaceCardState();
}

class _FaceCardState extends State<_FaceCard> {
  Image? _thumbImage;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    if (widget.face.exhibition.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final thumbPath = widget.face.exhibition.first.thumbnailPath;
    final img = await widget.loadThumb(thumbPath);
    if (mounted) {
      setState(() {
        _thumbImage = img;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 缩略图
            Expanded(
              child: Container(
                color: Colors.grey[200],
                child: _loading
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _thumbImage != null
                        ? _thumbImage!
                        : const Icon(Icons.person, size: 48),
              ),
            ),
            // 名称和数量
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.face.name.isEmpty ? '未命名' : widget.face.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.face.count} 张照片',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
