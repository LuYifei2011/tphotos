import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import '../api/tos_api.dart';
import '../models/face_models.dart';
import '../widgets/adaptive_scrollbar.dart';
import '../widgets/collection_tile.dart';
import '../widgets/thumbnail_manager.dart';
import 'face_photos_page.dart';

class FacePage extends StatefulWidget {
  final TosAPI api;
  final int space;

  const FacePage({super.key, required this.api, required this.space});

  @override
  State<FacePage> createState() => _FacePageState();
}

class _FacePageState extends State<FacePage> {
  List<FaceIndexItem> _faces = [];
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
  void didUpdateWidget(FacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.space != widget.space) {
      _load();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final n in _thumbNotifiers.values) {
      n.dispose();
    }
    super.dispose();
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

  ValueNotifier<Uint8List?> _thumbNotifierFor(String path) {
    return _thumbNotifiers.putIfAbsent(
      path,
      () => ValueNotifier<Uint8List?>(null),
    );
  }

  void _preloadCovers() {
    for (final face in _faces.take(30)) {
      if (face.exhibition.isNotEmpty) {
        _ensureCoverLoaded(_coverPathFor(face));
      }
    }
  }

  String _coverPathFor(FaceIndexItem face) {
    if (face.exhibition.isEmpty) {
      return '';
    }
    final first = face.exhibition.first;
    return first.thumbnailPath.isNotEmpty ? first.thumbnailPath : first.path;
  }

  Future<void> _ensureCoverLoaded(String thumbnailPath) async {
    if (thumbnailPath.isEmpty) return;
    final notifier = _thumbNotifierFor(thumbnailPath);
    if (notifier.value != null) return;

    try {
      final bytes = await ThumbnailManager.instance.load(
        thumbnailPath,
        () => widget.api.face.faceThumbnailBytes(thumbnailPath),
      );
      notifier.value = bytes;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('人物封面加载失败: $thumbnailPath, $e');
      }
    }
  }

  void _onTapFace(FaceIndexItem face) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            FacePhotosPage(api: widget.api, space: widget.space, face: face),
      ),
    );
  }

  Future<void> _onLongPressFace(FaceIndexItem face) async {
    final newName = await _showRenameDialog(face);
    if (newName == null) return;

    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == face.name) return;

    await _updateFaceName(face, trimmed);
  }

  Future<void> _updateFaceName(FaceIndexItem face, String newName) async {
    final navigator = Navigator.of(context, rootNavigator: true);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await widget.api.face.editIndexName(
        id: face.id,
        space: widget.space,
        indexName: newName,
      );

      if (!mounted) return;
      setState(() {
        _faces = _faces
            .map(
              (item) => item.id == face.id
                  ? FaceIndexItem(
                      id: item.id,
                      indexId: item.indexId,
                      name: newName,
                      collectionType: item.collectionType,
                      cover: item.cover,
                      count: item.count,
                      exhibition: item.exhibition,
                    )
                  : item,
            )
            .toList();
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('名称已更新')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('修改失败: $e')));
      }
    } finally {
      if (navigator.mounted) {
        navigator.pop();
      }
    }
  }

  Future<String?> _showRenameDialog(FaceIndexItem face) {
    final controller = TextEditingController(text: face.name);

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('修改人物名称'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: '名称'),
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
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
        onRetry: _load,
      );
    }

    if (_faces.isEmpty) {
      return _buildStatus(
        icon: Icons.person_outline,
        iconColor: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.3),
        message: '暂无人物数据',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: AdaptiveScrollbar(
        controller: _scrollController,
        child: GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.66,
          ),
          itemCount: _faces.length,
          itemBuilder: (context, index) {
            final face = _faces[index];
            final notifiers = face.exhibition.isEmpty
                ? <ValueNotifier<Uint8List?>>[]
                : [
                    (() {
                      final path = _coverPathFor(face);
                      _ensureCoverLoaded(path);
                      return _thumbNotifierFor(path);
                    })(),
                  ];

            return CollectionTile(
              title: face.name.isEmpty ? '未命名' : face.name,
              subtitle: '${face.count} 张照片',
              thumbnailNotifiers: notifiers,
              defaultIcon: Icons.person,
              shape: CollectionShape.circle,
              onTap: () => _onTapFace(face),
              onLongPress: () => _onLongPressFace(face),
              onSecondaryTap: () => _onLongPressFace(face),
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
