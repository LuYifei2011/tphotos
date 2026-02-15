import 'package:flutter/material.dart';

import '../api/tos_api.dart';
import '../models/album_models.dart';
import '../models/photo_list_models.dart';
import '../models/timeline_models.dart';
import '../widgets/timeline_view.dart';

/// 相册详情页（独立路由页面）
///
/// 展示单个相册内的照片时间线，使用 [TimelineView] 统一组件。
class AlbumDetailPage extends StatelessWidget {
  final TosAPI api;
  final AlbumInfo album;

  const AlbumDetailPage({
    super.key,
    required this.api,
    required this.album,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              album.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              '${album.count} 张照片',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
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
        keyPrefix: 'album-${album.id}',
        emptyLabel: '该相册暂无照片',
        emptyDateLabel: '该日期无照片',
      ),
    );
  }

  Future<List<TimelineItem>> _loadTimeline() async {
    final response = await api.photos.albumTimeline(
      id: album.id,
      timelineType: 2,
      order: 'desc',
    );
    if (!response.code) {
      throw Exception(response.msg.isEmpty ? '加载失败' : response.msg);
    }
    return response.data;
  }

  Future<PhotoListData> _loadPhotosForDate(TimelineItem item) async {
    final response = await api.photos.photosInAlbum(
      name: album.name,
      startTime: item.timestamp,
      endTime: item.timestamp,
      pageIndex: 1,
      pageSize: 150,
      timelineType: 2,
      order: 'desc',
    );
    if (!response.code) {
      throw Exception('API Error: ${response.msg}');
    }
    return response.data;
  }
}
