import 'tos_client.dart';
import '../models/geo_models.dart';
import '../models/photo_list_models.dart';
import '../models/timeline_models.dart';

class GeoAPI {
  final TosClient _client;

  GeoAPI(this._client);

  Future<GeoIndexResponse> geoList({
    required int space,
    String lang = 'zh-cn',
    int pageIndex = 1,
    int pageSize = 50,
  }) async {
    final params = <String, String>{
      'lang': lang,
      'space': space.toString(),
      'page_index': pageIndex.toString(),
      'page_size': pageSize.toString(),
    };
    final response = await _client.get(
      '/v2/proxy/TerraPhotos/GeoClassfy',
      params: params,
    );
    return GeoIndexResponse.fromJson(response);
  }

  Future<GeoTimelineResponse> geoTimeline({
    required int space,
    required String countryCode,
    required String firstLevelCode,
    required String secondLevelCode,
    int timelineType = 2,
    String order = 'desc',
  }) async {
    final body = <String, dynamic>{
      'space': space,
      'country_code': countryCode,
      'first_level_code': firstLevelCode,
      'second_level_code': secondLevelCode,
      'timeline_type': timelineType,
      'order': order,
    };
    final response = await _client.post(
      '/v2/proxy/TerraPhotos/GeoTimeline',
      json: body,
    );
    return TimelineResponse.fromJson(response);
  }

  Future<GeoPhotoListResponse> geoPhotoList({
    required int space,
    required String countryCode,
    required String firstLevelCode,
    required String secondLevelCode,
    required int startTime,
    required int endTime,
    int pageIndex = 1,
    int pageSize = 150,
    int timelineType = 2,
    String order = 'desc',
  }) async {
    final body = <String, dynamic>{
      'space': space,
      'country_code': countryCode,
      'first_level_code': firstLevelCode,
      'second_level_code': secondLevelCode,
      'start_time': startTime,
      'end_time': endTime,
      'page_index': pageIndex,
      'page_size': pageSize,
      'timeline_type': timelineType,
      'order': order,
    };
    final response = await _client.post(
      '/v2/proxy/TerraPhotos/GeoPhoto',
      json: body,
    );
    return PhotoListResponse.fromJson(response);
  }

  Future<PhotoListData> geoPhotoListAll({
    required int space,
    required String countryCode,
    required String firstLevelCode,
    required String secondLevelCode,
    required int startTime,
    required int endTime,
    int timelineType = 2,
    String order = 'desc',
  }) async {
    const pageSize = 150;
    var pageIndex = 1;
    final allPhotos = <PhotoItem>[];
    int total = 0;

    while (true) {
      final res = await geoPhotoList(
        space: space,
        countryCode: countryCode,
        firstLevelCode: firstLevelCode,
        secondLevelCode: secondLevelCode,
        startTime: startTime,
        endTime: endTime,
        pageIndex: pageIndex,
        pageSize: pageSize,
        timelineType: timelineType,
        order: order,
      );

      total = res.data.total;
      allPhotos.addAll(res.data.photoList);

      if (allPhotos.length >= total || res.data.photoList.length < pageSize) {
        break;
      }

      pageIndex++;
    }

    return PhotoListData(total: total, photoList: allPhotos);
  }
}
