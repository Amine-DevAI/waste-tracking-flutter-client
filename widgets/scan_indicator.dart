import 'package:flutter/material.dart';
import 'package:waste_tracking/theme/app_theme.dart';

class ScanIndicator extends StatefulWidget {
  final bool isScanning;
  final String? message;

  const ScanIndicator({
    super.key,
    this.isScanning = true,
    this.message,
  });

  @override
  State<ScanIndicator> createState() => _ScanIndicatorState();
}

class _ScanIndicatorState extends State<ScanIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FadeTransition(
      opacity: _pulse,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isScanning ? AppTheme.primaryBluee : AppTheme.success,
              boxShadow: [
                BoxShadow(
                  color: (widget.isScanning
                          ? AppTheme.primaryBluee
                          : AppTheme.success)
                      .withOpacity(0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            widget.message ?? 'Ready for scan...',
            style: TextStyle(
              color: widget.isScanning ? AppTheme.primaryBluee : AppTheme.success,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class ScanReadyIndicator extends StatelessWidget {
  final String label;

  const ScanReadyIndicator({
    super.key,
    this.label = 'Scan barcode',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primaryBluee.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.primaryBluee.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.qr_code_scanner,
            color: AppTheme.primaryBluee,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.primaryBluee,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.success,
            ),
          ),
        ],
      ),
    );
  }
}
