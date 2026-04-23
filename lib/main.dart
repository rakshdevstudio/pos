import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'services/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode for standard phones
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Immersive mode for POS — no status bar distractions
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Color(0xFF0B0B0B),
    ),
  );

  final router = await AppRouter.create();

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
    // Kick off background sync watcher
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
