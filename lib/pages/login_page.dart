import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/tos_api.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

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
      _serverCtrl.text = prefs.getString('server') ?? 'http://192.168.2.2:8181';
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
    try {
      final api = TosAPI(_serverCtrl.text.trim());
      final res = await api.auth.login(
        _userCtrl.text.trim(),
        _passCtrl.text,
        keepLogin: _remember,
      );
      if (res['code'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('server', _serverCtrl.text.trim());
        await prefs.setString('username', _userCtrl.text.trim());
        if (_remember) {
          await prefs.setString('password', _passCtrl.text);
        } else {
          await prefs.remove('password');
        }
        await prefs.setBool('remember', _remember);

        if (!mounted) return;
        // 使用命名路由，避免页面间循环依赖
        Navigator.of(context).pushReplacementNamed(
          '/photos',
          arguments: api,
        );
      } else {
        setState(() => _error = res['msg']?.toString() ?? '登录失败');
      }
    } catch (e) {
      setState(() => _error = '登录失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
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
                        onChanged: (v) => setState(() => _remember = v ?? false),
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
