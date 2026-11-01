import 'package:go_router/go_router.dart';
import 'screens/splash_screen.dart';
import 'screens/connection_screen.dart';
import 'screens/main_shell.dart';
import 'screens/log_detail_screen.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/connect',
        builder: (context, state) => const ConnectionScreen(),
      ),
      GoRoute(
        path: '/main',
        builder: (context, state) => const MainShell(),
      ),
      GoRoute(
        path: '/log/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return LogDetailScreen(cycleId: id);
        },
      ),
    ],
  );
}