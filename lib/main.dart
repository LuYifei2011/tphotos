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
  final ValueNotifier<String> _autoLoginStatus = ValueNotifier<String>(
    '准备自动登录...',
  );
  Completer<bool>? _cancelCompleter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initial = _decideInitialPage();
    _loadThemeMode();
    _applySystemUiOverlay(_themeMode);
  }

  void _cancelAutoLogin() {
    if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
      _cancelCompleter!.complete(true);
      _autoLoginStatus.value = '已取消自动登录';
    }
  }

  Future<TosAPI?> _decideInitialPage() async {
    _cancelCompleter = Completer<bool>();

    final prefs = await SharedPreferences.getInstance();
    final savedServer = prefs.getString('server');
    final savedUser = prefs.getString('username');
    final savedPass = prefs.getString('password');
    final remember = prefs.getBool('remember') ?? false;
    final ddnsServer = prefs.getString('tnas_ddns_url');
    final tnasOnlineServer = prefs.getString('tnas_online_url');
    final enableTptConnection =
      prefs.getBool('enable_tpt_connection') ?? false;
    final savedHttpsPort = prefs.getInt('https_port') ?? 5443;
    final tptServer = enableTptConnection
      ? 'http://localhost:${savedHttpsPort + 20000}'
      : null;

    if (savedServer != null && savedServer.isNotEmpty) {
      TosAPI? api;
      Object? primaryError;

      _autoLoginStatus.value = '正在尝试连接: $savedServer';
      if (_cancelCompleter!.isCompleted) return null;

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

      if (_cancelCompleter!.isCompleted) return null;
      if (api != null) {
        _autoLoginStatus.value = '登录成功！';
        return api;
      }

      final canUseFallback =
          primaryError != null && _isConnectivityError(primaryError);

      if (canUseFallback &&
          tptServer != null &&
          tptServer.isNotEmpty &&
          tptServer != savedServer) {
        _autoLoginStatus.value = '正在尝试 TPT 地址: $tptServer';
        if (_cancelCompleter!.isCompleted) return null;

        try {
          final tptApi = await _autoLoginWithBase(
            baseUrl: tptServer,
            prefs: prefs,
            username: savedUser,
            password: savedPass,
            remember: remember,
          );
          if (_cancelCompleter!.isCompleted) return null;
          if (tptApi != null) {
            _autoLoginStatus.value = '登录成功！';
            return tptApi;
          }
        } catch (_) {}
      }

      if (canUseFallback &&
          ddnsServer != null &&
          ddnsServer.isNotEmpty &&
          ddnsServer != savedServer &&
          ddnsServer != tptServer) {
        _autoLoginStatus.value = '正在尝试 DDNS 地址: $ddnsServer';
        if (_cancelCompleter!.isCompleted) return null;

        try {
          final ddnsApi = await _autoLoginWithBase(
            baseUrl: ddnsServer,
            prefs: prefs,
            username: savedUser,
            password: savedPass,
            remember: remember,
          );
          if (_cancelCompleter!.isCompleted) return null;
          if (ddnsApi != null) {
            _autoLoginStatus.value = '登录成功！';
            return ddnsApi;
          }
        } catch (_) {}
      }

      final shouldTryTnasOnlineFallback =
          tnasOnlineServer != null &&
          tnasOnlineServer.isNotEmpty &&
          tnasOnlineServer != savedServer &&
          tnasOnlineServer != tptServer &&
          canUseFallback;

      if (shouldTryTnasOnlineFallback) {
        _autoLoginStatus.value = '正在尝试 TNAS.online 地址: $tnasOnlineServer';
        if (_cancelCompleter!.isCompleted) return null;

        try {
          final fallbackApi = await _autoLoginWithBase(
            baseUrl: tnasOnlineServer,
            prefs: prefs,
            username: savedUser,
            password: savedPass,
            remember: remember,
          );
          if (_cancelCompleter!.isCompleted) return null;
          if (fallbackApi != null) {
            _autoLoginStatus.value = '登录成功！';
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
    _autoLoginStatus.dispose();
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

        // 全平台统一使用支持预测性返回的页面过渡动画
        const pageTransitionsTheme = PageTransitionsTheme(
          builders: {
            TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
            TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          },
        );

        return MaterialApp(
          title: 'TPhotos',
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: lightColorScheme,
            pageTransitionsTheme: pageTransitionsTheme,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: darkColorScheme,
            pageTransitionsTheme: pageTransitionsTheme,
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
                return _AutoLoginScreen(
                  statusNotifier: _autoLoginStatus,
                  onCancel: _cancelAutoLogin,
                  themeMode: _themeMode,
                  onToggleTheme: _toggleThemeMode,
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
      await _refreshHttpsPort(api, prefs);
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
        await _refreshHttpsPort(api, prefs);
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

  Future<void> _refreshHttpsPort(TosAPI api, SharedPreferences prefs) async {
    try {
      final httpsPort = await api.ddns.httpsPort();
      await prefs.setInt('https_port', httpsPort);
    } catch (_) {
      // 忽略 https 端口刷新失败
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

/// 自动登录状态显示页面
class _AutoLoginScreen extends StatelessWidget {
  final ValueNotifier<String> statusNotifier;
  final VoidCallback onCancel;
  final ThemeMode? themeMode;
  final VoidCallback? onToggleTheme;

  const _AutoLoginScreen({
    required this.statusNotifier,
    required this.onCancel,
    this.themeMode,
    this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('自动登录中'),
        actions: [
          if (onToggleTheme != null)
            IconButton(
              tooltip: _themeTooltip(themeMode ?? ThemeMode.system),
              onPressed: onToggleTheme,
              icon: Icon(_themeIcon(themeMode ?? ThemeMode.system)),
            ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              ValueListenableBuilder<String>(
                valueListenable: statusNotifier,
                builder: (context, status, _) {
                  return Text(
                    status,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  );
                },
              ),
              const SizedBox(height: 32),
              OutlinedButton(onPressed: onCancel, child: const Text('取消')),
            ],
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
