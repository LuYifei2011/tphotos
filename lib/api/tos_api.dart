import 'tos_client.dart';
import 'auth_api.dart';
import 'photos_api.dart';

class TosAPI {
  final TosClient _client;
  late final AuthAPI auth;
  late final PhotosAPI photos;

  TosAPI(String baseUrl)
      : _client = TosClient(baseUrl) {
    auth = AuthAPI(_client);
    photos = PhotosAPI(_client);
  }

  /// Base URL of current server, used for composing absolute resource URLs.
  String get baseUrl => _client.baseUrl;

  void dispose() {
    _client.dispose();
  }
}
