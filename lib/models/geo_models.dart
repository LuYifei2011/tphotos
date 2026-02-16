import 'photo_list_models.dart';
import 'timeline_models.dart';

class GeoExhibition {
  final String path;
  final String thumbnailPath;

  GeoExhibition({required this.path, required this.thumbnailPath});

  factory GeoExhibition.fromJson(Map<String, dynamic> json) {
    return GeoExhibition(
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

class GeoItem {
  final String country;
  final String countryCode;
  final String firstLevel;
  final String firstLevelCode;
  final String secondLevel;
  final String secondLevelCode;
  final String name;
  final int count;
  final List<GeoExhibition> exhibition;

  GeoItem({
    required this.country,
    required this.countryCode,
    required this.firstLevel,
    required this.firstLevelCode,
    required this.secondLevel,
    required this.secondLevelCode,
    required this.name,
    required this.count,
    required this.exhibition,
  });

  factory GeoItem.fromJson(Map<String, dynamic> json) {
    return GeoItem(
      country: json['country'] as String? ?? '',
      countryCode: json['country_code'] as String? ?? '',
      firstLevel: json['first_level'] as String? ?? '',
      firstLevelCode: json['first_level_code'] as String? ?? '',
      secondLevel: json['second_level'] as String? ?? '',
      secondLevelCode: json['second_level_code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      exhibition: (json['exhibition'] as List<dynamic>? ?? [])
          .map((item) => GeoExhibition.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'country': country,
      'country_code': countryCode,
      'first_level': firstLevel,
      'first_level_code': firstLevelCode,
      'second_level': secondLevel,
      'second_level_code': secondLevelCode,
      'name': name,
      'count': count,
      'exhibition': exhibition.map((e) => e.toJson()).toList(),
    };
  }
}

class GeoIndexData {
  final int total;
  final List<GeoItem> photoGeo;

  GeoIndexData({required this.total, required this.photoGeo});

  factory GeoIndexData.fromJson(Map<String, dynamic> json) {
    return GeoIndexData(
      total: json['total'] as int? ?? 0,
      photoGeo: (json['photo_geo'] as List<dynamic>? ?? [])
          .map((item) => GeoItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'photo_geo': photoGeo.map((e) => e.toJson()).toList(),
    };
  }
}

class GeoIndexResponse {
  final bool isLogin;
  final bool code;
  final String msg;
  final GeoIndexData data;
  final double time;
  final int codeNum;
  final String codeMsg;

  GeoIndexResponse({
    required this.isLogin,
    required this.code,
    required this.msg,
    required this.data,
    required this.time,
    required this.codeNum,
    required this.codeMsg,
  });

  factory GeoIndexResponse.fromJson(Map<String, dynamic> json) {
    return GeoIndexResponse(
      isLogin: json['is_login'] as bool? ?? false,
      code: json['code'] as bool? ?? false,
      msg: json['msg'] as String? ?? '',
      data: GeoIndexData.fromJson(json['data'] as Map<String, dynamic>? ?? {}),
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

typedef GeoTimelineResponse = TimelineResponse;
typedef GeoPhotoListResponse = PhotoListResponse;
