import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
  String? _appName;
  String? _appVersion;
  String? _savedLanServer;
  String? _savedDdnsServer;
  String? _savedTnasOnlineServer;
  final Uri _repoUrl = Uri.parse('https://github.com/LuYifei2011/tphotos');

  @override
  void initState() {
    super.initState();
    _selectedSpace = widget.defaultSpace == 1 ? 1 : 2;
    _loadPackageInfo();
    _loadSavedServers();
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
      });
    } catch (_) {
      // Ignore errors if preferences are unavailable.
    }
  }

  void _showAbout() {
    final name = _appName ?? 'TPhotos';
    final version = _appVersion ?? '未知版本';
    showAboutDialog(
      context: context,
      applicationName: name,
      applicationVersion: version,
      applicationLegalese: '© 2025 LuYifei2011',
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
            subtitle: const Text('本地 / DDNS / TNAS.online'),
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
