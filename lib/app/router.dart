import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/application/auth_providers.dart';
import '../features/pairing/application/pairing_providers.dart';
import '../features/pairing/presentation/setup_screen.dart';
import '../features/operator/presentation/operator_picker_screen.dart';
import '../features/sales/presentation/sales_screen.dart';

/// Notifies go_router to re-run redirect whenever the paired-device state
/// or the raw Firebase auth state changes. Listening to only one of these
/// leaves a window where redirect bails out on isLoading and never gets
/// re-triggered once the other one resolves.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(pairedDeviceProvider, (_, _) => notifyListeners());
    ref.listen(authStateChangesProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/setup',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final pairedAsync = ref.read(pairedDeviceProvider);
      if (pairedAsync.isLoading) return null;

      final paired = pairedAsync.value;
      final onSetup = state.matchedLocation == '/setup';

      if (paired == null) {
        return onSetup ? null : '/setup';
      }

      final firebaseUserAsync = ref.read(authStateChangesProvider);
      if (firebaseUserAsync.isLoading) return null;

      final onOperators = state.matchedLocation == '/operators';
      final signedIn = firebaseUserAsync.value != null;

      if (!signedIn) {
        return onOperators ? null : '/operators';
      }

      if (onSetup || onOperators) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/setup', builder: (context, state) => const SetupScreen()),
      GoRoute(
        path: '/operators',
        builder: (context, state) => const OperatorPickerScreen(),
      ),
      GoRoute(path: '/home', builder: (context, state) => const SalesScreen()),
    ],
  );
});
