import 'photo_list_models.dart';
import 'timeline_models.dart';

/// 场景展示项（封面照片）
class SceneExhibition {
  final String path;
  final String thumbnailPath;

  SceneExhibition({required this.path, required this.thumbnailPath});

  factory SceneExhibition.fromJson(Map<String, dynamic> json) {
    return SceneExhibition(
      path: json['path'] as String? ?? '',
      thumbnailPath: json['thumbnail_path'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'thumbnail_path': thumbnailPath,
    };
  }
}

/// 场景索引项
class SceneItem {
  final String label;
  final int count;
  final List<SceneExhibition> exhibition;

  SceneItem({required this.label, required this.count, required this.exhibition});

  factory SceneItem.fromJson(Map<String, dynamic> json) {
    return SceneItem(
      label: json['label'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      exhibition: (json['exhibition'] as List<dynamic>? ?? [])
          .map((item) => SceneExhibition.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'count': count,
      'exhibition': exhibition.map((e) => e.toJson()).toList(),
    };
  }
}

/// 场景索引列表数据
class SceneIndexData {
  final int total;
  final List<SceneItem> scene;

  SceneIndexData({required this.total, required this.scene});

  factory SceneIndexData.fromJson(Map<String, dynamic> json) {
    return SceneIndexData(
      total: json['total'] as int? ?? 0,
      scene: (json['scene'] as List<dynamic>? ?? [])
          .map((item) => SceneItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'scene': scene.map((e) => e.toJson()).toList(),
    };
  }
}

/// 场景索引列表响应
class SceneIndexResponse {
  final bool isLogin;
  final bool code;
  final String msg;
  final SceneIndexData data;
  final double time;
  final int codeNum;
  final String codeMsg;

  SceneIndexResponse({
    required this.isLogin,
    required this.code,
    required this.msg,
    required this.data,
    required this.time,
    required this.codeNum,
    required this.codeMsg,
  });

  factory SceneIndexResponse.fromJson(Map<String, dynamic> json) {
    return SceneIndexResponse(
      isLogin: json['is_login'] as bool? ?? false,
      code: json['code'] as bool? ?? false,
      msg: json['msg'] as String? ?? '',
      data: SceneIndexData.fromJson(json['data'] as Map<String, dynamic>? ?? {}),
      time: (json['time'] as num?)?.toDouble() ?? 0.0,
      codeNum: json['code_num'] as int? ?? 0,
      codeMsg: json['code_msg'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'is_login': isLogin,
      'code': code,
      'msg': msg,
      'data': data.toJson(),
      'time': time,
      'code_num': codeNum,
      'code_msg': codeMsg,
    };
  }
}

/// 场景时间线响应（复用 TimelineResponse）
typedef SceneTimelineResponse = TimelineResponse;

/// 场景照片列表响应（复用 PhotoListResponse）
typedef ScenePhotoListResponse = PhotoListResponse;
