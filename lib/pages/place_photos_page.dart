import 'package:flutter/material.dart';
import '../api/tos_api.dart';
import '../models/geo_models.dart';
import '../models/photo_list_models.dart';
import '../models/timeline_models.dart';
import '../widgets/timeline_view.dart';

class PlacePhotosPage extends StatelessWidget {
  final TosAPI api;
  final int space;
  final GeoItem place;

  const PlacePhotosPage({
    super.key,
    required this.api,
    required this.space,
    required this.place,
  });

  String _title() {
    if (place.name.isNotEmpty) return place.name;
    final parts = <String>[];
    if (place.country.isNotEmpty) parts.add(place.country);
    if (place.firstLevel.isNotEmpty) parts.add(place.firstLevel);
    if (place.secondLevel.isNotEmpty) parts.add(place.secondLevel);
    return parts.isEmpty ? '地点' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final title = _title();

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
              '${place.count} 张照片',
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
        keyPrefix: 'place-photo',
        emptyLabel: '暂无照片',
        emptyDateLabel: '该日期无照片',
      ),
    );
  }

  Future<List<TimelineItem>> _loadTimeline() async {
    final res = await api.geo.geoTimeline(
      space: space,
      countryCode: place.countryCode,
      firstLevelCode: place.firstLevelCode,
      secondLevelCode: place.secondLevelCode,
      timelineType: 2,
      order: 'desc',
    );
    if (!res.code) {
      throw Exception(res.msg.isEmpty ? '加载失败' : res.msg);
    }
    return res.data;
  }

  Future<PhotoListData> _loadPhotosForDate(TimelineItem item) {
    return api.geo.geoPhotoListAll(
      space: space,
      countryCode: place.countryCode,
      firstLevelCode: place.firstLevelCode,
      secondLevelCode: place.secondLevelCode,
      startTime: item.timestamp,
      endTime: item.timestamp,
      timelineType: 2,
      order: 'desc',
    );
  }
}
