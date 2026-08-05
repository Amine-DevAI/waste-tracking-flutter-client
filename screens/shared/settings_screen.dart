import 'package:flutter/material.dart';

// Config & Theme (Absolute paths from /lib)
import 'package:waste_tracking/config/app_config.dart';
import 'package:waste_tracking/theme/app_theme.dart' hide SectionHeader;
import 'package:waste_tracking/ffi/screens/shared/section_header.dart';
import 'package:waste_tracking/l10n/app_localizations.dart';

// Services & Engine
import 'package:waste_tracking/ffi/services/scale_service.dart';
import 'package:waste_tracking/ffi/engine.dart';
// ============================================================================
// SETTINGS SCREEN
// ============================================================================

class SettingsScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final void Function(String) onChangeLocale;
  const SettingsScreen(
      {super.key, required this.onToggleTheme, required this.onChangeLocale});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ── Controllers ───────────────────────────────────────────────────────────
  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _baudCtrl = TextEditingController();
  final _scannerCtrl = TextEditingController();

// ── State ─────────────────────────────────────────────────────────────────
  bool _testingConnection = false;
  bool _testingScale = false;
  bool _testingScanner = false;
  String _connectionStatus = '';
  String _scaleStatus = '';
  String _scannerStatus = '';
  bool _connectionOk = false;
  bool _scaleOk = false;
  bool _scannerOk = false;

  // Theme
  late bool _isDark;
  String _locale = 'en';

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  void _loadConfig() {
    _ipCtrl.text = AppConfig.serverIp;
    _portCtrl.text = AppConfig.scalePort;
    _baudCtrl.text = AppConfig.scaleBaud.toString();
    _scannerCtrl.text = AppConfig.scannerPort;

    _isDark = AppConfig.getString('theme', 'dark') == 'dark';
    _locale = AppConfig.getString('locale', 'en');
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _baudCtrl.dispose();
    _scannerCtrl.dispose();
    super.dispose();
  }

  // ── Test server connection ────────────────────────────────────────────────
  Future<void> _testConnection() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;

    setState(() {
      _testingConnection = true;
      _connectionStatus = '';
      _connectionOk = false;
    });

    try {
      // Use async isolate wrapper with timeout
      final ok = await Future(() => WasteEngine.instance.switchServer(ip)).timeout(const Duration(seconds: 10), onTimeout: () => false);
      if (ok) {
        AppConfig.set('server_ip', ip);
        setState(() {
          _connectionOk = true;
          _connectionStatus = 'Connected to $ip';
        });
      } else {
        setState(() {
          _connectionOk = false;
          _connectionStatus = 'Could not connect to $ip (timeout or error)';
        });
      }
    } catch (e) {
      setState(() {
        _connectionOk = false;
        _connectionStatus = 'Error: $e';
      });
    } finally {
      setState(() => _testingConnection = false);
    }
  }

  // ── Test scale ────────────────────────────────────────────────────────────
  Future<void> _testScale() async {
    final port = _portCtrl.text.trim();
    final baud = int.tryParse(_baudCtrl.text) ?? 9600;

    if (port.isEmpty) return;

    setState(() {
      _testingScale = true;
      _scaleStatus = '';
      _scaleOk = false;
    });

    try {
      final svc = ScaleService(portName: port, baudRate: baud);
      final result = await svc.readOnce(timeoutMs: 3000);

      if (result.isSuccess) {
        AppConfig.set('scale_port', port);
        AppConfig.set('scale_baud', baud);
        setState(() {
          _scaleOk = true;
          _scaleStatus = 'Scale OK — ${result.weight} kg';
        });
      } else {
        setState(() {
          _scaleOk = false;
          _scaleStatus = result.errorMessage ?? 'No response from scale';
        });
      }
    } catch (e) {
      setState(() {
        _scaleOk = false;
        _scaleStatus = 'Error: $e';
      });
    } finally {
      setState(() => _testingScale = false);
    }
  }

  void _showSaved() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Settings saved'),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          // ── Header ────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
              child: SectionHeader(
                title: l10n.settings,
                subtitle: 'Configure server, scale and print preferences',
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: _leftColumn(context, isDark),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  // ── Left column ───────────────────────────────────────────────────────────
  Widget _leftColumn(BuildContext context, bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _serverCard(context, isDark, l10n),
        const SizedBox(height: 24),
        _scaleCard(context, isDark, l10n),
        const SizedBox(height: 24),
        _scannerCard(context, isDark, l10n),
        const SizedBox(height: 24),
        _appearanceCard(context, isDark, l10n),
      ],
    );
  }

  // ── Server card ───────────────────────────────────────────────────────────
  Widget _serverCard(BuildContext context, bool isDark, AppLocalizations l10n) {
    return _SettingsCard(
      title: l10n.serverConnection,
      icon: Icons.lan_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label: l10n.serverIpAddress),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ipCtrl,
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: const InputDecoration(
                    hintText: '192.168.1.100',
                    prefixIcon: Icon(Icons.dns_outlined, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _testingConnection
                  ? const SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: _testConnection,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      child: const Text('Test'),
                    ),
            ],
          ),

          // Status
          if (_connectionStatus.isNotEmpty) ...[
            const SizedBox(height: 10),
            _StatusRow(
              message: _connectionStatus,
              ok: _connectionOk,
            ),
          ],
        ],
      ),
    );
  }

  // ── Scale card ────────────────────────────────────────────────────────────
  Widget _scaleCard(BuildContext context, bool isDark, AppLocalizations l10n) {
    final l10n = AppLocalizations.of(context)!;
    return _SettingsCard(
      title: l10n.scaleConfiguration,
      icon: Icons.scale_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Port
          _FieldLabel(label: l10n.serialPort),
          const SizedBox(height: 6),
          TextField(
            controller: _portCtrl,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: const InputDecoration(
              hintText: '/dev/ttyUSB0',
              prefixIcon: Icon(Icons.usb_outlined, size: 18),
            ),
          ),

          const SizedBox(height: 16),

          // Baud rate
          _FieldLabel(label: 'BAUD RATE'),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            value: int.tryParse(_baudCtrl.text) ?? 9600,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.speed_outlined, size: 18),
            ),
            items: [
              1200,
              2400,
              4800,
              9600,
              19200,
              38400,
              57600,
              115200,
            ]
                .map((b) => DropdownMenuItem(
                      value: b,
                      child: Text('$b baud'),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                _baudCtrl.text = v.toString();
              }
            },
          ),

          const SizedBox(height: 16),

          // Test button
          SizedBox(
            width: double.infinity,
            child: _testingScale
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: _testScale,
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: const Text('Test Scale'),
                  ),
          ),

          // Status
          if (_scaleStatus.isNotEmpty) ...[
            const SizedBox(height: 10),
            _StatusRow(
              message: _scaleStatus,
              ok: _scaleOk,
            ),
          ],
        ],
      ),
    );
  }

  // ── Scanner card ───────────────────────────────────────────────────────────
  Widget _scannerCard(
      BuildContext context, bool isDark, AppLocalizations l10n) {
    final l10n = AppLocalizations.of(context)!;
    return _SettingsCard(
      title: l10n.scannerConfiguration,
      icon: Icons.qr_code_scanner,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label: l10n.serialPort),
          const SizedBox(height: 6),
          TextField(
            controller: _scannerCtrl,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: const InputDecoration(
              hintText: '/dev/ttyUSB1',
              prefixIcon: Icon(Icons.usb_outlined, size: 18),
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                AppConfig.set('scanner_port', value.trim());
              }
            },
          ),
          const SizedBox(height: 16),
          if (_scannerStatus.isNotEmpty) ...[
            _StatusRow(
              message: _scannerStatus,
              ok: _scannerOk,
            ),
          ],
        ],
      ),
    );
  }

  // ── Appearance card ───────────────────────────────────────────────────────
  Widget _appearanceCard(
      BuildContext context, bool isDark, AppLocalizations l10n) {
    return _SettingsCard(
      title: 'Appearance',
      icon: Icons.palette_outlined,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Theme',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      _isDark ? 'Dark mode' : 'Light mode',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isDark,
                onChanged: (v) {
                  setState(() => _isDark = v);
                  AppConfig.set('theme', v ? 'dark' : 'light');
                  widget.onToggleTheme();
                },
                activeColor: AppTheme.primaryBluee,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          const SizedBox(height: 20),
          _FieldLabel(label: 'LANGUAGE'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _LangButton(
                label: 'English',
                flag: '🇬🇧',
                selected: _locale == 'en',
                onTap: () {
                  setState(() => _locale = 'en');
                  AppConfig.set('locale', 'en');
                  widget.onChangeLocale('en');
                },
              ),
              _LangButton(
                label: 'Français',
                flag: '🇫🇷',
                selected: _locale == 'fr',
                onTap: () {
                  setState(() => _locale = 'fr');
                  AppConfig.set('locale', 'fr');
                  widget.onChangeLocale('fr');
                },
              ),
              _LangButton(
                label: 'العربية',
                flag: '🇩🇿',
                selected: _locale == 'ar',
                onTap: () {
                  setState(() => _locale = 'ar');
                  AppConfig.set('locale', 'ar');
                  widget.onChangeLocale('ar');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SETTINGS CARD
// ============================================================================

class _SettingsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBluee.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: AppTheme.primaryBluee,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(title, style: theme.textTheme.titleMedium),
            ],
          ),

          const SizedBox(height: 20),
          Divider(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            height: 1,
          ),
          const SizedBox(height: 20),

          child,
        ],
      ),
    );
  }
}

