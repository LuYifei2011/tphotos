/// 相册展示缩略图
class AlbumExhibition {
  final String path;
  final String thumbnailPath;

  AlbumExhibition({required this.path, required this.thumbnailPath});

  factory AlbumExhibition.fromJson(Map<String, dynamic> json) {
    return AlbumExhibition(
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

/// 相册信息
class AlbumInfo {
  final int id;
  final String name;
  final int count;
  final int creatTime;
  final String describe;
  final List<AlbumExhibition> exhibition;

  AlbumInfo({
    required this.id,
    required this.name,
    required this.count,
    required this.creatTime,
    required this.describe,
    required this.exhibition,
  });

  factory AlbumInfo.fromJson(Map<String, dynamic> json) {
    return AlbumInfo(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      creatTime: json['creat_time'] as int? ?? 0,
      describe: json['describe'] as String? ?? '',
      exhibition:
          (json['exhibition'] as List<dynamic>?)
              ?.map((e) => AlbumExhibition.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'count': count,
      'creat_time': creatTime,
      'describe': describe,
      'exhibition': exhibition.map((e) => e.toJson()).toList(),
    };
  }
}

/// 相册列表响应
class AlbumListResponse {
  final bool isLogin;
  final bool code;
  final String msg;
  final List<AlbumInfo> data;
  final double time;
  final int codeNum;
  final String codeMsg;

  AlbumListResponse({
    required this.isLogin,
    required this.code,
    required this.msg,
    required this.data,
    required this.time,
    required this.codeNum,
    required this.codeMsg,
  });

  factory AlbumListResponse.fromJson(Map<String, dynamic> json) {
    return AlbumListResponse(
      isLogin: json['is_login'] as bool? ?? false,
      code: json['code'] as bool? ?? false,
      msg: json['msg'] as String? ?? '',
      data:
          (json['data'] as List<dynamic>?)
              ?.map((item) => AlbumInfo.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
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
      'data': data.map((item) => item.toJson()).toList(),
      'time': time,
      'code_num': codeNum,
      'code_msg': codeMsg,
    };
  }
}

/// 相册时间线项
class AlbumTimelineItem {
  final int year;
  final int month;
  final int day;
  final int timestamp;
  final int photoCount;

  AlbumTimelineItem({
    required this.year,
    required this.month,
    required this.day,
    required this.timestamp,
    required this.photoCount,
  });

  factory AlbumTimelineItem.fromJson(Map<String, dynamic> json) {
    return AlbumTimelineItem(
      year: json['year'] as int? ?? 0,
      month: json['month'] as int? ?? 0,
      day: json['day'] as int? ?? 0,
      timestamp: json['timestamp'] as int? ?? 0,
      photoCount: json['photo_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'year': year,
      'month': month,
      'day': day,
      'timestamp': timestamp,
      'photo_count': photoCount,
    };
  }
}

/// 相册时间线响应
class AlbumTimelineResponse {
  final bool isLogin;
  final bool code;
  final String msg;
  final List<AlbumTimelineItem> data;
  final double time;
  final int codeNum;
  final String codeMsg;

  AlbumTimelineResponse({
    required this.isLogin,
    required this.code,
    required this.msg,
    required this.data,
    required this.time,
    required this.codeNum,
    required this.codeMsg,
  });

  factory AlbumTimelineResponse.fromJson(Map<String, dynamic> json) {
    return AlbumTimelineResponse(
      isLogin: json['is_login'] as bool? ?? false,
      code: json['code'] as bool? ?? false,
      msg: json['msg'] as String? ?? '',
      data:
          (json['data'] as List<dynamic>?)
              ?.map(
                (item) =>
                    AlbumTimelineItem.fromJson(item as Map<String, dynamic>),
              )
              .toList() ??
          [],
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
      'data': data.map((item) => item.toJson()).toList(),
      'time': time,
      'code_num': codeNum,
      'code_msg': codeMsg,
    };
  }
}
