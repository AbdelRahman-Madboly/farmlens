import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/live_data.dart';
import '../providers/connection_provider.dart';
import '../providers/live_provider.dart';
import '../providers/settings_provider.dart';
import '../theme.dart';
import '../utils/formatters.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _lastAlertCycleId = '';
  LiveProvider? _liveProvider;
  Timer? _startRetryTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _liveProvider = Provider.of<LiveProvider>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startPollingWithRetry();
    });
  }

  /// Tries to start polling. If deviceBaseUrl is still empty (SettingsProvider
  /// not yet loaded), retries every 200ms for up to 5 seconds.
  void _startPollingWithRetry() {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final live = Provider.of<LiveProvider>(context, listen: false);

    if (settings.deviceBaseUrl.isNotEmpty) {
      live.startPolling(settings.api());
      return;
    }

    // URL not ready yet - retry
    int attempts = 0;
    _startRetryTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (!mounted) { t.cancel(); return; }
      attempts++;
      final s = Provider.of<SettingsProvider>(context, listen: false);
      if (s.deviceBaseUrl.isNotEmpty) {
        t.cancel();
        Provider.of<LiveProvider>(context, listen: false)
            .startPolling(s.api());
      } else if (attempts >= 25) {
        // 5 seconds passed, still empty - give up
        t.cancel();
      }
    });
  }

  void _manualRefresh() {
    _startRetryTimer?.cancel();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final live = Provider.of<LiveProvider>(context, listen: false);
    if (settings.deviceBaseUrl.isNotEmpty) {
      live.stopPolling();
      live.startPolling(settings.api());
    }
  }

  void _checkAndShowAlertSnackBar(LiveData data) {
    if (isNewAlert(data, _lastAlertCycleId)) {
      _lastAlertCycleId = data.cycleId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Alert: ${formatDetectionClass(data.detectionClass)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: Colors.white),
            ),
            backgroundColor: FarmLensColors.alert,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 120,
              left: 16,
              right: 16,
            ),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _startRetryTimer?.cancel();
    _liveProvider?.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<LiveProvider, ConnectionProvider>(
      builder: (context, liveProvider, connProvider, _) {
        final data = liveProvider.latest;
        final isEmpty = data.cycleId.isEmpty;
        final isError = connProvider.state == DeviceConnectionState.error;

        _checkAndShowAlertSnackBar(data);

        return Scaffold(
          backgroundColor: FarmLensColors.background,
          appBar: AppBar(
            backgroundColor: FarmLensColors.background,
            elevation: 0,
            title: Row(
              children: [
                const Icon(Icons.eco_rounded,
                    color: FarmLensColors.primary, size: 20),
                const SizedBox(width: 8),
                const Text('FarmLens',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: FarmLensColors.primary)),
                const SizedBox(width: 8),
                _NodeStatusDot(
                    isConnected: connProvider.isConnected && !isError),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh,
                    color: FarmLensColors.textSecondary),
                onPressed: _manualRefresh,
                tooltip: 'Refresh',
              ),
            ],
          ),
          body: isError
              ? _ErrorState(onRetry: _manualRefresh)
              : isEmpty
                  ? const _LoadingState()
                  : _DashboardBody(data: data),
        );
      },
    );
  }
}

// ─── Loading ──────────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: FarmLensColors.primary),
          SizedBox(height: 16),
          Text('Connecting to node…',
              style: TextStyle(
                  color: FarmLensColors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }
}

// ─── Error ────────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 48, color: FarmLensColors.textSecondary),
          const SizedBox(height: 12),
          const Text('Node offline',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: FarmLensColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('Could not reach the ESP32 node',
              style: TextStyle(
                  fontSize: 13, color: FarmLensColors.textSecondary)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: FarmLensColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Node status dot ──────────────────────────────────────────────────────────

class _NodeStatusDot extends StatelessWidget {
  final bool isConnected;
  const _NodeStatusDot({required this.isConnected});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isConnected ? FarmLensColors.primary : FarmLensColors.alert,
      ),
    );
  }
}

// ─── Dashboard body ───────────────────────────────────────────────────────────

class _DashboardBody extends StatelessWidget {
  final LiveData data;
  const _DashboardBody({required this.data});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.alert) ...[
            _AlertBanner(detectionClass: data.detectionClass),
            const SizedBox(height: 12),
          ],
          _DetectionCard(data: data),
          const SizedBox(height: 12),
          _CombinedScoreCard(data: data),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _SensorCard(
                label: 'Soil Moisture',
                value: data.moisturePct,
                unit: '%',
                icon: Icons.water_drop_outlined,
                stress: data.moistureStress,
                activeColor: FarmLensColors.primary,
              )),
              const SizedBox(width: 12),
              Expanded(child: _SensorCard(
                label: 'Water Level',
                value: data.waterPct,
                unit: '%',
                icon: Icons.waves_outlined,
                stress: data.waterStress,
                activeColor: FarmLensColors.amber,
              )),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _ScoreChip(
                label: 'Cv  (AI conf.)',
                value: data.cv,
                color: FarmLensColors.primary,
              )),
              const SizedBox(width: 8),
              Expanded(child: _ScoreChip(
                label: 'Cs  (stress)',
                value: data.cs,
                color: FarmLensColors.alert,
              )),
            ],
          ),
          const SizedBox(height: 12),
          _CycleInfoCard(data: data),
        ],
      ),
    );
  }
}

