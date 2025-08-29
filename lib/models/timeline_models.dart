class TimelineItem {
  final int year;
  final int month;
  final int day;
  final int timestamp;
  final int photoCount;

  TimelineItem({
    required this.year,
    required this.month,
    required this.day,
    required this.timestamp,
    required this.photoCount,
  });

  factory TimelineItem.fromJson(Map<String, dynamic> json) {
    return TimelineItem(
      year: json['year'] as int,
      month: json['month'] as int,
      day: json['day'] as int,
      timestamp: json['timestamp'] as int,
      photoCount: json['photo_count'] as int,
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

class TimelineResponse {
  final bool isLogin;
  final bool code;
  final String msg;
  final List<TimelineItem> data;
  final double time;
  final int codeNum;
  final String codeMsg;

  TimelineResponse({
    required this.isLogin,
    required this.code,
    required this.msg,
    required this.data,
    required this.time,
    required this.codeNum,
    required this.codeMsg,
  });

  factory TimelineResponse.fromJson(Map<String, dynamic> json) {
    return TimelineResponse(
      isLogin: json['is_login'] as bool,
      code: json['code'] as bool,
      msg: json['msg'] as String,
      data: (json['data'] as List<dynamic>)
          .map((item) => TimelineItem.fromJson(item as Map<String, dynamic>))
          .toList(),
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
      'data': data.map((item) => item.toJson()).toList(),
      'time': time,
      'code_num': codeNum,
      'code_msg': codeMsg,
    };
  }
}
