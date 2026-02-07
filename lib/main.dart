import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'api/tos_api.dart';
import 'api/tos_client.dart';
import 'pages/login_page.dart';
import 'pages/photos_page.dart';
import 'package:fvp/fvp.dart' as fvp;

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
          systemStatusBarContrastEnforced: false,
        ),
      );
      // 使用 fvp 替换/增强 video_player，在桌面优先启用
      try {
        fvp.registerWith(
          options: {
            'platforms': ['windows', 'macos', 'linux', 'android', 'ios'],
            // 可按需添加解码器或低延迟设置
            'video.decoders': ['D3D11', 'NVDEC', 'FFmpeg'],
          },
        );
      } catch (e) {
        debugPrint('fvp register failed: $e');
      }
      FlutterError.onError = (details) {
        debugPrint('FlutterError: ${details.exceptionAsString()}');
        if (details.stack != null) {
          debugPrint(details.stack.toString());
        }
      };
      runApp(const MainApp());
    },
    (error, stack) {
      debugPrint('Uncaught zone error: $error');
      debugPrint(stack.toString());
    },
  );
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WidgetsBindingObserver {
  Future<TosAPI?>? _initial;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initial = _decideInitialPage();
    _loadThemeMode();
    _applySystemUiOverlay(_themeMode);
  }

  Future<TosAPI?> _decideInitialPage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedServer = prefs.getString('server');
    final savedUser = prefs.getString('username');
    final savedPass = prefs.getString('password');
    final remember = prefs.getBool('remember') ?? false;
    final ddnsServer = prefs.getString('tnas_ddns_url');
    final tnasOnlineServer = prefs.getString('tnas_online_url');

    if (savedServer != null && savedServer.isNotEmpty) {
      TosAPI? api;
      Object? primaryError;
      try {
        api = await _autoLoginWithBase(
          baseUrl: savedServer,
          prefs: prefs,
          username: savedUser,
          password: savedPass,
          remember: remember,
        );
      } on Object catch (e) {
        primaryError = e;
      }

      if (api != null) {
        return api;
      }

      final canUseFallback =
          primaryError != null && _isConnectivityError(primaryError);

      if (canUseFallback &&
          ddnsServer != null &&
          ddnsServer.isNotEmpty &&
          ddnsServer != savedServer) {
        try {
          final ddnsApi = await _autoLoginWithBase(
            baseUrl: ddnsServer,
            prefs: prefs,
            username: savedUser,
            password: savedPass,
            remember: remember,
          );
          if (ddnsApi != null) {
            return ddnsApi;
          }
        } catch (_) {}
      }

      final shouldTryTnasOnlineFallback =
          tnasOnlineServer != null &&
          tnasOnlineServer.isNotEmpty &&
          tnasOnlineServer != savedServer &&
          canUseFallback;

      if (shouldTryTnasOnlineFallback) {
        try {
          final fallbackApi = await _autoLoginWithBase(
            baseUrl: tnasOnlineServer,
            prefs: prefs,
            username: savedUser,
            password: savedPass,
            remember: remember,
          );
          if (fallbackApi != null) {
            return fallbackApi;
          }
        } catch (_) {}
      }
    }
    // 无服务器地址或登录失败，返回 null（进入登录页）
    return null;
  }

  // 无需在此处统一释放 API，由页面持有并在登出时释放
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString('themeMode');
    setState(() {
      _themeMode = _parseThemeMode(modeStr);
    });
    _applySystemUiOverlay(_themeMode);
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
    _applySystemUiOverlay(next);
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    if (_themeMode == ThemeMode.system) {
      _applySystemUiOverlay(ThemeMode.system);
    }
  }

  void _applySystemUiOverlay(ThemeMode mode) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final platformBrightness = dispatcher.platformBrightness;
    Brightness target;
    switch (mode) {
      case ThemeMode.light:
        target = Brightness.light;
        break;
      case ThemeMode.dark:
        target = Brightness.dark;
        break;
      case ThemeMode.system:
        target = platformBrightness;
        break;
    }
    final iconBrightness = target == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    final overlay = SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarContrastEnforced: false,
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness: target,
      systemStatusBarContrastEnforced: false,
    );
    SystemChrome.setSystemUIOverlayStyle(overlay);
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // 使用动态配色（如果可用），否则回退到蓝色种子色
        ColorScheme lightColorScheme;
        ColorScheme darkColorScheme;

        if (lightDynamic != null && darkDynamic != null) {
          // 系统支持动态配色，使用系统配色
          lightColorScheme = lightDynamic.harmonized();
          darkColorScheme = darkDynamic.harmonized();
        } else {
          // 无动态配色，回退到默认蓝色主题
          lightColorScheme = ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          );
          darkColorScheme = ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          );
        }

        return MaterialApp(
          title: 'TPhotos',
          theme: ThemeData(useMaterial3: true, colorScheme: lightColorScheme),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: darkColorScheme,
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
          home: FutureBuilder<TosAPI?>(
            future: _initial,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              final api = snapshot.data;
              if (api != null) {
                return PhotosPage(
                  api: api,
                  themeMode: _themeMode,
                  onToggleTheme: _toggleThemeMode,
                );
              }
              return LoginPage(
                themeMode: _themeMode,
                onToggleTheme: _toggleThemeMode,
              );
            },
          ),
        );
      },
    );
  }

  bool _isConnectivityError(Object error) {
    return error is SocketException ||
        error is HandshakeException ||
        error is HttpException ||
        error is TimeoutException;
  }

  Future<TosAPI?> _autoLoginWithBase({
    required String baseUrl,
    required SharedPreferences prefs,
    String? username,
    String? password,
    required bool remember,
  }) async {
    final api = TosAPI(baseUrl);
    Map<String, dynamic>? state;
    try {
      state = await api.auth.isLoginState();
    } on APIError {
      // 会话已失效，继续尝试登录
    } on Object catch (e) {
      api.dispose();
      if (_isConnectivityError(e)) {
        rethrow;
      }
      return null;
    }

    if (state != null && state['code'] == true) {
      await _refreshTnasOnlineUrl(api, prefs);
      await _refreshDdnsUrl(api, prefs);
      return api;
    }

    if (!remember || username == null || password == null) {
      api.dispose();
      return null;
    }

    try {
      final res = await api.auth.login(username, password, keepLogin: true);
      if (res['code'] == true) {
        await _refreshTnasOnlineUrl(api, prefs);
        await _refreshDdnsUrl(api, prefs);
        return api;
      }
    } on APIError {
      api.dispose();
      return null;
    } on Object catch (e) {
      api.dispose();
      if (_isConnectivityError(e)) {
        rethrow;
      }
      return null;
    }

    api.dispose();
    return null;
  }

  Future<void> _refreshTnasOnlineUrl(
    TosAPI api,
    SharedPreferences prefs,
  ) async {
    try {
      final url = await api.online.nodeUrl();
      if (url != null && url.isNotEmpty) {
        await prefs.setString('tnas_online_url', url);
      }
    } catch (_) {
      // 忽略在线地址刷新失败
    }
  }

  Future<void> _refreshDdnsUrl(TosAPI api, SharedPreferences prefs) async {
    try {
      final url = await api.ddns.ddnsUrl();
      if (url != null && url.isNotEmpty) {
        await prefs.setString('tnas_ddns_url', url);
      }
    } catch (_) {
      // 忽略 DDNS 地址刷新失败
    }
  }
}
