import 'package:file_picker/file_picker.dart';
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

class BusinessSettingsPage extends StatefulWidget {
  final String businessId;
  const BusinessSettingsPage({super.key, required this.businessId});

  @override
  State<BusinessSettingsPage> createState() => _BusinessSettingsPageState();
}

class _BusinessSettingsPageState extends State<BusinessSettingsPage> {
  bool _loading = true;
  bool _saving = false;
  bool _uploadingLogo = false;
  bool _uploadingCover = false;

  String? _error;
  Map<String, dynamic>? business;

  final _whatsapp = TextEditingController();
  final _address = TextEditingController();
  final _desc = TextEditingController();

  bool _dbCategoriesAvailable = false;
  final _categories = <_BusinessCategory>[];
  String _selectedCategoryId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _whatsapp.dispose();
    _address.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _ensureAuthenticated() async {
    final sb = Supabase.instance.client;
    // Important: s'assure que le token est OK avant Storage / DB.
    await sb.auth.refreshSession();
    final session = sb.auth.currentSession;
    final user = sb.auth.currentUser;
    if (session == null || user == null) {
      throw Exception('Session manquante. Déconnecte-toi puis reconnecte-toi.');
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _ensureAuthenticated();

      final sb = Supabase.instance.client;
      Map<String, dynamic> row;
      var hasCategoryColumn = true;
      try {
        row = await sb
            .from('businesses')
            .select(
              'id,name,slug,description,whatsapp_phone,address_text,logo_path,cover_path,business_category_id',
            )
            .eq('id', widget.businessId)
            .single();
      } on PostgrestException catch (e) {
        if (e.message.contains('business_category_id')) {
          hasCategoryColumn = false;
          row = await sb
              .from('businesses')
              .select(
                'id,name,slug,description,whatsapp_phone,address_text,logo_path,cover_path',
              )
              .eq('id', widget.businessId)
              .single();
        } else {
          rethrow;
        }
      }

      business = row;
      _whatsapp.text = (row['whatsapp_phone'] ?? '') as String;
      _address.text = (row['address_text'] ?? '') as String;
      _desc.text = (row['description'] ?? '') as String;

      if (hasCategoryColumn) {
        _selectedCategoryId = (row['business_category_id'] ?? '').toString();
        await _loadDbCategories();
      } else {
        _dbCategoriesAvailable = false;
        _categories.clear();
        _selectedCategoryId = '';
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadDbCategories() async {
    try {
      final sb = Supabase.instance.client;
      final resp = await sb
          .from('business_categories')
          .select('id,name,sort_order')
          .order('sort_order', ascending: true)
          .order('name', ascending: true);

      final rows = (resp as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final cats = rows.map(_BusinessCategory.fromRow).where((c) => c.id.isNotEmpty).toList();

      if (!mounted) return;
      setState(() {
        _dbCategoriesAvailable = true;
        _categories
          ..clear()
          ..addAll(cats);

        final ids = _categories.map((c) => c.id).toSet();
        if (_selectedCategoryId.isNotEmpty && !ids.contains(_selectedCategoryId)) {
          _selectedCategoryId = '';
        }
      });
    } on PostgrestException {
      if (!mounted) return;
      setState(() {
        _dbCategoriesAvailable = false;
        _categories.clear();
        _selectedCategoryId = '';
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

  String _contentTypeFromExt(String? ext) {
    final e = (ext ?? '').toLowerCase();
    if (e == 'png') return 'image/png';
    if (e == 'jpg' || e == 'jpeg') return 'image/jpeg';
    if (e == 'webp') return 'image/webp';
    return 'application/octet-stream';
  }

  Future<void> _uploadImage({
    required String bucket,
    required String column, // doit être 'logo_path' ou 'cover_path'
  }) async {
    if (column != 'logo_path' && column != 'cover_path') {
      setState(() => _error = 'Colonne invalide: $column');
      return;
    }

    setState(() {
      _error = null;
      if (column == 'logo_path') {
        _uploadingLogo = true;
      } else {
        _uploadingCover = true;
      }
    });

    try {
      await _ensureAuthenticated();

      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Impossible de lire le fichier (bytes null).');
      }

      final ext = (file.extension ?? 'png').toLowerCase();
      // IMPORTANT: chemin = '<businessId>/...'
      final objectPath =
          '${widget.businessId}/${column}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final sb = Supabase.instance.client;

      // Upload vers Storage
      await sb.storage
          .from(bucket)
          .uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _contentTypeFromExt(ext),
            ),
          );

      // Update DB (businesses.logo_path / cover_path)
      await sb
          .from('businesses')
          .update({column: objectPath})
          .eq('id', widget.businessId);

      await _load();
    } on StorageException catch (e) {
      setState(() => _error = 'Storage error: ${e.message}');
    } on PostgrestException catch (e) {
      setState(() => _error = 'DB error: ${e.message}');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          if (column == 'logo_path') {
            _uploadingLogo = false;
          } else {
            _uploadingCover = false;
          }
        });
      }
    }
  }

  Future<void> _saveText() async {
    setState(() {
      _error = null;
      _saving = true;
    });

    try {
      await _ensureAuthenticated();

      final sb = Supabase.instance.client;
      final update = <String, dynamic>{
        'whatsapp_phone': _whatsapp.text.trim().isEmpty ? null : _whatsapp.text.trim(),
        'address_text': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      };

      if (_dbCategoriesAvailable) {
        update['business_category_id'] =
            _selectedCategoryId.trim().isEmpty ? null : _selectedCategoryId.trim();
      }

      await sb
          .from('businesses')
          .update(update)
          .eq('id', widget.businessId);

      await _load();
    } on PostgrestException catch (e) {
      setState(() => _error = 'DB error: ${e.message}');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String? _publicUrl(String bucket, String? path) {
    if (path == null || path.isEmpty) return null;
    final sb = Supabase.instance.client;
    return sb.storage.from(bucket).getPublicUrl(path);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final logoUrl = _publicUrl(
      'business_logos',
      business?['logo_path'] as String?,
    );
    final coverUrl = _publicUrl(
      'business_covers',
      business?['cover_path'] as String?,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Paramètres - ${business?['name'] ?? ''}'),
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
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 10),
                ],

                const Text(
                  'Médias',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              const Text('Logo'),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 120,
                                child: logoUrl == null
                                    ? const Center(child: Text('Aucun logo'))
                                    : Image.network(
                                        logoUrl,
                                        fit: BoxFit.contain,
                                      ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: _uploadingLogo
                                    ? null
                                    : () => _uploadImage(
                                        bucket: 'business_logos',
                                        column: 'logo_path',
                                      ),
                                child: Text(
                                  _uploadingLogo ? '...' : 'Uploader logo',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              const Text('Couverture'),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 120,
                                child: coverUrl == null
                                    ? const Center(
                                        child: Text('Aucune couverture'),
                                      )
                                    : Image.network(
                                        coverUrl,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: _uploadingCover
                                    ? null
                                    : () => _uploadImage(
                                        bucket: 'business_covers',
                                        column: 'cover_path',
                                      ),
                                child: Text(
                                  _uploadingCover
                                      ? '...'
                                      : 'Uploader couverture',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Text(
                  'Infos mini-site',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                if (_dbCategoriesAvailable) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey(_selectedCategoryId),
                    initialValue: _selectedCategoryId.isEmpty ? '' : _selectedCategoryId,
                    decoration: const InputDecoration(labelText: 'Catégorie'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Aucune'),
                      ),
                      ..._categories.map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedCategoryId = v ?? ''),
                  ),
                  const SizedBox(height: 10),
                ],

                TextField(
                  controller: _whatsapp,
                  decoration: const InputDecoration(labelText: 'WhatsApp'),
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

                const SizedBox(height: 16),
                const Text(
                  'B1 – Avancé',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                    onPressed: () {
                      final slug = (business?['slug'] ?? '').toString();
                      if (slug.isEmpty) return;
                      context.push('/b/$slug');
                    },                      icon: const Icon(Icons.public),
                      label: const Text('Ouvrir boutique publique'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/business/${widget.businessId}/settings/hours'),
                      icon: const Icon(Icons.access_time),
                      label: const Text('Horaires'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/business/${widget.businessId}/settings/links'),
                      icon: const Icon(Icons.link),
                      label: const Text('Liens'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/business/${widget.businessId}/settings/domains'),
                      icon: const Icon(Icons.domain),
                      label: const Text('Domaines'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveText,
                    child: Text(_saving ? '...' : 'Enregistrer'),
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
