import 'package:flutter/material.dart';
import '../api/tos_api.dart';
import '../models/photo_list_models.dart';
import '../models/scene_models.dart';
import '../models/timeline_models.dart';
import '../widgets/timeline_view.dart';
import '../utils/scene_label_resolver.dart';

class ScenePhotosPage extends StatelessWidget {
  final TosAPI api;
  final int space;
  final SceneItem scene;

  const ScenePhotosPage({
    super.key,
    required this.api,
    required this.space,
    required this.scene,
  });

  @override
  Widget build(BuildContext context) {
    final resolver = SceneLabelResolver.instance;

    return ValueListenableBuilder<int>(
      valueListenable: resolver.versionListenable,
      builder: (context, _, __) {
        final title = resolver.translate(scene.label);

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${scene.count} 张照片',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          body: TimelineView(
            loadTimeline: _loadTimeline,
            loadPhotosForDate: _loadPhotosForDate,
            loadThumbnail: (path) => api.photos.thumbnailBytes(path),
            api: api,
            keyPrefix: 'scene-photo',
            emptyLabel: '暂无照片',
            emptyDateLabel: '该日期无照片',
          ),
        );
      },
    );
  }

  Future<List<TimelineItem>> _loadTimeline() async {
    final res = await api.scene.sceneTimeline(
      space: space,
      label: scene.label,
      timelineType: 2,
      order: 'desc',
    );
    if (!res.code) {
      throw Exception(res.msg.isEmpty ? '加载失败' : res.msg);
    }
    return res.data;
  }

  Future<PhotoListData> _loadPhotosForDate(TimelineItem item) {
    return api.scene.scenePhotoListAll(
      space: space,
      label: scene.label,
      startTime: item.timestamp,
      endTime: item.timestamp,
      timelineType: 2,
      order: 'desc',
    );
  }
}
