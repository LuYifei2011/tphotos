import 'dart:convert';

import 'tos_client.dart';

class OnlineAPI {
  final TosClient _client;

  OnlineAPI(this._client);

  /// Fetch node_url from online status; returns null when cloudnas component not present.
  Future<String?> nodeUrl() async {
    // 响应头是 text/plain 需要手动解析
    final response = jsonDecode((await _client.get('/v2/srv/online2/status'))['body']);

    if (response['code'] != true) {
      final codeNum = response['code_num'];
      final codeMsg = response['code_msg'] ?? 'Failed to fetch online status';
      throw APIError(
        codeNum is int ? codeNum : 500,
        codeMsg is String ? codeMsg : 'Failed to fetch online status',
        response['data'],
      );
    }

    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      return null;
    }

    final components = data['components'];
    if (components is! List) {
      return null;
    }

    for (final componentEntry in components) {
      if (componentEntry is! Map<String, dynamic>) {
        continue;
      }
      if (componentEntry['component'] != 'cloudnas') {
        continue;
      }
      final state = componentEntry['state'];
      if (state is! Map<String, dynamic>) {
        continue;
      }
      final nodeUrl = state['node_url'];
      if (nodeUrl is String && nodeUrl.isNotEmpty) {
        return nodeUrl;
      }
    }

    return null;
  }
}
