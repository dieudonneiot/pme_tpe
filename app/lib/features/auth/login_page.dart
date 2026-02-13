import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/google_oauth.dart';

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

  bool _loading = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _email.dispose();
    _pass.dispose();
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

  Future<void> _signInPassword() async {
    _setLoading(true);
    _setError(null);
    _setInfo(null);

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _pass.text,
      );
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
      await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _pass.text,
      );

      _setInfo(
        "Compte créé. Vérifie ta boîte mail si la confirmation email est activée.",
      );
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
    return Scaffold(
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
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Connexion',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),

                          TabBar(
                            controller: _tabs,
                            tabs: const [
                              Tab(text: 'Mot de passe'),
                              Tab(text: 'Magic link'),
                            ],
                          ),

                          const SizedBox(height: 12),

                          TextField(
                            controller: _email,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 10),

                          SizedBox(
                            height: 190,
                            child: TabBarView(
                              controller: _tabs,
                              children: [
                                Column(
                                  children: [
                                    TextField(
                                      controller: _pass,
                                      decoration: const InputDecoration(
                                        labelText: 'Mot de passe',
                                      ),
                                      obscureText: true,
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: _loading
                                                ? null
                                                : _signInPassword,
                                            child: Text(
                                              _loading ? '...' : 'Se connecter',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: _loading
                                                ? null
                                                : _signUpPassword,
                                            child: const Text(
                                              'Créer un compte',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),

                                Column(
                                  children: [
                                    const Text(
                                      "Saisis ton email et reçois un lien de connexion.",
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: _loading
                                            ? null
                                            : _sendMagicLink,
                                        child: Text(
                                          _loading ? '...' : 'Envoyer le lien',
                                        ),
                                      ),
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
                              icon: const Icon(Icons.login),
                              label: const Text('Continuer avec Google'),
                            ),
                          ),

                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                          if (_info != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _info!,
                              style: const TextStyle(color: Colors.green),
                            ),
                          ],
                        ],
                      ),
                    ),
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
