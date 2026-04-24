import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'data/local/database_helper.dart';
import 'data/remote/api_client.dart';
import 'services/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Immersive mode for POS — no status bar distractions
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Color(0xFF0B0B0B),
    ),
  );

  // Init secure storage base URL cache (sync, avoids per-request async)
  await ApiClient.initBaseUrl();

  // Run atomic SharedPreferences → SQLite migration (no-op if already done)
  await DatabaseHelper.instance.migrateFromSharedPreferences();

  final router = await AppRouter.create();

  // Register 401 logout callback — navigates to '/' without BuildContext
  setGlobalLogoutCallback(() {
    router.go('/');
  });

  runApp(
    ProviderScope(
      child: IllumePosApp(router: router),
    ),
  );
}

class IllumePosApp extends ConsumerStatefulWidget {
  final GoRouter router;
  const IllumePosApp({super.key, required this.router});

  @override
  ConsumerState<IllumePosApp> createState() => _IllumePosAppState();
}

class _IllumePosAppState extends ConsumerState<IllumePosApp> {
  @override
  void initState() {
    super.initState();
    // Kick off background sync watcher (SyncNotifier registers its own
    // lifecycle observer internally, so this just ensures the provider is alive)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Illume POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: widget.router,
    );
  }
}
