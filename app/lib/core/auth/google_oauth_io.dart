import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const int _loopbackPort = 3000;
const String _callbackPath = '/auth/callback';

Future<void> signInWithGoogleUnified() async {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    // Pour Android/iOS on fera un flow deep-link (différent).
    throw UnsupportedError('OAuth desktop uniquement (Windows/macOS/Linux).');
  }

  final sb = Supabase.instance.client;

  // Important: 127.0.0.1 évite les soucis IPv6 (localhost -> ::1)
  final redirectTo = 'http://127.0.0.1:$_loopbackPort$_callbackPath';

  HttpServer? server;
  final completer = Completer<Uri>();

  try {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, _loopbackPort);

    server.listen((HttpRequest req) async {
      try {
        if (req.uri.path != _callbackPath) {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }

        // Reconstituer une URI complète (host/scheme/port)
        final fullUri = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: _loopbackPort,
          path: req.uri.path,
          query: req.uri.query,
        );

        // Répondre au navigateur (page simple)
        req.response.headers.contentType = ContentType.html;
        req.response.write('''
<!doctype html>
<html>
  <body>
    <h3>Connexion terminée.</h3>
    <p>Tu peux fermer cet onglet et revenir à l’application.</p>
  </body>
</html>
''');
        await req.response.close();

        if (!completer.isCompleted) completer.complete(fullUri);
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    });

    // Lance OAuth
    await sb.auth.signInWithOAuth(OAuthProvider.google, redirectTo: redirectTo);

    // Attendre le retour navigateur
    final callbackUri = await completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () =>
          throw TimeoutException('OAuth timeout (pas de callback).'),
    );

    debugPrint('OAuth callback: $callbackUri');

    // Échange + création session
    await sb.auth.getSessionFromUrl(callbackUri);

    // À partir d’ici, session disponible -> ton GoRouter redirige vers /home
  } finally {
    try {
      await server?.close(force: true);
    } catch (_) {
      // ignore
    }
  }
}
