import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthCallbackPage extends StatefulWidget {
  const AuthCallbackPage({super.key});

  @override
  State<AuthCallbackPage> createState() => _AuthCallbackPageState();
}

class _AuthCallbackPageState extends State<AuthCallbackPage> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _handle();
  }

  Future<void> _handle() async {
    try {
      final uri = Uri.base;

      // Si OAuth renvoie une erreur
      final err = uri.queryParameters['error'];
      final errDesc = uri.queryParameters['error_description'];
      if (err != null) {
        setState(() => _error = 'OAuth error: $err ${errDesc ?? ""}');
        return;
      }

      final sb = Supabase.instance.client;

      // Supabase web: récupère la session depuis l’URL (code PKCE)
      await sb.auth.getSessionFromUrl(uri);

      final session = sb.auth.currentSession;
      if (session == null) {
        setState(() => _error = 'Session non créée. Réessaie la connexion.');
        return;
      }

      if (!mounted) return;
      final next = uri.queryParameters['next']?.trim();
      if (next != null && next.isNotEmpty && next.startsWith('/')) {
        context.go(next);
      } else {
        context.go('/home');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      ),
    );
  }
}
