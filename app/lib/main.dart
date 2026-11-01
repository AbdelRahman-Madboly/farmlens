import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/settings_provider.dart';
import 'providers/connection_provider.dart';
import 'providers/live_provider.dart';
import 'providers/log_provider.dart';
import 'router.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FarmLensApp());
}

class FarmLensApp extends StatefulWidget {
  const FarmLensApp({super.key});

  @override
  State<FarmLensApp> createState() => _FarmLensAppState();
}

class _FarmLensAppState extends State<FarmLensApp> {
  late final GoRouterWrapper _routerWrapper;

  @override
  void initState() {
    super.initState();
    _routerWrapper = GoRouterWrapper();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()..loadFromPrefs()),
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProvider(create: (_) => LiveProvider()),
        ChangeNotifierProvider(create: (_) => LogProvider()),
      ],
      child: MaterialApp.router(
        title: 'FarmLens',
        theme: farmLensTheme(),
        routerConfig: _routerWrapper.router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class GoRouterWrapper {
  late final router = buildRouter();
}