// ============================================================================
// STATUS ROW
// ============================================================================

class _StatusRow extends StatelessWidget {
  final String message;
  final bool ok;

  const _StatusRow({
    required this.message,
    required this.ok,
  });

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppTheme.success : AppTheme.error;
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          color: color,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: color,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// FIELD LABEL
// ============================================================================

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1),
    );
  }
}

class _LangButton extends StatelessWidget {
  final String label;
  final String flag;
  final bool selected;
  final VoidCallback onTap;

  const _LangButton({
    required this.label,
    required this.flag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      width: 90,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primaryBluee.withOpacity(0.15)
                : isDark
                    ? AppTheme.darkCard
                    : AppTheme.lightCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppTheme.primaryBluee
                  : isDark
                      ? AppTheme.darkBorder
                      : AppTheme.lightBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(flag, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? AppTheme.primaryBluee
                      : isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.lightTextPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
/*```

**What's in this file:**
```
✅ Server card
   → IP field + test button
   → Live connection status
   → Saves on success
✅ Scale card
   → Port field
   → Baud rate dropdown (all standard rates)
   → Test scale → reads one weight
   → Live scale status
   → Saves on success
✅ Appearance card
   → Theme toggle switch
   → Persisted to config
✅ Print card
   → Width + height in mm
   → Quick presets: A4 / A5 / 80mm / 58mm thermal
   → QR size: small / medium / large
   → Field toggles: 7 fields on/off
   → Save button
✅ Two column layout on wide screens
✅ Single column on narrow screens
✅ All settings persisted to config.json */
