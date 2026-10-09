/// Settings: server health probe, TV-mode override, core version.

import 'package:flutter/material.dart';

import '../core/aftab_ffi.dart';
import '../core/catalog.dart';
import '../core/store.dart';
import '../main.dart' show AftabVersionLabel;
import 'home_screen.dart' show AftabAppBar;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _catalog = CatalogClient.instance;
  final _store = AftabStore.instance;

  static const _tvModeSetting = 'tv_mode';

  List<Map<String, dynamic>>? _health;
  String? _healthError;
  bool _tvMode = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tv = await _store.getSetting(_tvModeSetting);
      if (mounted) setState(() => _tvMode = tv == '1');
    } on AftabException {
      // Settings are best-effort; the screen still renders.
    }
    try {
      final health = await _catalog.health();
      if (!mounted) return;
      setState(() {
        _health = health;
        _healthError = null;
      });
    } on AftabException catch (e) {
      if (mounted) setState(() => _healthError = e.message);
    }
  }

  Future<void> _setTvMode(bool value) async {
    await _store.setSetting(_tvModeSetting, value ? '1' : '0');
    if (mounted) setState(() => _tvMode = value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('برای اعمال حالت تلویزیون، برنامه را دوباره باز کنید'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AftabAppBar(title: 'تنظیمات'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('سرورها', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          _buildHealth(theme),
          const SizedBox(height: 24),
          Text('نمایش', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('حالت تلویزیون (Android TV)'),
            subtitle: const Text('رابط کاربری فوکوس‌محور برای کنترل از راه دور'),
            value: _tvMode,
            onChanged: _setTvMode,
          ),
          const SizedBox(height: 24),
          const AftabVersionLabel(),
        ],
      ),
    );
  }

  Widget _buildHealth(ThemeData theme) {
    if (_healthError != null) {
      return Text('بررسی سرورها ناموفق بود: $_healthError',
          style: theme.textTheme.bodySmall);
    }
    if (_health == null) {
      return const Row(
        children: <Widget>[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('در حال بررسی سرورها…'),
        ],
      );
    }
    return Column(
      children: <Widget>[
        for (final server in _health!)
          ListTile(
            dense: true,
            leading: Icon(
              server['ok'] == true ? Icons.check_circle : Icons.cancel,
              color: server['ok'] == true
                  ? Colors.green
                  : theme.colorScheme.error,
            ),
            title: Text('${server['server']}'),
            subtitle: Text(server['ok'] == true ? 'در دسترس' : 'بی‌پاسخ'),
          ),
      ],
    );
  }
}