// ─── Alert Banner ─────────────────────────────────────────────────────────────

class _AlertBanner extends StatelessWidget {
  final String detectionClass;
  const _AlertBanner({required this.detectionClass});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: FarmLensColors.alert.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FarmLensColors.alert.withAlpha(80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: FarmLensColors.alert, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '⚠  Alert: ${formatDetectionClass(detectionClass)}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: FarmLensColors.alert),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Detection Card ───────────────────────────────────────────────────────────

class _DetectionCard extends StatelessWidget {
  final LiveData data;
  const _DetectionCard({required this.data});
  @override
  Widget build(BuildContext context) {
    final healthy = data.detectionClass.toLowerCase().contains('healthy');
    final color = healthy ? FarmLensColors.primary : FarmLensColors.alert;
    return _Card(
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              healthy ? Icons.eco_rounded : Icons.bug_report_outlined,
              color: color, size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI Detection',
                    style: TextStyle(
                        fontSize: 11, color: FarmLensColors.textSecondary)),
                const SizedBox(height: 4),
                Text(formatDetectionClass(data.detectionClass),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ],
            ),
          ),
          Text('${(data.detectionConf * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }
}

// ─── Combined Score Card ──────────────────────────────────────────────────────

class _CombinedScoreCard extends StatelessWidget {
  final LiveData data;
  const _CombinedScoreCard({required this.data});
  @override
  Widget build(BuildContext context) {
    final color = ccombinedColor(data.ccombined);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Combined Score  (Ccombined)',
                  style: TextStyle(
                      fontSize: 11, color: FarmLensColors.textSecondary)),
              const Spacer(),
              if (data.alert)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: FarmLensColors.alert,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('ALERT',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: data.ccombined.clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: FarmLensColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(data.ccombined.toStringAsFixed(3),
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Sensor Card ──────────────────────────────────────────────────────────────

class _SensorCard extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final IconData icon;
  final int stress;
  final Color activeColor;
  const _SensorCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.stress,
    required this.activeColor,
  });
  @override
  Widget build(BuildContext context) {
    final isStress = stress == 1;
    final displayColor = isStress ? FarmLensColors.alert : activeColor;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: displayColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        color: FarmLensColors.textSecondary)),
              ),
              if (isStress)
                const Icon(Icons.warning_amber_rounded,
                    size: 14, color: FarmLensColors.alert),
            ],
          ),
          const SizedBox(height: 10),
          _GaugeArc(value: value / 100.0, color: displayColor),
          const SizedBox(height: 6),
          Center(
            child: Text('${value.toStringAsFixed(1)}$unit',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isStress
                        ? FarmLensColors.alert
                        : FarmLensColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

// ─── Gauge Arc ────────────────────────────────────────────────────────────────

class _GaugeArc extends StatelessWidget {
  final double value;
  final Color color;
  const _GaugeArc({required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: CustomPaint(
        painter: _GaugePainter(value: value.clamp(0.0, 1.0), color: color),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;
  const _GaugePainter({required this.value, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.9;
    final r = math.min(cx, cy) * 0.9;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      math.pi, math.pi, false,
      Paint()
        ..color = FarmLensColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      math.pi, math.pi * value, false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
  }
  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color;
}

// ─── Score Chip ───────────────────────────────────────────────────────────────

class _ScoreChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _ScoreChip(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          Container(
            width: 4, height: 32,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10, color: FarmLensColors.textSecondary)),
              const SizedBox(height: 2),
              Text(value.toStringAsFixed(3),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Cycle Info Card ──────────────────────────────────────────────────────────

class _CycleInfoCard extends StatelessWidget {
  final LiveData data;
  const _CycleInfoCard({required this.data});
  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cycle Info',
              style: TextStyle(
                  fontSize: 11, color: FarmLensColors.textSecondary)),
          const SizedBox(height: 8),
          _InfoRow(label: 'Cycle ID', value: data.cycleId),
          _InfoRow(label: 'Node', value: data.nodeId),
          _InfoRow(label: 'Uptime', value: timeAgo(data.ts)),
        ],
      ),
    );
  }
}

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

// ─── Card wrapper ─────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FarmLensColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FarmLensColors.border, width: 0.5),
      ),
      child: child,
    );
  }
}