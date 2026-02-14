/// 文件夹权限
class FolderPermission {
  final bool view;
  final bool upload;
  final bool manage;

  FolderPermission({
    required this.view,
    required this.upload,
    required this.manage,
  });

  factory FolderPermission.fromJson(Map<String, dynamic> json) {
    return FolderPermission(
      view: json['view'] as bool? ?? false,
      upload: json['upload'] as bool? ?? false,
      manage: json['manage'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'view': view, 'upload': upload, 'manage': manage};
  }
}

/// 文件夹缩略图
class FolderThumbnail {
  final String path;
  final String thumbnailPath;

  FolderThumbnail({required this.path, required this.thumbnailPath});

  factory FolderThumbnail.fromJson(Map<String, dynamic> json) {
    return FolderThumbnail(
      path: json['path'] as String? ?? '',
      thumbnailPath: json['thumbnail_path'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'path': path, 'thumbnail_path': thumbnailPath};
  }
}

/// 文件夹附加信息
class FolderAdditional {
  final List<FolderThumbnail> thumbnail;
  final FolderPermission permission;

  FolderAdditional({required this.thumbnail, required this.permission});

  factory FolderAdditional.fromJson(Map<String, dynamic> json) {
    return FolderAdditional(
      thumbnail:
          (json['thumbnail'] as List<dynamic>?)
              ?.map((e) => FolderThumbnail.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      permission: FolderPermission.fromJson(
        json['permission'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'thumbnail': thumbnail.map((e) => e.toJson()).toList(),
      'permission': permission.toJson(),
    };
  }
}

/// 文件夹信息
class FolderInfo {
  final FolderAdditional additional;
  final String showFolder;
  final String relativelyPath;
  final String searchPhotoDir;

  FolderInfo({
    required this.additional,
    required this.showFolder,
    required this.relativelyPath,
    required this.searchPhotoDir,
  });

  factory FolderInfo.fromJson(Map<String, dynamic> json) {
    return FolderInfo(
      additional: FolderAdditional.fromJson(
        json['additional'] as Map<String, dynamic>? ?? {},
      ),
      showFolder: json['show_folder'] as String? ?? '',
      relativelyPath: json['relatively_path'] as String? ?? '',
      searchPhotoDir: json['search_photo_dir'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'additional': additional.toJson(),
      'show_folder': showFolder,
      'relatively_path': relativelyPath,
      'search_photo_dir': searchPhotoDir,
    };
  }

  /// 获取第一个缩略图路径（如果有）
  String? get firstThumbnailPath {
    if (additional.thumbnail.isEmpty) return null;
    return additional.thumbnail.first.thumbnailPath;
  }

  /// 是否有缩略图
  bool get hasThumbnail => additional.thumbnail.isNotEmpty;
}

/// 文件夹列表数据
class FolderModeData {
  final List<FolderInfo> photoDirInfo;
  final int total;

  FolderModeData({required this.photoDirInfo, required this.total});

  factory FolderModeData.fromJson(Map<String, dynamic> json) {
    return FolderModeData(
      photoDirInfo:
          (json['photo_dir_info'] as List<dynamic>?)
              ?.map((e) => FolderInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      total: json['total'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'photo_dir_info': photoDirInfo.map((e) => e.toJson()).toList(),
      'total': total,
    };
  }
}

/// 文件夹模式响应
class FolderModeResponse {
  final bool isLogin;
  final bool code;
  final String msg;
  final FolderModeData data;
  final double time;
  final int codeNum;
  final String codeMsg;

  FolderModeResponse({
    required this.isLogin,
    required this.code,
    required this.msg,
    required this.data,
    required this.time,
    required this.codeNum,
    required this.codeMsg,
  });

  factory FolderModeResponse.fromJson(Map<String, dynamic> json) {
    return FolderModeResponse(
      isLogin: json['is_login'] as bool? ?? false,
      code: json['code'] as bool? ?? false,
      msg: json['msg'] as String? ?? '',
      data: FolderModeData.fromJson(
        json['data'] as Map<String, dynamic>? ?? {},
      ),
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
