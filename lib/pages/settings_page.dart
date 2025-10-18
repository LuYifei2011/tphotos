import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _selectedSpace = widget.defaultSpace == 1 ? 1 : 2;
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

  @override
  Widget build(BuildContext context) {
    final usernameLabel =
        (widget.username != null && widget.username!.isNotEmpty)
        ? widget.username!
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
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('当前账号'),
            subtitle: Text(usernameLabel),
          ),
          const Divider(),
          const ListTile(
            title: Text('默认空间'),
            subtitle: Text('用于决定启动时加载的空间，并立即应用到当前页面'),
          ),
          RadioListTile<int>(
            value: 1,
            groupValue: _selectedSpace,
            onChanged: (v) {
              if (v != null) _changeDefaultSpace(v);
            },
            title: const Text('个人空间'),
            secondary: const Icon(Icons.person),
          ),
          RadioListTile<int>(
            value: 2,
            groupValue: _selectedSpace,
            onChanged: (v) {
              if (v != null) _changeDefaultSpace(v);
            },
            title: const Text('公共空间'),
            secondary: const Icon(Icons.people),
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
              '提示：该设置会立即生效，并在下次启动时作为默认空间使用。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
