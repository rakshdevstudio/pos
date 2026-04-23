import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../presentation/auth/login_screen.dart';
import '../../presentation/schools/school_selection_screen.dart';
import '../../presentation/pos/pos_screen.dart';
import '../../presentation/checkout/checkout_screen.dart';

class AppRouter {
  static Future<GoRouter> create() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final hasSchool = prefs.containsKey('selected_school_id');

    String initialLocation = '/';
    if (token != null && hasSchool) {
      initialLocation = '/pos';
    } else if (token != null) {
      initialLocation = '/schools';
    }

    return GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const LoginScreen(),
        ),
        GoRoute(
          path: '/schools',
          builder: (_, __) => const SchoolSelectionScreen(),
        ),
        GoRoute(
          path: '/pos',
          builder: (_, __) => const PosScreen(),
        ),
        GoRoute(
          path: '/checkout',
          builder: (_, __) => const CheckoutScreen(),
        ),
      ],
    );
  }
}
