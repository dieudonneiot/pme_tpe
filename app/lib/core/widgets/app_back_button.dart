import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Back button that works on desktop too (where there is no system back button).
///
/// - If the current route can pop: pops.
/// - Otherwise: navigates to a safe fallback route.
class AppBackButton extends StatelessWidget {
  final String? fallbackPath;

  const AppBackButton({super.key, this.fallbackPath});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Retour',
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        if (context.canPop()) {
          context.pop();
          return;
        }

        final loggedIn = Supabase.instance.client.auth.currentSession != null;
        final dest = fallbackPath ?? (loggedIn ? '/home' : '/');
        context.go(dest);
      },
    );
  }
}

