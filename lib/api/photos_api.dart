import 'tos_client.dart';
import '../models/timeline_models.dart';
import '../models/photo_list_models.dart';

class PhotosAPI {
  final TosClient _client;

  PhotosAPI(this._client);

  /// Fetch thumbnail bytes using client to include cookies to avoid 403.
  Future<List<int>> thumbnailBytes(String rawPath) async {
    final encodedPath = Uri.encodeComponent(rawPath);
    final path = '/v2/proxy/TerraPhotos/Thumbnail/$encodedPath';
    final bytes = await _client.getBytes(path);
    return bytes;
  }

  /// Fetch original photo bytes using client to include cookies to avoid 403.
  Future<List<int>> originalPhotoBytes(String rawPath) async {
    final encodedPath = Uri.encodeComponent(rawPath);
    final path = '/v2/proxy/TerraPhotos/multimediaPlay?path=$encodedPath';
    final bytes = await _client.getBytes(path);
    return bytes;
  }

  Future<TimelineResponse> timeline({
    int? space,
    int? fileType,
    int? timelineType,
    String? order,
  }) async {
    final params = <String, String>{};
    if (space != null) params['space'] = space.toString();
    if (fileType != null) params['file_type'] = fileType.toString();
    if (timelineType != null) params['timeline_type'] = timelineType.toString();
    if (order != null) params['order'] = order;
    final response = await _client.get(
      '/v2/proxy/TerraPhotos/Timeline',
      params: params,
    );
    return TimelineResponse.fromJson(response);
  }

  Future<PhotoListResponse> photoList({
    required int space,
    required int listType,
    required int fileType,
    required int startTime,
    required int endTime,
    required int pageSize,
    required int pageIndex,
    required int timelineType,
    required String order,
  }) async {
    final body = <String, dynamic>{
      'space': space,
      'list_type': listType,
      'file_type': fileType,
      'start_time': startTime,
      'end_time': endTime,
      'page_size': pageSize,
      'page_index': pageIndex,
      'timeline_type': timelineType,
      'order': order,
    };
    final response = await _client.post(
      '/v2/proxy/TerraPhotos/PhotoList',
      json: body,
    );
    return PhotoListResponse.fromJson(response);
  }

  /// Load all pages of photo list by repeatedly calling photoList until all data is loaded
  Future<PhotoListData> photoListAll({
    required int space,
    required int listType,
    required int fileType,
    required int startTime,
    required int endTime,
    required int pageSize,
    required int timelineType,
    required String order,
  }) async {
    final allPhotos = <PhotoItem>[];
    var currentPage = 1;
    var totalLoaded = 0;
    var total = 0;

    do {
      final response = await photoList(
        space: space,
        listType: listType,
        fileType: fileType,
        startTime: startTime,
        endTime: endTime,
        pageSize: pageSize,
        pageIndex: currentPage,
        timelineType: timelineType,
        order: order,
      );

      if (!response.code) {
        throw Exception('API Error: ${response.msg}');
      }

      final data = response.data;
      total = data.total;
      allPhotos.addAll(data.photoList);
      totalLoaded += data.photoList.length;
      currentPage++;

      // 如果这一页的数据少于pageSize，说明已经是最后一页了
      if (data.photoList.length < pageSize) {
        break;
      }
    } while (totalLoaded < total);

    return PhotoListData(total: total, photoList: allPhotos);
  }
}
