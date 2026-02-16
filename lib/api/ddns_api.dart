import 'tos_client.dart';

class DdnsAPI {
  final TosClient _client;

  DdnsAPI(this._client);

  /// Fetch HTTPS port from routine network config.
  Future<int> httpsPort() async {
    final response = await _client.get('/v2/networkSet/GetRoutineSetConf');
    final dynamic value = response['data']?['https_port'];
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value) ?? 5443;
    }
    return 5443;
  }

  /// Fetch DDNS host URL from /v2/ddns/; returns https://{host_name}:{port} when available.
  Future<String?> ddnsUrl() async {
    final response = await _client.get('/v2/ddns/');

    if (response['code'] != true) {
      final codeNum = response['code_num'];
      final codeMsg = response['code_msg'] ?? 'Failed to fetch DDNS URL';
      throw APIError(
        codeNum is int ? codeNum : 500,
        codeMsg is String ? codeMsg : 'Failed to fetch DDNS URL',
        response['data'],
      );
    }

    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      return null;
    }

    final records = data['records'];
    if (records is! List || records.isEmpty) {
      return null;
    }

    final httpsPort = await this.httpsPort();

    for (final record in records) {
      if (record is! Map<String, dynamic>) {
        continue;
      }
      final hostName = record['host_name'];
      if (hostName is String && hostName.isNotEmpty) {
        return 'https://$hostName:$httpsPort';
      }
    }

    return null;
  }
}
