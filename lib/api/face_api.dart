import 'tos_client.dart';
import '../models/face_models.dart';
import '../models/timeline_models.dart';
import '../models/photo_list_models.dart';

class FaceAPI {
  final TosClient _client;

  FaceAPI(this._client);

  /// 修改人物索引（目前用于改名）
  Future<void> editIndexName({
    required int id,
    required int space,
    required String indexName,
    int type = 1,
  }) async {
    final body = <String, dynamic>{
      'id': id,
      'type': type,
      'index_name': indexName,
      'space': space,
    };

    final response = await _client.post(
      '/v2/proxy/TerraPhotos/EditIndex',
      json: body,
    );

    if (response['code'] != true) {
      throw APIError(
        0,
        response['msg']?.toString() ?? '编辑失败',
        response['data'],
      );
    }
  }

  /// 获取人物索引列表
  /// [space] 空间 ID（1: 个人空间, 2: 公共空间）
  /// [pageIndex] 页码（从 1 开始）
  /// [pageSize] 每页数量
  Future<FaceIndexResponse> faceIndex({
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
      '/v2/proxy/TerraPhotos/FaceIndex',
      params: params,
    );
    return FaceIndexResponse.fromJson(response);
  }

  /// 获取人物头像字节数据
  Future<List<int>> faceThumbnailBytes(String rawPath) async {
    final encodedPath = Uri.encodeComponent(rawPath);
    final csrfToken = Uri.encodeQueryComponent(_client.csrfToken ?? '');
    final path =
        '/v2/proxy/TerraPhotos/multimediaPlay?path=$encodedPath&X-Csrf-Token=$csrfToken';
    final bytes = await _client.getBytes(path);
    return bytes;
  }

  /// 获取某个人物的时间线
  /// [space] 空间 ID
  /// [faceId] 人物 ID
  /// [timelineType] 时间线类型（1: 年, 2: 日）
  /// [order] 排序（desc: 降序, asc: 升序）
  Future<FaceTimelineResponse> faceTimeline({
    required int space,
    required String faceId,
    int timelineType = 2,
    String order = 'desc',
  }) async {
    final params = <String, String>{
      'space': space.toString(),
      'face_id': faceId,
      'timeline_type': timelineType.toString(),
      'order': order,
    };
    final response = await _client.get(
      '/v2/proxy/TerraPhotos/FaceTimeline',
      params: params,
    );
    return TimelineResponse.fromJson(response);
  }

  /// 获取某个人物在特定时间的照片列表
  /// [space] 空间 ID
  /// [faceId] 人物 ID
  /// [startTime] 开始时间戳
  /// [endTime] 结束时间戳
  /// [pageIndex] 页码（从 1 开始）
  /// [pageSize] 每页数量
  /// [timelineType] 时间线类型（1: 年, 2: 日）
  /// [order] 排序（desc: 降序, asc: 升序）
  Future<FacePhotoListResponse> faceList({
    required int space,
    required String faceId,
    required int startTime,
    required int endTime,
    int pageIndex = 1,
    int pageSize = 150,
    int timelineType = 2,
    String order = 'desc',
  }) async {
    final body = <String, dynamic>{
      'space': space,
      'face_id': faceId,
      'start_time': startTime,
      'end_time': endTime,
      'page_index': pageIndex,
      'page_size': pageSize,
      'timeline_type': timelineType,
      'order': order,
    };
    final response = await _client.post(
      '/v2/proxy/TerraPhotos/FaceList',
      json: body,
    );
    return PhotoListResponse.fromJson(response);
  }

  /// 加载某个人物在特定时间的所有照片（自动分页）
  Future<PhotoListData> faceListAll({
    required int space,
    required String faceId,
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
      final response = await faceList(
        space: space,
        faceId: faceId,
        startTime: startTime,
        endTime: endTime,
        pageIndex: pageIndex,
        pageSize: pageSize,
        timelineType: timelineType,
        order: order,
      );

      total = response.data.total;
      allPhotos.addAll(response.data.photoList);

      // 如果已加载所有数据，退出循环
      if (allPhotos.length >= total) {
        break;
      }

      pageIndex++;
    }

    return PhotoListData(total: total, photoList: allPhotos);
  }
}
