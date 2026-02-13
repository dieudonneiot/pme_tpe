import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _loggedIn => Supabase.instance.client.auth.currentSession != null;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sb = Supabase.instance.client;
      final q = _search.text.trim();

      var req = sb
          .from('businesses')
          .select('id,name,slug,description,is_active,is_verified')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(30);

      if (q.isNotEmpty) {
        req = sb
            .from('businesses')
            .select('id,name,slug,description,is_active,is_verified')
            .eq('is_active', true)
            .or('name.ilike.%$q%,slug.ilike.%$q%')
            .order('created_at', ascending: false)
            .limit(30);
      }

      final rows = await req;
      _items = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explorer'),
        actions: [
          if (_loggedIn)
            TextButton(
              onPressed: () => context.go('/home'),
              child: const Text('Dashboard'),
            )
          else
            TextButton(
              onPressed: () => context.push('/login'),
              child: const Text('Se connecter'),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: InputDecoration(
                labelText: 'Rechercher une boutique (nom ou slug)',
                suffixIcon: IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (_) => _load(),
            ),
            const SizedBox(height: 12),
            if (_loading) const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(child: Center(child: Text(_error!, style: const TextStyle(color: Colors.red))))
            else if (_items.isEmpty)
              const Expanded(child: Center(child: Text('Aucune boutique trouvée.')))
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final b = _items[i];
                    final name = (b['name'] ?? '').toString();
                    final slug = (b['slug'] ?? '').toString();
                    final verified = b['is_verified'] == true;

                    return Card(
                      child: ListTile(
                        title: Row(
                          children: [
                            Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            if (verified) const SizedBox(width: 8),
                            if (verified)
                              const Icon(Icons.verified, size: 18),
                          ],
                        ),
                        subtitle: Text('@$slug', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.arrow_forward),
                        onTap: () => context.push('/b/$slug'),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
