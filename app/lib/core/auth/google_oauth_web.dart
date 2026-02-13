import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> signInWithGoogleUnified() async {
  // Web: retourne sur /auth/callback (ta page AuthCallbackPage)
  final redirectTo = '${Uri.base.origin}/auth/callback';

  await Supabase.instance.client.auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: redirectTo,
  );
}
