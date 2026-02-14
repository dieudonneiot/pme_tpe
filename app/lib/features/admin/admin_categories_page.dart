import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/app_back_button.dart';

class AdminCategoriesPage extends StatefulWidget {
  const AdminCategoriesPage({super.key});

  @override
  State<AdminCategoriesPage> createState() => _AdminCategoriesPageState();
}

class _CategoryRow {
  final String id;
  final String name;
  final String slug;
  final int sortOrder;

  const _CategoryRow({
    required this.id,
    required this.name,
    required this.slug,
    required this.sortOrder,
  });

  factory _CategoryRow.fromRow(Map<String, dynamic> row) {
    return _CategoryRow(
      id: (row['id'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      slug: (row['slug'] ?? '').toString(),
      sortOrder: (row['sort_order'] is int) ? row['sort_order'] as int : 0,
    );
  }
}

class _AdminCategoriesPageState extends State<AdminCategoriesPage> {
  final _sb = Supabase.instance.client;

  bool _checking = true;
  bool _isAdmin = false;
  bool _loading = false;
  String? _error;

  List<_CategoryRow> _items = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      final v = await _sb.rpc('is_app_admin');
      _isAdmin = v == true;
      if (_isAdmin) {
        await _load();
      }
    } on PostgrestException catch (e) {
      _error =
          'RPC is_app_admin manquant (exécute le SQL dans app/_supabase_sql/README.md).\n${e.message}';
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      dynamic resp;
      try {
        resp = await _sb
            .from('categories')
            .select('id,name,slug,sort_order')
            .order('sort_order', ascending: true)
            .order('name', ascending: true);
      } on PostgrestException catch (e) {
        if (e.message.contains('slug') || e.message.contains('sort_order')) {
          resp = await _sb.from('categories').select('id,name').order('name', ascending: true);
        } else {
          rethrow;
        }
      }

      final rows = (resp as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _items = rows.map(_CategoryRow.fromRow).where((c) => c.id.isNotEmpty).toList();
    } on PostgrestException catch (e) {
      _error = 'DB error: ${e.message}';
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor({required _CategoryRow? initial}) async {
    final res = await showDialog<_CategoryRow>(
      context: context,
      builder: (_) => _CategoryEditorDialog(initial: initial),
    );
    if (res == null) return;

    try {
      if (initial == null) {
        await _sb.from('categories').insert({
          'name': res.name.trim(),
          'slug': res.slug.trim().isEmpty ? null : res.slug.trim(),
          'sort_order': res.sortOrder,
        });
      } else {
        await _sb.from('categories').update({
          'name': res.name.trim(),
          'slug': res.slug.trim().isEmpty ? null : res.slug.trim(),
          'sort_order': res.sortOrder,
        }).eq('id', initial.id);
      }
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur DB: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _delete(_CategoryRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer la catégorie ?'),
        content: Text('“${row.name}”'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _sb.from('categories').delete().eq('id', row.id);
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur DB: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Admin · Catégories'),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _loading || _checking ? null : _init,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _checking
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorCard(message: _error!, onRetry: _init)
                    : !_isAdmin
                        ? const _NotAllowedCard()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Gérer la liste globale des catégories.',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ),
                                  FilledButton.icon(
                                    onPressed: _loading ? null : () => _openEditor(initial: null),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Ajouter'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: _loading
                                    ? const Center(child: CircularProgressIndicator())
                                    : _items.isEmpty
                                        ? const _EmptyCard()
                                        : ListView.separated(
                                            itemCount: _items.length,
                                            separatorBuilder: (context, index) =>
                                                const SizedBox(height: 10),
                                            itemBuilder: (context, i) {
                                              final c = _items[i];
                                              return Card(
                                                child: ListTile(
                                                  title: Text(
                                                    c.name,
                                                    style: const TextStyle(fontWeight: FontWeight.w900),
                                                  ),
                                                  subtitle: Text(
                                                    [
                                                      if (c.slug.trim().isNotEmpty) 'slug: ${c.slug}',
                                                      'ordre: ${c.sortOrder}',
                                                    ].join(' • '),
                                                  ),
                                                  trailing: Wrap(
                                                    spacing: 6,
                                                    children: [
                                                      IconButton(
                                                        tooltip: 'Éditer',
                                                        onPressed: () => _openEditor(initial: c),
                                                        icon: const Icon(Icons.edit),
                                                      ),
                                                      IconButton(
                                                        tooltip: 'Supprimer',
                                                        onPressed: () => _delete(c),
                                                        icon: const Icon(Icons.delete_outline),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
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

class _NotAllowedCard extends StatelessWidget {
  const _NotAllowedCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Accès refusé',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 8),
            Text('Ton compte n’est pas configuré comme admin applicatif.'),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('Aucune catégorie.'),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Erreur',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryEditorDialog extends StatefulWidget {
  final _CategoryRow? initial;
  const _CategoryEditorDialog({required this.initial});

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _slug;
  late final TextEditingController _sortOrder;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _slug = TextEditingController(text: widget.initial?.slug ?? '');
    _sortOrder = TextEditingController(text: (widget.initial?.sortOrder ?? 0).toString());
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  int _parseSortOrder() {
    final raw = _sortOrder.text.trim();
    final v = int.tryParse(raw);
    return v ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.initial == null;
    return AlertDialog(
      title: Text(isNew ? 'Ajouter une catégorie' : 'Éditer la catégorie'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Nom requis' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _slug,
                decoration: const InputDecoration(
                  labelText: 'Slug (optionnel)',
                  helperText: 'Ex: restauration, beaute, sante',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _sortOrder,
                decoration: const InputDecoration(labelText: 'Ordre'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(
              context,
              _CategoryRow(
                id: widget.initial?.id ?? '',
                name: _name.text.trim(),
                slug: _slug.text.trim(),
                sortOrder: _parseSortOrder(),
              ),
            );
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
