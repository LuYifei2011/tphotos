import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class APIError implements Exception {
  final int code;
  final String message;
  final dynamic data;

  APIError(this.code, this.message, this.data);

  @override
  String toString() => 'APIError: $code - $message';
}

class TosClient {
  final String baseUrl;
  final http.Client _client;
  final Map<String, String> _cookies = {};
  String? _csrfToken;

  TosClient(this.baseUrl) : _client = http.Client();

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? params, Map<String, String>? headers, bool includeHeaders = false}) async {
    final url = Uri.parse('$baseUrl$path').replace(queryParameters: params);
    final response = await _client.get(url, headers: _buildHeaders(headers));
    final parsed = _handleResponse(response);
    if (includeHeaders) {
      return {
        'data': parsed,
        'headers': response.headers,
        'statusCode': response.statusCode,
        'contentType': response.headers['content-type'] ?? '',
      };
    }
    return parsed;
  }

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? json, Map<String, String>? data, Map<String, String>? headers}) async {
    final url = Uri.parse('$baseUrl$path');
    final response = await _client.post(
      url,
      headers: _buildHeaders(headers),
      body: json != null ? jsonEncode(json) : data,
    );
    return _handleResponse(response);
  }

  /// Fetch binary content while preserving cookies/headers.
  Future<Uint8List> getBytes(String path, {Map<String, String>? params, Map<String, String>? headers}) async {
    final url = Uri.parse('$baseUrl$path').replace(queryParameters: params);
    final response = await _client.get(url, headers: _buildHeaders(headers));
    _updateCookies(response);
    _updateCsrfToken(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    } else {
      try {
        final data = jsonDecode(response.body);
        throw APIError(response.statusCode, data['msg'] ?? 'Unknown error', data['data']);
      } catch (e) {
        if (e is APIError) rethrow;
        throw APIError(response.statusCode, 'Binary response failed with status ${response.statusCode}', null);
      }
    }
  }

  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? json, Map<String, String>? headers}) async {
    final url = Uri.parse('$baseUrl$path');
    final response = await _client.put(
      url,
      headers: _buildHeaders(headers),
      body: json != null ? jsonEncode(json) : null,
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> delete(String path, {Map<String, dynamic>? json, Map<String, String>? headers}) async {
    final url = Uri.parse('$baseUrl$path');
    final response = await _client.delete(
      url,
      headers: _buildHeaders(headers),
      body: json != null ? jsonEncode(json) : null,
    );
    return _handleResponse(response);
  }

  Map<String, String> _buildHeaders(Map<String, String>? additionalHeaders) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
    };
    if (_csrfToken != null) {
      headers['X-CSRF-Token'] = _csrfToken!;
    }
    if (additionalHeaders != null) {
      headers.addAll(additionalHeaders);
    }
    return headers;
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    _updateCookies(response);
    _updateCsrfToken(response);

    final contentType = response.headers['content-type'] ?? '';

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // 检查是否是JSON响应
      if (contentType.contains('application/json')) {
        try {
          return jsonDecode(response.body);
        } catch (e) {
          // 如果JSON解析失败，返回原始响应体
          return {'body': response.body, 'contentType': contentType};
        }
      } else {
        // 对于非JSON响应（如HTML），返回包含响应体的Map
        return {
          'body': response.body,
          'contentType': contentType,
          'statusCode': response.statusCode
        };
      }
    } else {
      // 错误响应：尝试解析JSON错误信息，如果失败则返回原始响应
      try {
        final data = jsonDecode(response.body);
        throw APIError(response.statusCode, data['msg'] ?? 'Unknown error', data['data']);
      } catch (e) {
        if (e is APIError) rethrow;
        throw APIError(response.statusCode, 'Response parsing failed: ${response.body}', null);
      }
    }
  }

  void _updateCookies(http.Response response) {
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null) {
      final cookies = setCookie.split(',');
      for (final cookie in cookies) {
        final parts = cookie.split(';')[0].split('=');
        if (parts.length == 2) {
          _cookies[parts[0].trim()] = parts[1].trim();
        }
      }
    }
  }

  void _updateCsrfToken(http.Response response) {
    final csrfFromCookie = _cookies['X-Csrf-Token'];
    if (csrfFromCookie != null) {
      _csrfToken = csrfFromCookie;
    }
  }

  void dispose() {
    _client.close();
  }
}
