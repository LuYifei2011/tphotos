import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/asymmetric/api.dart' as pc;
import 'tos_client.dart';

class AuthAPI {
  final TosClient _client;

  AuthAPI(this._client);

  Future<Map<String, dynamic>> login(
    String username,
    String password, {
    String code = "",
    bool keepLogin = false,
  }) async {
    // 获取CSRF Token
    await _client.get('/tos/');

    // 获取RSA公钥
    final langResponse = await _client.get(
      '/v2/lang/tos',
      includeHeaders: true,
    );
    final rsaToken = langResponse['headers']?['x-rsa-token'];
    if (rsaToken == null) {
      throw APIError(400, 'Failed to get RSA token', null);
    }

    // 解析 header 中的 RSA 公钥（x-rsa-token 为 PEM 文本的 Base64）
    final publicKey = _parsePublicKey(rsaToken);
    final rsa = encrypt.Encrypter(
      encrypt.RSA(publicKey: publicKey, encoding: encrypt.RSAEncoding.PKCS1),
    );

    // 使用 RSA 加密密码，并用 base64 传输
    final encryptedPassword = rsa.encrypt(password).base64;

    // 发送登录请求
    final loginData = {
      'username': username,
      'password': encryptedPassword,
      'remember': keepLogin,
      'code': code,
    };

    return await _client.post('/v2/login', json: loginData);
  }

  Future<Map<String, dynamic>> logout() async {
    return await _client.put('/v2/logout', json: {});
  }

  Future<Map<String, dynamic>> isLoginState() async {
    return await _client.get('/v2/login/state');
  }

  Future<Map<String, dynamic>> keepLogin(String shareKey) async {
    final headers = {'share_key': shareKey};
    return await _client.put('/v2/system/share', json: {}, headers: headers);
  }

  // 将 x-rsa-token 作为 "PEM 文本的 Base64" 解析；若解码失败则回退视为原始 PEM
  pc.RSAPublicKey _parsePublicKey(String token) {
    final pemText = utf8.decode(base64.decode(token)).replaceAll("RSA ", "");
    final parsed = encrypt.RSAKeyParser().parse(pemText);
    if (parsed is pc.RSAPublicKey) return parsed;
    throw APIError(400, 'Parsed key is not RSAPublicKey', null);
  }
}
