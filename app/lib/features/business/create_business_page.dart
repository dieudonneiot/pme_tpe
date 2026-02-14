import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _BusinessCategory {
  final String id;
  final String name;
  final int sortOrder;

  const _BusinessCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  factory _BusinessCategory.fromRow(Map<String, dynamic> row) {
    return _BusinessCategory(
      id: (row['id'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      sortOrder: (row['sort_order'] is int) ? row['sort_order'] as int : 0,
    );
  }
}

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

  bool _dbCategoriesAvailable = false;
  final _categories = <_BusinessCategory>[];
  String _selectedCategoryId = '';

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

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

  Future<void> _loadCategories() async {
    try {
      final sb = Supabase.instance.client;
      dynamic resp;
      try {
        resp = await sb
            .from('categories')
            .select('id,name,sort_order')
            .order('sort_order', ascending: true)
            .order('name', ascending: true);
      } on PostgrestException catch (e) {
        if (e.message.contains('sort_order')) {
          resp = await sb.from('categories').select('id,name').order('name', ascending: true);
        } else {
          rethrow;
        }
      }

      final rows = (resp as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final cats = rows.map(_BusinessCategory.fromRow).where((c) => c.id.isNotEmpty).toList();

      if (!mounted) return;
      setState(() {
        _dbCategoriesAvailable = cats.isNotEmpty;
        _categories
          ..clear()
          ..addAll(cats);
        final ids = _categories.map((c) => c.id).toSet();
        if (_selectedCategoryId.isNotEmpty && !ids.contains(_selectedCategoryId)) {
          _selectedCategoryId = '';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dbCategoriesAvailable = false;
        _categories.clear();
        _selectedCategoryId = '';
      });
    }
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
    if (_dbCategoriesAvailable && _selectedCategoryId.isEmpty) {
      setState(() => _error = 'Catégorie requise.');
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

      // Best-effort slug uniqueness hint (server still enforces uniqueness)
      try {
        final existing = await sb.from('businesses').select('id').eq('slug', slug).maybeSingle();
        if (existing != null) {
          throw Exception('Ce slug est déjà utilisé. Choisis-en un autre.');
        }
      } catch (e) {
        // Ignore if RLS blocks it; server will validate.
        if (e.toString().contains('déjà utilisé')) rethrow;
      }

      // 2) Appeler la function
      final res = await sb.functions.invoke(
        'create_business',
        body: {
          'name': name,
          'slug': slug,
          'business_category_id': _selectedCategoryId.isEmpty ? null : _selectedCategoryId,
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
            child: ListView(
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Nom entreprise',
                    hintText: 'Ex: Leo boutique',
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
                    hintText: 'ex: leo-boutique',
                  ),
                ),
                const SizedBox(height: 10),
                if (_dbCategoriesAvailable) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey(_selectedCategoryId),
                    initialValue: _selectedCategoryId.isEmpty ? '' : _selectedCategoryId,
                    decoration: const InputDecoration(labelText: 'Catégorie'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Choisir...')),
                      ..._categories.map(
                        (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                      ),
                    ],
                    onChanged: _loading ? null : (v) => setState(() => _selectedCategoryId = v ?? ''),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: _whatsapp,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp (ex: +228XXXXXXXX)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _address,
                  decoration: const InputDecoration(
                    labelText: 'Adresse (ville/quartier)',
                    hintText: 'Ex: Lomé, Agoè ...',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _desc,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Décris brièvement ton activité et ce que tu proposes.',
                  ),
                  maxLines: 3,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading ? null : _create,
                    child: Text(_loading ? '...' : 'Créer'),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Tu pourras ajouter le logo, la couverture, les horaires et les liens après la création.",
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
