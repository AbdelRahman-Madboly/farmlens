import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../theme.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  static const _refreshInterval = Duration(seconds: 5);

  String _refreshKey = '';
  int _countdown = 5;
  bool _lastLoadOk = false;
  DateTime? _lastLoadTime;
  Timer? _refreshTimer;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _doRefresh();

    // Auto-refresh image every 5 seconds
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _doRefresh());

    // Countdown display every second
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _countdown = (_countdown - 1).clamp(0, 5);
      });
    });
  }

  void _doRefresh() {
    if (!mounted) return;
    setState(() {
      _refreshKey = DateTime.now().millisecondsSinceEpoch.toString();
      _countdown  = 5;
    });
  }

  String _snapshotUrl(String baseUrl) =>
      '$baseUrl/api/snapshot?t=$_refreshKey';

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl =
        Provider.of<SettingsProvider>(context, listen: false).deviceBaseUrl;

    return Scaffold(
      backgroundColor: FarmLensColors.background,
      appBar: AppBar(
        backgroundColor: FarmLensColors.background,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.videocam_outlined, color: FarmLensColors.primary, size: 20),
            SizedBox(width: 8),
            Text('Camera Feed',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: FarmLensColors.primary)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: FarmLensColors.textSecondary),
            onPressed: _doRefresh,
            tooltip: 'Refresh now',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status bar ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: FarmLensColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: FarmLensColors.border, width: 0.5),
              ),
              child: Row(
                children: [
                  // Live dot
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _lastLoadOk
                          ? FarmLensColors.primary
                          : FarmLensColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _lastLoadOk ? 'FL-001 · Live view' : 'FL-001 · Connecting…',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: FarmLensColors.textPrimary),
                  ),
                  const Spacer(),
                  Text(
                    'next in ${_countdown}s',
                    style: const TextStyle(
                        fontSize: 12, color: FarmLensColors.textSecondary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Camera image ─────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: baseUrl.isEmpty
                    ? _NoConnection()
                    : Image.network(
                        _snapshotUrl(baseUrl),
                        key: ValueKey(_refreshKey),
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) {
                            // Loaded successfully
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              setState(() {
                                _lastLoadOk   = true;
                                _lastLoadTime = DateTime.now();
                              });
                            });
                            return child;
                          }
                          return Container(
                            color: const Color(0xFFF0F0EC),
                            child: const Center(
                              child: CircularProgressIndicator(
                                  color: FarmLensColors.primary, strokeWidth: 2),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stack) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() => _lastLoadOk = false);
                          });
                          return _NoSignal();
                        },
                      ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Info card ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: FarmLensColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: FarmLensColors.border, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Camera Info',
                      style: TextStyle(
                          fontSize: 11, color: FarmLensColors.textSecondary)),
                  const SizedBox(height: 8),
                  const _InfoRow(label: 'Source',   value: 'Node /api/snapshot'),
                  const _InfoRow(label: 'Mode',     value: 'MOCK: simulated frame and placeholder box, not a detection'),
                  const _InfoRow(label: 'Refresh',  value: 'Every 5 seconds'),
                  _InfoRow(
                    label: 'Last frame',
                    value: _lastLoadTime != null
                        ? '${DateTime.now().difference(_lastLoadTime!).inSeconds}s ago'
                        : '-',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── No connection placeholder ────────────────────────────────────────────────

class _NoConnection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_off, size: 48, color: Colors.white38),
            SizedBox(height: 12),
            Text('Not connected',
                style: TextStyle(fontSize: 14, color: Colors.white54)),
            SizedBox(height: 4),
            Text('Connect to RPi on port 8000',
                style: TextStyle(fontSize: 12, color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}

// ─── No signal placeholder ────────────────────────────────────────────────────

class _NoSignal extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, size: 48, color: Colors.white38),
            SizedBox(height: 12),
            Text('No camera signal',
                style: TextStyle(fontSize: 14, color: Colors.white54)),
            SizedBox(height: 4),
            Text('Check RPi server is running',
                style: TextStyle(fontSize: 12, color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}

// ─── Info row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: FarmLensColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: FarmLensColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}