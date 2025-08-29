class PhotoItem {
  final int photoId;
  final int type;
  final String name;
  final String path;
  final int size;
  final int timestamp; // 注意：API中是"timetamp"，可能是拼写错误
  final String time;
  final String date;
  final int width;
  final int height;
  final int isCollect;
  final String thumbnailPath;

  PhotoItem({
    required this.photoId,
    required this.type,
    required this.name,
    required this.path,
    required this.size,
    required this.timestamp,
    required this.time,
    required this.date,
    required this.width,
    required this.height,
    required this.isCollect,
    required this.thumbnailPath,
  });

  factory PhotoItem.fromJson(Map<String, dynamic> json) {
    return PhotoItem(
      photoId: json['photo_id'] as int,
      type: json['type'] as int,
      name: json['name'] as String,
      path: json['path'] as String,
      size: json['size'] as int,
      timestamp: json['timetamp'] as int, // 使用"timetamp"匹配API响应
      time: json['time'] as String,
      date: json['date'] as String,
      width: json['width'] as int,
      height: json['height'] as int,
      isCollect: json['is_collect'] as int,
      thumbnailPath: json['thumbnail_path'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'photo_id': photoId,
      'type': type,
      'name': name,
      'path': path,
      'size': size,
      'timetamp': timestamp,
      'time': time,
      'date': date,
      'width': width,
      'height': height,
      'is_collect': isCollect,
      'thumbnail_path': thumbnailPath,
    };
  }
}

class PhotoListData {
  final int total;
  final List<PhotoItem> photoList;

  PhotoListData({
    required this.total,
    required this.photoList,
  });

  factory PhotoListData.fromJson(Map<String, dynamic> json) {
    return PhotoListData(
      total: json['total'] as int,
      photoList: (json['photo_list'] as List<dynamic>)
          .map((item) => PhotoItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'photo_list': photoList.map((item) => item.toJson()).toList(),
    };
  }
}

class PhotoListResponse {
  final bool isLogin;
  final bool code;
  final String msg;
  final PhotoListData data;
  final double time;
  final int codeNum;
  final String codeMsg;

  PhotoListResponse({
    required this.isLogin,
    required this.code,
    required this.msg,
    required this.data,
    required this.time,
    required this.codeNum,
    required this.codeMsg,
  });

  factory PhotoListResponse.fromJson(Map<String, dynamic> json) {
    return PhotoListResponse(
      isLogin: json['is_login'] as bool,
      code: json['code'] as bool,
      msg: json['msg'] as String,
      data: PhotoListData.fromJson(json['data'] as Map<String, dynamic>),
      time: (json['time'] as num).toDouble(),
      codeNum: json['code_num'] as int,
      codeMsg: json['code_msg'] as String,
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
