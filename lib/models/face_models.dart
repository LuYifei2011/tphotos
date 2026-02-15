import 'photo_list_models.dart';
import 'timeline_models.dart';

/// 人脸展示项（封面照片）
class FaceExhibition {
  final String path;
  final String thumbnailPath;

  FaceExhibition({required this.path, required this.thumbnailPath});

  factory FaceExhibition.fromJson(Map<String, dynamic> json) {
    return FaceExhibition(
      path: json['path'] as String,
      thumbnailPath: json['thumbnail_path'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'path': path, 'thumbnail_path': thumbnailPath};
  }
}

/// 人脸索引项
class FaceIndexItem {
  final int id;
  final String indexId;
  final String name;
  final int collectionType;
  final String cover;
  final int count;
  final List<FaceExhibition> exhibition;

  FaceIndexItem({
    required this.id,
    required this.indexId,
    required this.name,
    required this.collectionType,
    required this.cover,
    required this.count,
    required this.exhibition,
  });

  factory FaceIndexItem.fromJson(Map<String, dynamic> json) {
    return FaceIndexItem(
      id: json['id'] as int,
      indexId: json['index_id'] as String,
      name: json['name'] as String,
      collectionType: json['collection_type'] as int,
      cover: json['cover'] as String,
      count: json['count'] as int,
      exhibition: (json['exhibition'] as List<dynamic>)
          .map((item) => FaceExhibition.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'index_id': indexId,
      'name': name,
      'collection_type': collectionType,
      'cover': cover,
      'count': count,
      'exhibition': exhibition.map((e) => e.toJson()).toList(),
    };
  }
}

/// 人脸索引列表数据
class FaceIndexData {
  final int total;
  final List<FaceIndexItem> faceIndexList;

  FaceIndexData({required this.total, required this.faceIndexList});

  factory FaceIndexData.fromJson(Map<String, dynamic> json) {
    return FaceIndexData(
      total: json['total'] as int,
      faceIndexList: (json['face_index_list'] as List<dynamic>)
          .map((item) => FaceIndexItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'face_index_list': faceIndexList.map((e) => e.toJson()).toList(),
    };
  }
}

/// 人脸索引列表响应
class FaceIndexResponse {
  final bool isLogin;
  final bool code;
  final String msg;
  final FaceIndexData data;

  FaceIndexResponse({
    required this.isLogin,
    required this.code,
    required this.msg,
    required this.data,
  });

  factory FaceIndexResponse.fromJson(Map<String, dynamic> json) {
    return FaceIndexResponse(
      isLogin: json['is_login'] as bool,
      code: json['code'] as bool,
      msg: json['msg'] as String,
      data: FaceIndexData.fromJson(json['data'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'is_login': isLogin,
      'code': code,
      'msg': msg,
      'data': data.toJson(),
    };
  }
}

/// 人脸时间线响应（复用 TimelineResponse）
typedef FaceTimelineResponse = TimelineResponse;

/// 人脸照片列表响应（复用 PhotoListResponse）
typedef FacePhotoListResponse = PhotoListResponse;
