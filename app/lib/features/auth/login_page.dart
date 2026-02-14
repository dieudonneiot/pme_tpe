import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/google_oauth.dart';
import '../../core/widgets/app_back_button.dart';

// <-- vérifie le chemin

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _showPass = false;

  bool _loading = false;
  String? _error;
  String? _info;

  bool _navigated = false;
  late final StreamSubscription<AuthState> _authSub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);

    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (!mounted) return;
      if (Supabase.instance.client.auth.currentSession == null) return;
      _redirectIfSignedIn();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (Supabase.instance.client.auth.currentSession == null) return;
      _redirectIfSignedIn();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _email.dispose();
    _pass.dispose();
    _authSub.cancel();
    super.dispose();
  }

  void _setLoading(bool v) {
    if (!mounted) return;
    setState(() => _loading = v);
  }

  void _setError(String? msg) {
    if (!mounted) return;
    setState(() => _error = msg);
  }

  void _setInfo(String? msg) {
    if (!mounted) return;
    setState(() => _info = msg);
  }

  String _resolveNext(BuildContext context) {
    final next = GoRouterState.of(context).uri.queryParameters['next']?.trim();
    if (next == null || next.isEmpty) return '/home';
    if (!next.startsWith('/')) return '/home';
    if (next.startsWith('/login') || next.startsWith('/auth/callback')) return '/home';
    return next;
  }

  void _redirectIfSignedIn() {
    if (!mounted || _navigated) return;
    if (Supabase.instance.client.auth.currentSession == null) return;

    _navigated = true;
    final next = _resolveNext(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(next);
    });
  }

  Future<void> _signInPassword() async {
    _setLoading(true);
    _setError(null);
    _setInfo(null);

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _pass.text,
      );
      _redirectIfSignedIn();
    } on AuthException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _signUpPassword() async {
    _setLoading(true);
    _setError(null);
    _setInfo(null);

    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _pass.text,
      );

      if (res.session != null) {
        _redirectIfSignedIn();
      } else {
        _setInfo(
          'Compte créé. Vérifie ta boîte mail si la confirmation email est activée.',
        );
      }
    } on AuthException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _sendMagicLink() async {
    _setLoading(true);
    _setError(null);
    _setInfo(null);

    try {
      // Web: vers /auth/callback (plus propre que origin seul)
      final redirectTo = kIsWeb ? '${Uri.base.origin}/auth/callback' : null;

      await Supabase.instance.client.auth.signInWithOtp(
        email: _email.text.trim(),
        emailRedirectTo: redirectTo,
      );

      _setInfo(
        "Lien envoyé. Ouvre ton email et clique sur le lien pour te connecter.",
      );
    } on AuthException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _signInGoogle() async {
    _setLoading(true);
    _setError(null);
    _setInfo(null);

    try {
      // Web -> redirect /auth/callback
      // Windows -> loopback http://localhost:3000/auth/callback + exchangeCodeForSession
      await signInWithGoogleUnified();
      _redirectIfSignedIn();
    } on AuthException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final emailOk = _email.text.trim().isNotEmpty;
    final passOk = _pass.text.isNotEmpty;
    final canSubmit = emailOk && passOk;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackPath: '/'),
        title: const Text('Connexion'),
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              scheme.primary.withAlpha(220),
                              scheme.primary.withAlpha(120),
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(40),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.lock_outline, color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Connexion',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Accède au tableau de bord et à la gestion.',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TabBar(
                                controller: _tabs,
                                tabs: const [
                                  Tab(text: 'Mot de passe'),
                                  Tab(text: 'Lien magique'),
                                ],
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _email,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 230,
                                child: TabBarView(
                                  controller: _tabs,
                                  children: [
                                    Column(
                                      children: [
                                        TextField(
                                          controller: _pass,
                                          decoration: InputDecoration(
                                            labelText: 'Mot de passe',
                                            prefixIcon: const Icon(Icons.password_outlined),
                                            suffixIcon: IconButton(
                                              tooltip: _showPass ? 'Masquer' : 'Afficher',
                                              onPressed: () => setState(() => _showPass = !_showPass),
                                              icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                                            ),
                                          ),
                                          obscureText: !_showPass,
                                          textInputAction: TextInputAction.done,
                                          onChanged: (_) => setState(() {}),
                                          onSubmitted: (_) => (_loading || !canSubmit) ? null : _signInPassword(),
                                        ),
                                        const SizedBox(height: 14),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: FilledButton.icon(
                                                onPressed: (_loading || !canSubmit) ? null : _signInPassword,
                                                icon: _loading
                                                    ? const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child: CircularProgressIndicator(strokeWidth: 2),
                                                      )
                                                    : const Icon(Icons.login),
                                                label: const Text('Se connecter'),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: FilledButton.tonal(
                                                onPressed: (_loading || !canSubmit) ? null : _signUpPassword,
                                                child: const Text('Créer un compte'),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'Astuce: utilise le lien magique si tu oublies ton mot de passe.',
                                            style: TextStyle(color: scheme.onSurfaceVariant),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      children: [
                                        Text(
                                          'Saisis ton email et reçois un lien de connexion sécurisé.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: scheme.onSurfaceVariant),
                                        ),
                                        const SizedBox(height: 14),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton.icon(
                                            onPressed: (_loading || !emailOk) ? null : _sendMagicLink,
                                            icon: _loading
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                  )
                                                : const Icon(Icons.mark_email_read_outlined),
                                            label: const Text('Envoyer le lien'),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          "Le lien ouvre l’application et te connecte automatiquement.",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: scheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _loading ? null : _signInGoogle,
                                  icon: const Icon(Icons.g_mobiledata),
                                  label: const Text('Continuer avec Google'),
                                ),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: scheme.errorContainer.withAlpha(90),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: scheme.errorContainer),
                                  ),
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      color: scheme.onErrorContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                              if (_info != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withAlpha(16),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: scheme.outlineVariant),
                                  ),
                                  child: Text(
                                    _info!,
                                    style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
