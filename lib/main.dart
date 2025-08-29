import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api/tos_api.dart';
import 'pages/login_page.dart';
import 'pages/photos_page.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  Future<Widget>? _initial;

  @override
  void initState() {
    super.initState();
    _initial = _decideInitialPage();
  }

  Future<Widget> _decideInitialPage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedServer = prefs.getString('server');
    final savedUser = prefs.getString('username');
    final savedPass = prefs.getString('password');
    final remember = prefs.getBool('remember') ?? false;

    if (savedServer != null && savedServer.isNotEmpty) {
      final api = TosAPI(savedServer);
      // 尝试会话有效性
      try {
        final state = await api.auth.isLoginState();
        if (state['code'] == true) {
          return PhotosPage(api: api);
        }
      } catch (_) {}

      // 自动登录
      if (remember && savedUser != null && savedPass != null) {
        try {
          final res = await api.auth.login(
            savedUser,
            savedPass,
            keepLogin: true,
          );
          if (res['code'] == true) {
            return PhotosPage(api: api);
          }
        } catch (_) {}
      }
    }
    // 无服务器地址或登录失败，进入登录页（可输入服务器地址）
    return const LoginPage();
  }

  // 无需在此处统一释放 API，由页面持有并在登出时释放
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TOS Photos',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      routes: {
        '/login': (_) => const LoginPage(),
        '/photos': (ctx) {
          final args = ModalRoute.of(ctx)!.settings.arguments;
          if (args is TosAPI) {
            return PhotosPage(api: args);
          }
          // 回退到登录
          return const LoginPage();
        },
      },
      home: FutureBuilder<Widget>(
        future: _initial,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final page = snapshot.data ?? const LoginPage();
          return page;
        },
      ),
    );
  }
}

// pages moved to: pages/login_page.dart and pages/photos_page.dart
