import 'tos_client.dart';
import '../models/scene_models.dart';
import '../models/timeline_models.dart';
import '../models/photo_list_models.dart';

class SceneAPI {
  final TosClient _client;

  SceneAPI(this._client);

  /// 获取场景索引列表
  Future<SceneIndexResponse> sceneList({
    required int space,
    int pageIndex = 1,
    int pageSize = 50,
  }) async {
    final params = <String, String>{
      'space': space.toString(),
      'page_index': pageIndex.toString(),
      'page_size': pageSize.toString(),
    };
    final response = await _client.get(
      '/v2/proxy/TerraPhotos/SceneInferList',
      params: params,
    );
    return SceneIndexResponse.fromJson(response);
  }

  /// 获取指定场景的时间线
  Future<SceneTimelineResponse> sceneTimeline({
    required int space,
    required String label,
    int timelineType = 2,
    String order = 'desc',
  }) async {
    final params = <String, String>{
      'space': space.toString(),
      'label': label,
      'timeline_type': timelineType.toString(),
      'order': order,
    };
    final response = await _client.get(
      '/v2/proxy/TerraPhotos/SceneInferTimeline',
      params: params,
    );
    return TimelineResponse.fromJson(response);
  }

  /// 获取指定场景在某日的照片列表
  Future<ScenePhotoListResponse> scenePhotoList({
    required int space,
    required String label,
    required int startTime,
    required int endTime,
    int pageIndex = 1,
    int pageSize = 150,
    int timelineType = 2,
    String order = 'desc',
  }) async {
    final body = <String, dynamic>{
      'space': space,
      'start_time': startTime,
      'end_time': endTime,
      'page_index': pageIndex,
      'page_size': pageSize,
      'label': label,
      'timeline_type': timelineType,
      'order': order,
    };
    final response = await _client.post(
      '/v2/proxy/TerraPhotos/SceneInferPhoto',
      json: body,
    );
    return PhotoListResponse.fromJson(response);
  }

  /// 自动分页加载指定场景在某日的所有照片
  Future<PhotoListData> scenePhotoListAll({
    required int space,
    required String label,
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
      final res = await scenePhotoList(
        space: space,
        label: label,
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
