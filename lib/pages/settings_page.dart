import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/original_photo_manager.dart';
import '../widgets/thumbnail_manager.dart'; // For ThumbnailManager

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.connection,
    this.username,
    required this.defaultSpace,
    required this.onDefaultSpaceChanged,
  });

  final String connection;
  final String? username;
  final int defaultSpace;
  final Future<void> Function(int value) onDefaultSpaceChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late int _selectedSpace;
  bool _isSaving = false;
  bool _isClearingOriginalCache = false;
  bool _isClearingThumbnailCache = false;
  int _concurrentRequests = 6; // 默认并发数
  String? _appName;
  String? _appVersion;
  String? _savedLanServer;
  String? _savedDdnsServer;
  String? _savedTnasOnlineServer;
  int? _savedHttpsPort;
  bool _enableTptConnection = true;
  final Uri _repoUrl = Uri.parse('https://github.com/LuYifei2011/tphotos');

  @override
  void initState() {
    super.initState();
    _selectedSpace = widget.defaultSpace == 1 ? 1 : 2;
    _loadPackageInfo();
    _loadSavedServers();
    _loadTptSetting();
    _loadConcurrentRequests();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSaving && oldWidget.defaultSpace != widget.defaultSpace) {
      setState(() {
        _selectedSpace = widget.defaultSpace == 1 ? 1 : 2;
      });
    }
  }

  Future<void> _changeDefaultSpace(int value) async {
    if (_isSaving || value == _selectedSpace) return;
    final previous = _selectedSpace;
    setState(() {
      _selectedSpace = value;
      _isSaving = true;
    });
    try {
      await widget.onDefaultSpaceChanged(value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _selectedSpace = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('切换失败: $e')));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appName = info.appName;
        _appVersion = info.version;
      });
    } catch (_) {
      // Ignore errors and keep fallback values.
    }
  }

  Future<void> _loadSavedServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _savedLanServer = prefs.getString('server');
        _savedDdnsServer = prefs.getString('tnas_ddns_url');
        _savedTnasOnlineServer = prefs.getString('tnas_online_url');
        _savedHttpsPort = prefs.getInt('https_port');
      });
    } catch (_) {
      // Ignore errors if preferences are unavailable.
    }
  }

  Future<void> _loadTptSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _enableTptConnection = prefs.getBool('enable_tpt_connection') ?? false;
      });
    } catch (_) {
      // Ignore errors if preferences are unavailable.
    }
  }

  Future<void> _setTptSetting(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('enable_tpt_connection', value);
      if (!mounted) return;
      setState(() {
        _enableTptConnection = value;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  Future<void> _loadConcurrentRequests() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getInt('concurrent_requests') ?? 6;
      if (!mounted) return;
      setState(() {
        _concurrentRequests = value.clamp(1, 32);
      });
    } catch (_) {
      // Use default value on error.
    }
  }

  Future<void> _saveConcurrentRequests(int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('concurrent_requests', value);

      // 立即更新 ThumbnailManager，使设置即时生效
      ThumbnailManager.instance.updateMaxConcurrent(value);
      OriginalPhotoManager.instance.updateMaxConcurrent(value);

      if (!mounted) return;
      setState(() {
        _concurrentRequests = value;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已保存并应用：最大并发请求数 $value'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  Future<void> _clearOriginalDiskCache() async {
    if (_isClearingOriginalCache) return;
    setState(() => _isClearingOriginalCache = true);
    try {
      final removed = await OriginalPhotoManager.instance.clearDiskCache();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已清理原图磁盘缓存：$removed 项')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清理失败: $e')));
    } finally {
      if (mounted) {
        setState(() => _isClearingOriginalCache = false);
      }
    }
  }

  Future<void> _clearThumbnailDiskCache() async {
    if (_isClearingThumbnailCache) return;
    setState(() => _isClearingThumbnailCache = true);
    try {
      final removed = await ThumbnailManager.instance.clearDiskCache();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已清理缩略图磁盘缓存：$removed 项')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清理失败: $e')));
    } finally {
      if (mounted) {
        setState(() => _isClearingThumbnailCache = false);
      }
    }
  }

  void _showAbout() {
    final name = _appName ?? 'TPhotos';
    final version = _appVersion ?? '未知版本';
    showAboutDialog(
      context: context,
      applicationName: name,
      applicationVersion: version,
      applicationLegalese: '© 2025-2026 LuYifei2011',
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text('非官方TerraPhotos客户端。'),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextButton.icon(
            onPressed: _openGitHub,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('访问 GitHub 仓库'),
          ),
        ),
      ],
    );
  }

  Future<void> _openGitHub() async {
    if (!await launchUrl(_repoUrl, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开 GitHub 链接')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final usernameLabel =
        (widget.username != null && widget.username!.isNotEmpty)
        ? widget.username!
        : '未保存';
    final lanLabel = (_savedLanServer != null && _savedLanServer!.isNotEmpty)
        ? _savedLanServer!
        : '未保存';
    final ddnsLabel = (_savedDdnsServer != null && _savedDdnsServer!.isNotEmpty)
        ? _savedDdnsServer!
        : '未保存';
    final tnasOnlineLabel =
        (_savedTnasOnlineServer != null && _savedTnasOnlineServer!.isNotEmpty)
        ? _savedTnasOnlineServer!
        : '未保存';
    final httpsPort = _savedHttpsPort ?? 5443;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('当前连接'),
            subtitle: Text(widget.connection),
          ),
          ExpansionTile(
            leading: const Icon(Icons.storage),
            title: const Text('服务地址'),
            subtitle: const Text('本地 / DDNS / TNAS.online / TPT'),
            initiallyExpanded: false,
            children: [
              ListTile(
                leading: const Icon(Icons.home),
                title: const Text('本地地址（已保存）'),
                subtitle: Text(lanLabel),
              ),
              ListTile(
                leading: const Icon(Icons.public),
                title: const Text('DDNS 地址'),
                subtitle: Text(ddnsLabel),
              ),
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('TNAS.online 地址'),
                subtitle: Text(tnasOnlineLabel),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.usb),
                title: const Text('TPT连接（需要登录TNAS客户端）'),
                subtitle: Text('http://localhost:${httpsPort + 20000}'),
                value: _enableTptConnection,
                onChanged: _setTptSetting,
              ),
            ],
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('当前账号'),
            subtitle: Text(usernameLabel),
          ),
          const Divider(),
          const ListTile(title: Text('默认空间'), subtitle: Text('用于决定下次启动时加载的空间')),
          RadioGroup<int>(
            groupValue: _selectedSpace,
            onChanged: (v) {
              if (v != null) _changeDefaultSpace(v);
            },
            child: Column(
              children: [
                RadioListTile<int>(
                  value: 1,
                  title: const Text('个人空间'),
                  secondary: const Icon(Icons.person),
                ),
                RadioListTile<int>(
                  value: 2,
                  title: const Text('公共空间'),
                  secondary: const Icon(Icons.people),
                ),
              ],
            ),
          ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              '提示:该设置将在下次启动应用时生效。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const ListTile(title: Text('性能设置'), subtitle: Text('调整图片加载性能参数')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '最大并发请求数',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Text(
                      '$_concurrentRequests',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _concurrentRequests.toDouble(),
                  min: 1,
                  max: 32,
                  divisions: 31,
                  label: '$_concurrentRequests',
                  onChanged: (value) {
                    setState(() {
                      _concurrentRequests = value.toInt();
                    });
                  },
                  onChangeEnd: (value) {
                    _saveConcurrentRequests(value.toInt());
                  },
                ),
                Text(
                  '控制同时加载的图片数量。较高的值可加快加载速度，但会占用更多网络和内存资源。设置会立即生效。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).textTheme.bodySmall?.color?.withValues(alpha: .7),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('清理原图磁盘缓存'),
                  subtitle: const Text('删除已缓存的原图文件，下次查看会重新下载'),
                  trailing: _isClearingOriginalCache
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _isClearingOriginalCache
                      ? null
                      : _clearOriginalDiskCache,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('清理缩略图磁盘缓存'),
                  subtitle: const Text('删除已缓存的缩略图文件，下次浏览会重新下载'),
                  trailing: _isClearingThumbnailCache
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _isClearingThumbnailCache
                      ? null
                      : _clearThumbnailDiskCache,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(_appName ?? 'TPhotos'),
            subtitle: Text('版本 ${_appVersion ?? '获取中…'}'),
            onTap: _showAbout,
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('GitHub 仓库'),
            subtitle: Text(_repoUrl.toString()),
            onTap: _openGitHub,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
