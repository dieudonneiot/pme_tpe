import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'core/env.dart';
import 'core/router.dart';
import 'core/notifications/push_service.dart';
import 'features/cart/cart_scope.dart';
import 'features/cart/cart_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Env.validate();

  await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const App());

  // Initialize notifications after the first frame so UI isn't blocked.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    NotificationService.init()
        .then((_) => NotificationService.requestPermissionAndSyncToken())
        .catchError((e, st) {
      debugPrint('NotificationService initialization failed: $e');
      debugPrint('$st');
    });
  });
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final CartService _cart = CartService();

  @override
  void dispose() {
    _cart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seed = const Color(0xFF4F46E5); // indigo premium

    return CartScope(
      cart: _cart,
      child: MaterialApp.router(
        title: 'PME/TPE',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.light,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: seed,
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF7F7FB),
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          cardTheme: CardThemeData(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: seed,
          brightness: Brightness.dark,
        ),
        routerConfig: appRouter,
      ),
    );
  }
}
