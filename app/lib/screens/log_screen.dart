import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/cycle_log.dart';
import '../providers/log_provider.dart';
import '../providers/settings_provider.dart';
import '../theme.dart';
import '../utils/formatters.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLogs());
  }

  Future<void> _loadLogs() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    if (settings.deviceBaseUrl.isNotEmpty) {
      await logProvider.loadLogs(settings.api());
    }
  }

  Future<void> _exportLogs() async {
    final logProvider = Provider.of<LogProvider>(context, listen: false);
    final cycles = logProvider.cycles;
    if (cycles.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logs to export')),
      );
      return;
    }

    final jsonList = cycles.map((c) => c.toJson()).toList();

    final jsonStr = const JsonEncoder.withIndent('  ').convert(jsonList);
    await Share.share(jsonStr, subject: 'FarmLens cycle log (simulated data)');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Log exported'),
        backgroundColor: FarmLensColors.primary,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LogProvider>(
      builder: (context, logProvider, _) {
        final cycles = logProvider.cycles;
        final alertCount = cycles.where((c) => c.alert).length;
        final lastTs = cycles.isNotEmpty ? cycles.first.ts : 0;

        return Scaffold(
          backgroundColor: FarmLensColors.background,
          body: SafeArea(
            child: Column(
              children: [
                // ── App Bar ───────────────────────────
                Container(
                  color: FarmLensColors.card,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Traceability Log',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: FarmLensColors.textPrimary,
                        ),
                      ),
                      TextButton(
                        onPressed: _exportLogs,
                        style: TextButton.styleFrom(
                          foregroundColor: FarmLensColors.primary,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Export',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: FarmLensColors.border),

                // ── Summary Strip ──────────────────────
                if (!logProvider.isLoading && cycles.isNotEmpty)
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFE1F5EE),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Text(
                      '${cycles.length} cycles · '
                      '$alertCount alert${alertCount == 1 ? '' : 's'} · '
                      'Last ${timeAgo(lastTs)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF0F6E56),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                // ── Body ──────────────────────────────
                Expanded(child: _buildBody(logProvider, cycles)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(LogProvider logProvider, List<CycleLog> cycles) {
    if (logProvider.isLoading) return const _ShimmerList();

    if (logProvider.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: FarmLensColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              logProvider.error!,
              style: const TextStyle(
                  color: FarmLensColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadLogs,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: FarmLensColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      );
    }

    if (cycles.isEmpty) {
      return const Center(
        child: Text(
          'No cycles logged yet\nWaiting for FarmLens node',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: FarmLensColors.textSecondary,
            height: 1.6,
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: FarmLensColors.primary,
      onRefresh: _loadLogs,
      child: ListView.builder(
        itemCount: cycles.length,
        itemBuilder: (context, i) => _LogRow(cycle: cycles[i]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Shimmer Loading
// ─────────────────────────────────────────────

class _ShimmerList extends StatefulWidget {
  const _ShimmerList();

  @override
  State<_ShimmerList> createState() => _ShimmerListState();
}

class _ShimmerListState extends State<_ShimmerList>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) => ListView.builder(
        itemCount: 5,
        itemBuilder: (context, i) => Opacity(
          opacity: _opacity.value,
          child: Container(
            height: 64,
            margin:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: FarmLensColors.border,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Log Row
// ─────────────────────────────────────────────

class _LogRow extends StatelessWidget {
  final CycleLog cycle;
  const _LogRow({required this.cycle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/log/${cycle.id}'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(
            bottom:
                BorderSide(color: FarmLensColors.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // ── Date / Time ──────────────────────────
            SizedBox(
              width: 44,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    formatDate(cycle.ts),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: FarmLensColors.textPrimary,
                    ),
                  ),
                  Text(
                    formatTime(cycle.ts),
                    style: const TextStyle(
                      fontSize: 10,
                      color: FarmLensColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // ── Detection + Cycle ID ─────────────────
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatDetectionClass(cycle.detectionClass),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: FarmLensColors.textPrimary,
                    ),
                  ),
                  Text(
                    cycle.id,
                    style: const TextStyle(
                      fontSize: 10,
                      color: FarmLensColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // ── Score + alert dot ────────────────────
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _ScorePill(value: cycle.ccombined),
                if (cycle.alert) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: FarmLensColors.alert,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Score Pill
// ─────────────────────────────────────────────

class _ScorePill extends StatelessWidget {
  final double value;
  const _ScorePill({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ccombinedColor(value),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        value.toStringAsFixed(2),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}