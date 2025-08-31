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
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _initial = _decideInitialPage();
    _loadThemeMode();
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
          return PhotosPage(
            api: api,
            themeMode: _themeMode,
            onToggleTheme: _toggleThemeMode,
          );
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
            return PhotosPage(
              api: api,
              themeMode: _themeMode,
              onToggleTheme: _toggleThemeMode,
            );
          }
        } catch (_) {}
      }
    }
    // 无服务器地址或登录失败，进入登录页（可输入服务器地址）
  return LoginPage(themeMode: _themeMode, onToggleTheme: _toggleThemeMode);
  }

  // 无需在此处统一释放 API，由页面持有并在登出时释放
  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString('themeMode');
    setState(() {
      _themeMode = _parseThemeMode(modeStr);
    });
  }

  ThemeMode _parseThemeMode(String? s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> _toggleThemeMode() async {
    ThemeMode next;
    if (_themeMode == ThemeMode.system) {
      next = ThemeMode.light;
    } else if (_themeMode == ThemeMode.light) {
      next = ThemeMode.dark;
    } else {
      next = ThemeMode.system;
    }
    setState(() => _themeMode = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', _themeModeToString(next));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TPhotos',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
      ),
      themeMode: _themeMode,
      routes: {
        '/login': (_) => LoginPage(
              themeMode: _themeMode,
              onToggleTheme: _toggleThemeMode,
            ),
        '/photos': (ctx) {
          final args = ModalRoute.of(ctx)!.settings.arguments;
          if (args is TosAPI) {
            return PhotosPage(
              api: args,
              themeMode: _themeMode,
              onToggleTheme: _toggleThemeMode,
            );
          }
          // 回退到登录
          return LoginPage(
            themeMode: _themeMode,
            onToggleTheme: _toggleThemeMode,
          );
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
          final page = snapshot.data ??
              LoginPage(
                themeMode: _themeMode,
                onToggleTheme: _toggleThemeMode,
              );
          return page;
        },
      ),
    );
  }
}
