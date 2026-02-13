import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateBusinessPage extends StatefulWidget {
  const CreateBusinessPage({super.key});

  @override
  State<CreateBusinessPage> createState() => _CreateBusinessPageState();
}

class _CreateBusinessPageState extends State<CreateBusinessPage> {
  final _name = TextEditingController();
  final _slug = TextEditingController();
  final _desc = TextEditingController();
  final _whatsapp = TextEditingController();
  final _address = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _desc.dispose();
    _whatsapp.dispose();
    _address.dispose();
    super.dispose();
  }

  String _slugify(String input) {
    var s = input.trim().toLowerCase();
    s = s
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ç', 'c');
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    s = s.replaceAll(RegExp(r'-+'), '-');
    s = s.replaceAll(RegExp(r'^-|-$'), '');
    if (s.length > 50) s = s.substring(0, 50).replaceAll(RegExp(r'-$'), '');
    return s;
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final slug = _slug.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Nom requis.');
      return;
    }
    if (slug.isEmpty) {
      setState(() => _error = 'Slug requis (ex: mon-boutique).');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final sb = Supabase.instance.client;

    try {
      // 1) Vérifier session
      final session = sb.auth.currentSession;
      if (session == null) {
        throw Exception('Session manquante. Reconnecte-toi.');
      }

      // 2) Appeler la function
      final res = await sb.functions.invoke(
        'create_business',
        body: {
          'name': name,
          'slug': slug,
          'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          'whatsapp_phone': _whatsapp.text.trim().isEmpty
              ? null
              : _whatsapp.text.trim(),
          'address_text': _address.text.trim().isEmpty
              ? null
              : _address.text.trim(),
          'lat': null,
          'lng': null,
        },
      );

      final data = res.data;
      if (data is! Map) {
        throw Exception('Réponse invalide (format inattendu).');
      }

      final businessId = data['business_id'] as String?;
      if (businessId == null || businessId.isEmpty) {
        throw Exception('Réponse invalide (business_id manquant).');
      }

      if (!mounted) return;
      context.pushReplacement('/business/$businessId/settings');
    } on FunctionException catch (e) {
      // Erreur renvoyée par Edge Functions (401/500 etc.)
      setState(() => _error = 'Function error (${e.status}): ${e.details}');
    } catch (e) {
      setState(() => _error = e.toString());
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
        title: const Text('Créer une entreprise'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Nom entreprise',
                  ),
                  onChanged: (v) {
                    if (_slug.text.isEmpty) {
                      _slug.text = _slugify(v);
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _slug,
                  decoration: const InputDecoration(
                    labelText: 'Slug (unique) ex: mon-boutique',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _whatsapp,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp (ex: +228XXXXXXXX)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Adresse'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _desc,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 3,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _create,
                    child: Text(_loading ? '...' : 'Créer'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
