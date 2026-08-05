import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math' as math;

import 'package:waste_tracking/theme/app_theme.dart';
import 'package:waste_tracking/config/app_config.dart';
import 'package:waste_tracking/ffi/engine.dart';
import 'package:waste_tracking/ffi/services/auth_service.dart';
import 'package:waste_tracking/l10n/app_localizations.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _ipCtrl   = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool   _isLoading    = false;
  bool   _showPassword = false;
  String _error        = '';

  @override
  void initState() {
    super.initState();
    _ipCtrl.text = AppConfig.serverIp;
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final ip   = _ipCtrl.text.trim();
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;

    if (ip.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please fill all fields');
      return;
    }

    setState(() { _isLoading = true; _error = ''; });

    // ✅ THE KEY FIX: wait until Flutter fully paints & commits the spinner
    // frame to the screen BEFORE running any blocking FFI code.
    // Future(() => ...) alone doesn't guarantee a frame is rendered first —
    // the event loop may fire the callback before the GPU commits the frame.
    await WidgetsBinding.instance.endOfFrame;

     try {
      final connected = await Future(() => WasteEngine.instance.switchServer(ip));
       if (!connected) {
         setState(() => _error = 'Cannot reach server at $ip');
         return;
       }
      AppConfig.set('server_ip', ip);

      // ✅ login() now throws WasteEngineException with the engine's own message
      await AuthService.instance.login(user, pass);

      if (mounted) Navigator.pushReplacementNamed(context, '/app');

    } on WasteEngineException catch (e) {
      // ✅ Engine already knows exactly what went wrong — show it directly
      setState(() => _error = e.toString());
    } catch (e) {
      setState(() => _error = 'System error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n   = AppLocalizations.of(context)!;

    return Scaffold(
      body: Row(
        children: [
          Expanded(
            flex: 5,
            child: _LeftPanel(isDark: isDark),
          ),
          Expanded(
            flex: 4,
            child: _RightPanel(
              isDark:       isDark,
              l10n:         l10n,
              ipCtrl:       _ipCtrl,
              userCtrl:     _userCtrl,
              passCtrl:     _passCtrl,
              isLoading:    _isLoading,
              showPassword: _showPassword,
              error:        _error,
              onTogglePass: () => setState(() => _showPassword = !_showPassword),
              onLogin:      _handleLogin,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// LEFT PANEL
// ============================================================================

class _LeftPanel extends StatelessWidget {
  final bool isDark;
  const _LeftPanel({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? AppTheme.accentCyan : AppTheme.primaryBlue;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF050A14),
                  const Color(0xFF0A1628),
                  const Color(0xFF0D2040),
                ]
              : [
                  const Color(0xFF0033A0),
                  const Color(0xFF0057C2),
                  const Color(0xFF1976D2),
                ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
              child: CustomPaint(painter: _GeoPainter(accent: accent))),
          Padding(
            padding: const EdgeInsets.all(56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.hub_outlined,
                    color: Colors.white,
                    size: 34,
                  ),
                ),

                const SizedBox(height: 48),

                const Text(
                  'WASTE\nTRACKING',
                  style: TextStyle(
                    color:         Colors.white,
                    fontSize:      52,
                    fontWeight:    FontWeight.w900,
                    letterSpacing: 2,
                    height:        1.1,
                  ),
                ),

                const SizedBox(height: 16),

                Container(
                  width: 64,
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  'Industrial Management\nPlatform',
                  style: TextStyle(
                    color:         Colors.white.withOpacity(0.7),
                    fontSize:      18,
                    fontWeight:    FontWeight.w300,
                    letterSpacing: 0.5,
                    height:        1.5,
                  ),
                ),

                const Spacer(),

                Row(
                  children: [
                    _Stat(value: '100%',   label: 'Traceable'),
                    const SizedBox(width: 40),
                    _Stat(value: 'GMP',    label: 'Compliant'),
                    const SizedBox(width: 40),
                    _Stat(value: 'ALCOA+', label: 'Standard'),
                  ],
                ),

                const SizedBox(height: 40),

                Text(
                  'Waste Management System',
                  style: TextStyle(
                    color:         Colors.white.withOpacity(0.35),
                    fontSize:      11,
                    letterSpacing: 2,
                    fontWeight:    FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color:      Colors.white,
            fontSize:   22,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color:        Colors.white.withOpacity(0.5),
            fontSize:     11,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

class _GeoPainter extends CustomPainter {
  final Color accent;
  const _GeoPainter({required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = Colors.white.withOpacity(0.03)
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawCircle(
        Offset(size.width * 0.8, size.height * 0.2), 200, paint);
    canvas.drawCircle(
        Offset(size.width * 0.1, size.height * 0.8), 150, paint);

    final gridPaint = Paint()
      ..color       = Colors.white.withOpacity(0.04)
      ..strokeWidth = 0.5;

    for (double x = 0; x < size.width; x += 60) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 60) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final accentPaint = Paint()
      ..color       = accent.withOpacity(0.15)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(size.width * 0.6, 0),
      Offset(size.width, size.height * 0.4),
      accentPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.3, size.height),
      Offset(size.width, size.height * 0.1),
      accentPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================================
// RIGHT PANEL
// ============================================================================

class _RightPanel extends StatelessWidget {
  final bool     isDark;
  final AppLocalizations l10n;
  final TextEditingController ipCtrl;
  final TextEditingController userCtrl;
  final TextEditingController passCtrl;
  final bool     isLoading;
  final bool     showPassword;
  final String   error;
  final VoidCallback onTogglePass;
  final VoidCallback onLogin;

  const _RightPanel({
    required this.isDark,
    required this.l10n,
    required this.ipCtrl,
    required this.userCtrl,
    required this.passCtrl,
    required this.isLoading,
    required this.showPassword,
    required this.error,
    required this.onTogglePass,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    final bg     = isDark ? const Color(0xFF0C111C) : Colors.white;
    final accent = isDark ? AppTheme.accentCyan : AppTheme.primaryBlue;

    return Container(
      color: bg,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [

                // ── Welcome ───────────────────────────────────
                Text(
                  'Welcome back',
                  style: TextStyle(
                    color:      isDark ? Colors.white : const Color(0xFF0D1B2A),
                    fontSize:   32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sign in to your workspace',
                  style: TextStyle(
                    color:    isDark ? Colors.white38 : Colors.black38,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 48),

                // ── Hidden IP field ───────────────────────────
                _IpField(controller: ipCtrl, isDark: isDark, accent: accent),

                const SizedBox(height: 20),

                // ── Username ──────────────────────────────────
                _Label(text: l10n.username.toUpperCase(), isDark: isDark),
                const SizedBox(height: 8),
                _Input(
                  controller: userCtrl,
                  hint:       'Enter username',
                  icon:       Icons.person_outline,
                  isDark:     isDark,
                  accent:     accent,
                ),

                const SizedBox(height: 20),

                // ── Password ──────────────────────────────────
                _Label(text: l10n.password.toUpperCase(), isDark: isDark),
                const SizedBox(height: 8),
                _Input(
                  controller: passCtrl,
                  hint:       '••••••••',
                  icon:       Icons.lock_outline,
                  isDark:     isDark,
                  accent:     accent,
                  obscure:    !showPassword,
                  suffix: IconButton(
                    icon: Icon(
                      showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size:  18,
                      color: isDark ? Colors.white30 : Colors.black26,
                    ),
                    onPressed: onTogglePass,
                  ),
                ),

                // ── Error ─────────────────────────────────────
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.error.withOpacity(0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: AppTheme.error, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            error,
                            style: TextStyle(
                                color: AppTheme.error, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 36),

                // ── Button ────────────────────────────────────
                SizedBox(
                  width:  double.infinity,
                  height: 56,
                  child: isLoading
                      ? Center(
                          child: CircularProgressIndicator(color: accent))
                      : ElevatedButton(
                          onPressed: onLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            elevation:       0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'SIGN IN',
                            style: TextStyle(
                              fontSize:      15,
                              fontWeight:    FontWeight.w800,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                ),

                const SizedBox(height: 32),

                // ── Footer ────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: isDark
                            ? Colors.white10
                            : Colors.black.withOpacity(0.08),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'v2.1 · GMP Certified',
                        style: TextStyle(
                          color:         isDark ? Colors.white24 : Colors.black26,
                          fontSize:      10,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: isDark
                            ? Colors.white10
                            : Colors.black.withOpacity(0.08),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// HIDDEN IP FIELD
// Technician taps the subtle icon → field opens → types IP → Enter/unfocus
// → field disappears. IP never displayed. Operator sees nothing.
// ============================================================================

class _IpField extends StatefulWidget {
  final TextEditingController controller;
  final bool  isDark;
  final Color accent;

  const _IpField({
    required this.controller,
    required this.isDark,
    required this.accent,
  });

  @override
  State<_IpField> createState() => _IpFieldState();
}

class _IpFieldState extends State<_IpField> {
  bool _open = false;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _open) {
        setState(() => _open = false);
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child:   SizeTransition(sizeFactor: anim, child: child),
      ),
      child: _open

          // ── Field open ────────────────────────────────────
          ? TextField(
              key:         const ValueKey('open'),
              controller:  widget.controller,
              focusNode:   _focus,
              autofocus:   true,
              style: TextStyle(
                color:    widget.isDark ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
              onSubmitted: (_) => setState(() => _open = false),
              decoration: InputDecoration(
                hintText:  '192.168.1.xxx',
                hintStyle: TextStyle(
                  color: widget.isDark
                      ? Colors.white.withOpacity(0.2)
                      : Colors.black.withOpacity(0.2),
                ),
                prefixIcon: Icon(
                  Icons.lan_outlined,
                  color: widget.isDark ? Colors.white30 : Colors.black26,
                  size:  20,
                ),
                filled:    true,
                fillColor: widget.isDark
                    ? Colors.white.withOpacity(0.05)
                    : const Color(0xFFF8F9FF),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: widget.isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.08),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: widget.accent, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 18),
              ),
            )

          // ── Invisible trigger ─────────────────────────────
          : GestureDetector(
              key:   const ValueKey('closed'),
              onTap: () => setState(() => _open = true),
              child: SizedBox(
                width:  40,
                height: 40,
                child: Icon(
                  Icons.settings_ethernet,
                  size:  16,
                  color: widget.isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.06),
                ),
              ),
            ),
    );
  }
}

// ============================================================================
// SHARED WIDGETS
// ============================================================================

class _Label extends StatelessWidget {
  final String text;
  final bool   isDark;
  const _Label({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color:         isDark ? Colors.white60 : Colors.black54,
        fontSize:      10,
        fontWeight:    FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _Input extends StatelessWidget {
  final TextEditingController  controller;
  final String                 hint;
  final IconData               icon;
  final bool                   isDark;
  final Color                  accent;
  final bool                   obscure;
  final Widget?                suffix;
  final void Function(String)? onSubmitted;

  const _Input({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.isDark,
    required this.accent,
    this.obscure     = false,
    this.suffix,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller:  controller,
      obscureText: obscure,
      onSubmitted: onSubmitted,
      style: TextStyle(
        color:    isDark ? Colors.white : Colors.black87,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        hintText:  hint,
        hintStyle: TextStyle(
          color: isDark
              ? Colors.white.withOpacity(0.2)
              : Colors.black.withOpacity(0.2),
          fontSize: 14,
        ),
        prefixIcon: Icon(icon,
            color: isDark ? Colors.white30 : Colors.black26, size: 20),
        suffixIcon: suffix,
        filled:     true,
        fillColor:  isDark
            ? Colors.white.withOpacity(0.05)
            : const Color(0xFFF8F9FF),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.08),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical:   18,
        ),
      ),
    );
  }
}