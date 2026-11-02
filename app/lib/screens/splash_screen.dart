import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/connection_provider.dart';
import '../providers/settings_provider.dart';
import '../services/node_discovery.dart';
import '../theme.dart';

/// Finds the node on start: the saved address, farmlens.local, then a scan of
/// the phone's Wi-Fi or hotspot network. The Pi's address on a phone hotspot
/// can change between boots, so a stale saved address is not a dead end.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.discovery});

  /// Injected in tests.
  final NodeDiscovery? discovery;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _message = '';

  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    // Small visual delay so the splash is visible
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    // SettingsProvider.loadFromPrefs() is async; wait (up to 3 s) for it so
    // a saved node address is not missed.
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    int waited = 0;
    while (!settings.isLoaded && waited < 30) {
      await Future.delayed(const Duration(milliseconds: 100));
      waited++;
      if (!mounted) return;
    }

    if (!mounted) return;
    final connection = Provider.of<ConnectionProvider>(context, listen: false);
    final savedHost = Uri.tryParse(settings.deviceBaseUrl)?.host ?? '';
    setState(() => _message = savedHost.isEmpty
        ? 'Looking for your FarmLens node…'
        : 'Connecting to your node…');

    final discovery = widget.discovery ?? NodeDiscovery();
    final nodes = await discovery.scan(
      preferredHosts: [savedHost, FarmLensConstants.defaultHostname],
      stopAtFirst: true,
      onProgress: (_, __) {
        if (mounted && _message != 'Looking for your FarmLens node…') {
          setState(() => _message = 'Looking for your FarmLens node…');
        }
      },
    );
    if (!mounted) return;

    final ok =
        nodes.isNotEmpty && await connection.connect(nodes.first.baseUrl);
    if (ok) await settings.saveDeviceUrl(nodes.first.baseUrl);
    if (!mounted) return;
    context.go(ok ? '/main' : '/connect');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FarmLensColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.eco_rounded,
              size: 72,
              color: FarmLensColors.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'FarmLens',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: FarmLensColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Crop health monitoring prototype',
              style: TextStyle(
                fontSize: 14,
                color: FarmLensColors.textSecondary,
              ),
            ),
            const SizedBox(height: 40),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: FarmLensColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _message,
              key: const Key('splash-message'),
              style: const TextStyle(
                fontSize: 13,
                color: FarmLensColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}