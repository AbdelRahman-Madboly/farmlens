import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
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

    if (settings.deviceBaseUrl.isNotEmpty) {
      // Previously saved URL found - go straight to dashboard
      context.go('/main');
    } else {
      // No saved URL - go to connection screen
      context.go('/connect');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: FarmLensColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.eco_rounded,
              size: 72,
              color: FarmLensColors.primary,
            ),
            SizedBox(height: 16),
            Text(
              'FarmLens',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: FarmLensColors.primary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Crop health monitoring prototype',
              style: TextStyle(
                fontSize: 14,
                color: FarmLensColors.textSecondary,
              ),
            ),
            SizedBox(height: 40),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: FarmLensColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}