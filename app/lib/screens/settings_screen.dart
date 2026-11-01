import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/fusion_settings.dart';
import '../providers/connection_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _w1 = 0.6;
  double _theta = 0.5;
  String _cropType = 'Tomato';

  static const List<String> _crops = [
    'Tomato',
    'Strawberry',
    'Mango',
    'Pepper',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    final fs =
        Provider.of<SettingsProvider>(context, listen: false).fusionSettings;
    _w1 = fs.w1;
    _theta = fs.theta;
    _cropType = _capitalize(fs.cropType);
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  ApiService _api(BuildContext context) =>
      Provider.of<SettingsProvider>(context, listen: false).api();

  Future<void> _postSettings() async {
    final settings =
        Provider.of<SettingsProvider>(context, listen: false);
    final fs = FusionSettings(
      w1: _w1,
      w2: double.parse((1.0 - _w1).toStringAsFixed(2)),
      theta: _theta,
      cropType: _cropType.toLowerCase(),
    );
    final ok = await _api(context).postSettings(fs);
    if (!mounted) return;
    if (ok) {
      settings.updateFusionSettings(fs);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Settings saved'),
          backgroundColor: FarmLensColors.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to save: node unreachable or API key rejected'),
          backgroundColor: FarmLensColors.alert,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _testConnection() async {
    final status = await _api(context).getStatus();
    if (!mounted) return;
    if (status != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to node ${status.nodeId}'),
          backgroundColor: FarmLensColors.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Node not responding'),
          backgroundColor: FarmLensColors.alert,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final conn = Provider.of<ConnectionProvider>(context);

    return Scaffold(
      backgroundColor: FarmLensColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── App Bar ──────────────────────────────────
            Container(
              color: FarmLensColors.card,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: FarmLensColors.textPrimary,
                  ),
                ),
              ),
            ),
            const Divider(
                height: 0.5, thickness: 0.5, color: FarmLensColors.border),

            // ── Scrollable body ──────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Section 1: Node Connection ───────
                    const _SectionHeader('Node Connection'),
                    _SettingsCard(
                      children: [
                        // Device URL row
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Device',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: FarmLensColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    settings.deviceBaseUrl.isEmpty
                                        ? 'Not configured'
                                        : settings.deviceBaseUrl,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: FarmLensColors.textPrimary,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => context.go('/connect'),
                              style: TextButton.styleFrom(
                                foregroundColor: FarmLensColors.primary,
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Change',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const _CardDivider(),
                        // Connection status row
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: conn.isConnected
                                    ? FarmLensColors.primary
                                    : FarmLensColors.alert,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              conn.isConnected
                                  ? 'Connected'
                                  : 'Not connected',
                              style: const TextStyle(
                                fontSize: 13,
                                color: FarmLensColors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: _testConnection,
                              style: TextButton.styleFrom(
                                foregroundColor: FarmLensColors.primary,
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Test',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ── Section 2: Fusion Weights ─────────
                    const _SectionHeader('Fusion Weights'),
                    _SettingsCard(
                      children: [
                        // w1 slider
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Visual weight (w1)',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: FarmLensColors.textPrimary),
                            ),
                            Text(
                              _w1.toStringAsFixed(2),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: FarmLensColors.primary,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _w1,
                          min: 0.0,
                          max: 1.0,
                          divisions: 20,
                          activeColor: FarmLensColors.primary,
                          inactiveColor: FarmLensColors.border,
                          onChanged: (v) =>
                              setState(() => _w1 = v),
                          onChangeEnd: (_) => _postSettings(),
                        ),
                        Text(
                          'Soil weight (w2): ${(1.0 - _w1).toStringAsFixed(2)} (1 - w1)',
                          style: const TextStyle(
                            fontSize: 11,
                            color: FarmLensColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // theta slider
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Alert threshold (θ)',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: FarmLensColors.textPrimary),
                            ),
                            Text(
                              _theta.toStringAsFixed(2),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: FarmLensColors.primary,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _theta,
                          min: 0.1,
                          max: 0.9,
                          divisions: 16,
                          activeColor: FarmLensColors.primary,
                          inactiveColor: FarmLensColors.border,
                          onChanged: (v) =>
                              setState(() => _theta = v),
                          onChangeEnd: (_) => _postSettings(),
                        ),
                        Text(
                          'Alert fires when Ccombined > ${_theta.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: FarmLensColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Crop type
                        const Text(
                          'Crop Type',
                          style: TextStyle(
                            fontSize: 12,
                            color: FarmLensColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _crops.map((crop) {
                            final selected = _cropType == crop;
                            return GestureDetector(
                              onTap: () {
                                setState(() => _cropType = crop);
                                _postSettings();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? FarmLensColors.primary
                                      : Colors.transparent,
                                  borderRadius:
                                      BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selected
                                        ? FarmLensColors.primary
                                        : FarmLensColors.textSecondary
                                            .withAlpha(76),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  crop,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? Colors.white
                                        : FarmLensColors.textSecondary,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ── Section 3: About ──────────────────
                    const _SectionHeader('About'),
                    const _SettingsCard(
                      children: [
                        Text(
                          'FarmLens 0.1.0',
                          key: Key('about-version'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: FarmLensColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Crop health monitoring prototype. Data shown is '
                          'simulated unless the node reports real sensors '
                          'and a model.',
                          style: TextStyle(
                            fontSize: 12,
                            color: FarmLensColors.textSecondary,
                          ),
                        ),
                        _CardDivider(),
                        Text(
                          'VINEX',
                          style: TextStyle(
                            fontSize: 12,
                            color: FarmLensColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: FarmLensColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: FarmLensColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FarmLensColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Divider(
          height: 0.5, thickness: 0.5, color: FarmLensColors.border),
    );
  }
}