import 'tos_client.dart';
import 'auth_api.dart';
import 'photos_api.dart';
import 'online_api.dart';
import 'ddns_api.dart';
import 'face_api.dart';
import 'scene_api.dart';

class TosAPI {
  final TosClient _client;
  late final AuthAPI auth;
  late final PhotosAPI photos;
  late final OnlineAPI online;
  late final DdnsAPI ddns;
  late final FaceAPI face;
  late final SceneAPI scene;

  TosAPI(String baseUrl) : _client = TosClient(baseUrl) {
    auth = AuthAPI(_client);
    photos = PhotosAPI(_client);
    online = OnlineAPI(_client);
    ddns = DdnsAPI(_client);
    face = FaceAPI(_client);
    scene = SceneAPI(_client);
  }

  /// Base URL of current server, used for composing absolute resource URLs.
  String get baseUrl => _client.baseUrl;

  void dispose() {
    _client.dispose();
  }
}
