import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> signInWithGoogleImpl() async {
  final sb = Supabase.instance.client;

  // IMPORTANT: doit matcher ce que tu as autorisé dans Supabase
  const redirectTo = 'http://localhost:3000/auth/callback';

  // Démarre un petit serveur local pour recevoir ?code=...
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 3000);

  try {
    await sb.auth.signInWithOAuth(OAuthProvider.google, redirectTo: redirectTo);

    // Attend le callback
    final req = await server.first;

    final error = req.uri.queryParameters['error'];
    final errorDesc = req.uri.queryParameters['error_description'];
    final code = req.uri.queryParameters['code'];

    // Répond au navigateur
    req.response.statusCode = 200;
    req.response.headers.contentType = ContentType.html;
    if (error != null) {
      req.response.write('<h3>Erreur: $error</h3><p>$errorDesc</p>');
    } else {
      req.response.write('<h3>OK. Tu peux fermer cette fenêtre.</h3>');
    }
    await req.response.close();

    if (error != null) {
      throw Exception('OAuth error: $error ($errorDesc)');
    }
    if (code == null || code.isEmpty) {
      throw Exception('Code OAuth manquant dans le callback.');
    }

    // Échange le code contre une session
    await sb.auth.exchangeCodeForSession(code);
  } finally {
    await server.close(force: true);
  }
}
