import 'dart:convert';

import 'package:farmlens/providers/connection_provider.dart';
import 'package:farmlens/providers/live_provider.dart';
import 'package:farmlens/providers/log_provider.dart';
import 'package:farmlens/providers/settings_provider.dart';
import 'package:farmlens/screens/alerts_screen.dart';
import 'package:farmlens/screens/connection_screen.dart';
import 'package:farmlens/screens/log_detail_screen.dart';
import 'package:farmlens/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_provider_test.dart' show live;

/// Pumps [home] at '/' inside the app's providers and a router that also
/// knows '/main' and '/connect', so screens that navigate can be tested.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget home, {
  LiveProvider? liveProvider,
  ConnectionProvider? connection,
  SettingsProvider? settings,
}) async {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => home),
    GoRoute(
        path: '/main',
        builder: (_, __) => const Scaffold(body: Text('MAIN SCREEN'))),
    GoRoute(
        path: '/connect',
        builder: (_, __) => const Scaffold(body: Text('CONNECT SCREEN'))),
  ]);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => settings ?? SettingsProvider()),
      ChangeNotifierProvider(
          create: (_) => connection ?? ConnectionProvider()),
      ChangeNotifierProvider(create: (_) => liveProvider ?? LiveProvider()),
      ChangeNotifierProvider(create: (_) => LogProvider()),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('settings has no dark mode or notification toggles',
      (tester) async {
    await pumpScreen(tester, const SettingsScreen());
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Dark mode'), findsNothing);
    expect(find.text('Push notifications'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Visual weight (w1)'), findsOneWidget);
  });

  testWidgets('settings about section credits VINEX only', (tester) async {
    await pumpScreen(tester, const SettingsScreen());
    await tester.scrollUntilVisible(find.byKey(const Key('about-version')), 200);
    expect(find.text('FarmLens 0.1.0'), findsOneWidget);
    expect(find.text('VINEX'), findsOneWidget);
    expect(find.textContaining('University'), findsNothing);
  });

  testWidgets('alerts screen lists alerts and clears the badge',
      (tester) async {
    final lp = LiveProvider()
      ..handleLiveData(live(id: 'FL-001-a', alert: true))
      ..handleLiveData(live(id: 'FL-001-b', alert: true));
    expect(lp.unreadAlertCount, 2);
    await pumpScreen(tester, const AlertsScreen(), liveProvider: lp);
    expect(find.text('Alert Feed'), findsOneWidget);
    expect(find.text('Tomato: Late Blight'), findsNWidgets(2));
    expect(lp.unreadAlertCount, 0);
  });

  testWidgets('alerts screen empty state', (tester) async {
    await pumpScreen(tester, const AlertsScreen());
    expect(find.text('Tomato: Late Blight'), findsNothing);
  });

  testWidgets('log detail finds an alert that is not in the log yet',
      (tester) async {
    final lp = LiveProvider()
      ..handleLiveData(live(id: 'FL-001-a', alert: true));
    await pumpScreen(tester, const LogDetailScreen(cycleId: 'FL-001-a'),
        liveProvider: lp);
    expect(find.text('Cycle not found'), findsNothing);
    expect(find.text('Tomato: Late Blight'), findsWidgets);
  });

  testWidgets('log detail for an unknown id', (tester) async {
    await pumpScreen(tester, const LogDetailScreen(cycleId: 'missing'));
    expect(find.text('Cycle not found'), findsOneWidget);
  });

  testWidgets('connection screen validates the address', (tester) async {
    await pumpScreen(tester, const ConnectionScreen());
    await tester.enterText(find.byType(TextFormField).first, '300.1.1.1');
    await tester.ensureVisible(find.text('Connect →'));
    await tester.tap(find.text('Connect →'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid IPv4 address'), findsOneWidget);
    expect(find.text('MAIN SCREEN'), findsNothing);
  });

  testWidgets('connection screen connects, saves the node and the key',
      (tester) async {
    final client = MockClient((req) async {
      expect(req.url.toString(), 'http://192.0.2.10:8000/api/status');
      return http.Response(
          jsonEncode({'node_id': 'FL-001', 'mode': 'MOCK'}), 200);
    });
    final settings = SettingsProvider();
    await pumpScreen(tester, const ConnectionScreen(),
        connection: ConnectionProvider(client: client), settings: settings);
    await tester.enterText(find.byType(TextFormField).first, '192.0.2.10');
    await tester.enterText(find.byKey(const Key('api-key-field')), 'k-1');
    await tester.ensureVisible(find.text('Connect →'));
    await tester.tap(find.text('Connect →'));
    await tester.pumpAndSettle();
    expect(find.text('MAIN SCREEN'), findsOneWidget);
    expect(settings.deviceBaseUrl, 'http://192.0.2.10:8000');
    expect(settings.apiKey, 'k-1');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('device_base_url'), 'http://192.0.2.10:8000');
  });

  testWidgets('connection screen shows an error when the node is down',
      (tester) async {
    final client = MockClient((_) async => http.Response('down', 503));
    await pumpScreen(tester, const ConnectionScreen(),
        connection: ConnectionProvider(client: client));
    await tester.enterText(find.byType(TextFormField).first, '192.0.2.10');
    await tester.ensureVisible(find.text('Connect →'));
    await tester.tap(find.text('Connect →'));
    await tester.pumpAndSettle();
    expect(find.text('MAIN SCREEN'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
