import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> signInWithGoogleImpl() async {
  final sb = Supabase.instance.client;

  // Route web de callback (doit exister dans ton router)
  final redirectTo = '${Uri.base.origin}/auth/callback';

  await sb.auth.signInWithOAuth(OAuthProvider.google, redirectTo: redirectTo);
}
