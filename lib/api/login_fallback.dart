enum LoginEndpointKind { primary, tpt, ddns, tnasOnline }

class LoginEndpoint {
  final LoginEndpointKind kind;
  final String baseUrl;

  const LoginEndpoint({required this.kind, required this.baseUrl});

  String get label {
    switch (kind) {
      case LoginEndpointKind.primary:
        return '主地址';
      case LoginEndpointKind.tpt:
        return 'TPT 地址';
      case LoginEndpointKind.ddns:
        return 'DDNS 地址';
      case LoginEndpointKind.tnasOnline:
        return 'TNAS.online 地址';
    }
  }
}

List<LoginEndpoint> buildLoginEndpoints({
  required String primaryServer,
  String? tptServer,
  String? ddnsServer,
  String? tnasOnlineServer,
}) {
  final endpoints = <LoginEndpoint>[];
  final seen = <String>{};

  void add(LoginEndpointKind kind, String? rawUrl) {
    final url = rawUrl?.trim();
    if (url == null || url.isEmpty) {
      return;
    }
    if (seen.add(url)) {
      endpoints.add(LoginEndpoint(kind: kind, baseUrl: url));
    }
  }

  add(LoginEndpointKind.primary, primaryServer);
  add(LoginEndpointKind.tpt, tptServer);
  add(LoginEndpointKind.ddns, ddnsServer);
  add(LoginEndpointKind.tnasOnline, tnasOnlineServer);

  return endpoints;
}
