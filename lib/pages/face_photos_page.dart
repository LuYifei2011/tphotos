import 'package:flutter/material.dart';
import '../api/tos_api.dart';
import '../models/face_models.dart';
import '../models/photo_list_models.dart';
import '../models/timeline_models.dart';
import '../widgets/timeline_view.dart';

class FacePhotosPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              face.name.isEmpty ? '未命名' : face.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              '${face.count} 张照片',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
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
        keyPrefix: 'face-photo',
        emptyLabel: '暂无照片',
        emptyDateLabel: '该日期无照片',
      ),
    );
  }

  Future<List<TimelineItem>> _loadTimeline() async {
    final res = await api.face.faceTimeline(
      space: space,
      faceId: face.indexId,
      timelineType: 2,
      order: 'desc',
    );
    return res.data;
  }

  Future<PhotoListData> _loadPhotosForDate(TimelineItem item) {
    return api.face.faceListAll(
      space: space,
      faceId: face.indexId,
      startTime: item.timestamp,
      endTime: item.timestamp,
      timelineType: 2,
      order: 'desc',
    );
  }
}
