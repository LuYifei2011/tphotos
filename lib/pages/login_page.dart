import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/tos_api.dart';
import '../api/tos_client.dart';

class LoginPage extends StatefulWidget {
  final ThemeMode? themeMode;
  final VoidCallback? onToggleTheme;
  const LoginPage({super.key, this.themeMode, this.onToggleTheme});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _serverCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _remember = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serverCtrl.text = prefs.getString('server') ?? 'http://tnas.local:8181';
      _userCtrl.text = prefs.getString('username') ?? '';
      _passCtrl.text = prefs.getString('password') ?? '';
      _remember = prefs.getBool('remember') ?? (_passCtrl.text.isNotEmpty);
    });
  }

  Future<void> _onLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final primaryServer = _serverCtrl.text.trim();
    SharedPreferences? prefs;
    TosAPI? api;
    late Map<String, dynamic> res;
    try {
      prefs = await SharedPreferences.getInstance();
      final fallbackServer = prefs.getString('tnas_online_url');

      Future<Map<String, dynamic>> attempt(String baseUrl) async {
        final currentApi = TosAPI(baseUrl);
        try {
          final response = await currentApi.auth.login(
            _userCtrl.text.trim(),
            _passCtrl.text,
            keepLogin: _remember,
          );
          api = currentApi;
          return response;
        } catch (e) {
          currentApi.dispose();
          rethrow;
        }
      }

      try {
        res = await attempt(primaryServer);
      } on Object catch (primaryError) {
        if (fallbackServer != null &&
            fallbackServer.isNotEmpty &&
            fallbackServer != primaryServer &&
            _isConnectivityError(primaryError)) {
          try {
            res = await attempt(fallbackServer);
          } on Object catch (fallbackError) {
            _setLoginError(primaryError, fallbackServer, fallbackError);
            return;
          }
        } else {
          _setLoginError(primaryError, null, null);
          return;
        }
      }

      final response = res;
      if (response['code'] == true) {
        await prefs.setString('server', primaryServer);
        await prefs.setString('username', _userCtrl.text.trim());
        if (_remember) {
          await prefs.setString('password', _passCtrl.text);
        } else {
          await prefs.remove('password');
        }
        await prefs.setBool('remember', _remember);
        await prefs.setString('server_last_used', api!.baseUrl);

        await _fetchAndStoreOnlineUrl(api!, prefs);

        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/photos', arguments: api);
      } else {
        api?.dispose();
        setState(() => _error = response['msg']?.toString() ?? '登录失败');
      }
    } catch (e) {
      api?.dispose();
      setState(() => _error = '登录失败: ${_describeError(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isConnectivityError(Object error) {
    return error is SocketException ||
        error is HandshakeException ||
        error is HttpException ||
        error is TimeoutException;
  }

  String _describeError(Object error) {
    if (error is APIError) {
      return '${error.message} (code: ${error.code})';
    }
    if (error is SocketException) {
      return error.message;
    }
    if (error is HandshakeException) {
      return 'TLS 握手失败';
    }
    if (error is HttpException) {
      return error.message;
    }
    if (error is TimeoutException) {
      return '请求超时';
    }
    return error.toString();
  }

  void _setLoginError(
    Object primaryError,
    String? fallbackServer,
    Object? fallbackError,
  ) {
    final buffer = StringBuffer(_describeError(primaryError));
    if (fallbackServer != null && fallbackError != null) {
      buffer.write('\n使用 TNAS Online 地址($fallbackServer) 时失败: ');
      buffer.write(_describeError(fallbackError));
    }
    setState(() => _error = '登录失败: $buffer');
  }

  Future<void> _fetchAndStoreOnlineUrl(
    TosAPI api,
    SharedPreferences prefs,
  ) async {
    try {
      final url = await api.online.nodeUrl();
      if (url != null && url.isNotEmpty) {
        await prefs.setString('tnas_online_url', url);
      }
    } catch (_) {
      // Ignore failures when fetching TNAS Online URL; login already succeeded.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        actions: [
          if (widget.onToggleTheme != null)
            IconButton(
              tooltip: _themeTooltip(widget.themeMode ?? ThemeMode.system),
              onPressed: widget.onToggleTheme,
              icon: Icon(_themeIcon(widget.themeMode ?? ThemeMode.system)),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _serverCtrl,
                    decoration: const InputDecoration(
                      labelText: '服务器地址（含协议，如 http://192.168.2.2:8181）',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入服务器地址' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(labelText: '用户名'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passCtrl,
                    decoration: const InputDecoration(labelText: '密码'),
                    obscureText: true,
                    validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: _remember,
                        onChanged: (v) =>
                            setState(() => _remember = v ?? false),
                      ),
                      const Text('记住我并自动登录'),
                    ],
                  ),
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _onLogin,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('登录'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _themeIcon(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return Icons.light_mode;
    case ThemeMode.dark:
      return Icons.dark_mode;
    case ThemeMode.system:
      return Icons.brightness_auto;
  }
}

String _themeTooltip(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return '浅色模式（点按切换）';
    case ThemeMode.dark:
      return '深色模式（点按切换）';
    case ThemeMode.system:
      return '跟随系统（点按切换）';
  }
}
