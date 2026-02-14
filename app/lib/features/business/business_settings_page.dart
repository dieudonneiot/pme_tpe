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
  bool _deleting = false;

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

  Future<bool> _confirmDeleteBusiness() async {
    final slug = (business?['slug'] ?? '').toString().trim();
    final name = (business?['name'] ?? '').toString().trim();
    final requiredText = slug.isNotEmpty ? slug : 'SUPPRIMER';

    return (await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            var typed = '';
            return StatefulBuilder(
              builder: (context, setLocalState) {
                final canDelete = typed.trim().toLowerCase() == requiredText.toLowerCase();
                return AlertDialog(
                  title: const Text('Supprimer la boutique ?'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty
                            ? 'Cette action va archiver la boutique et la retirer des tableaux de bord.'
                            : 'Cette action va archiver "$name" et la retirer des tableaux de bord.',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        slug.isNotEmpty
                            ? 'Tape le slug pour confirmer: $requiredText'
                            : 'Tape SUPPRIMER pour confirmer.',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        autofocus: true,
                        onChanged: (v) => setLocalState(() => typed = v),
                        decoration: const InputDecoration(
                          labelText: 'Confirmation',
                          hintText: '...',
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Annuler'),
                    ),
                    ElevatedButton(
                      onPressed: canDelete ? () => Navigator.of(context).pop(true) : null,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Supprimer'),
                    ),
                  ],
                );
              },
            );
          },
        )) ??
        false;
  }

  Future<void> _deleteBusiness() async {
    setState(() {
      _error = null;
      _deleting = true;
    });

    try {
      await _ensureAuthenticated();

      final ok = await _confirmDeleteBusiness();
      if (!ok) return;

      final sb = Supabase.instance.client;
      await sb.rpc('delete_business', params: {'_business_id': widget.businessId});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Boutique supprimée (archivée).')),
      );
      context.go('/home');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _error = 'DB error: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  String? _publicUrl(String bucket, String? path) {
    if (path == null || path.isEmpty) return null;
    final sb = Supabase.instance.client;
    return sb.storage.from(bucket).getPublicUrl(path);
  }

  String? _selectedCategoryName() {
    if (!_dbCategoriesAvailable) return null;
    final id = _selectedCategoryId.trim();
    if (id.isEmpty) return null;
    for (final c in _categories) {
      if (c.id == id) return c.name;
    }
    return null;
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _mediaHeader({
    required String name,
    required String slug,
    required String? logoUrl,
    required String? coverUrl,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final categoryName = _selectedCategoryName();

    return Card(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AspectRatio(
                  aspectRatio: 3.2,
                  child: InkWell(
                    onTap: _uploadingCover
                        ? null
                        : () => _uploadImage(
                              bucket: 'business_covers',
                              column: 'cover_path',
                            ),
                    child: coverUrl == null
                        ? Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  scheme.primary.withAlpha(51),
                                  scheme.tertiary.withAlpha(46),
                                  scheme.surfaceContainerHighest,
                                ],
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.image_outlined,
                                size: 44,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Image.network(
                            coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: scheme.surfaceContainerHighest,
                              child: Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 44,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: IconButton.filledTonal(
                    onPressed: _uploadingCover
                        ? null
                        : () => _uploadImage(
                              bucket: 'business_covers',
                              column: 'cover_path',
                            ),
                    tooltip: 'Modifier la couverture',
                    icon: _uploadingCover
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_outlined),
                  ),
                ),
                Positioned(
                  left: 16,
                  bottom: -34,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.surface,
                          border: Border.all(color: scheme.surface, width: 4),
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 18,
                              offset: Offset(0, 10),
                              color: Color(0x33000000),
                            ),
                          ],
                        ),
                        child: InkWell(
                          onTap: _uploadingLogo
                              ? null
                              : () => _uploadImage(
                                    bucket: 'business_logos',
                                    column: 'logo_path',
                                  ),
                          child: ClipOval(
                            child: logoUrl == null
                                ? Container(
                                    color: scheme.surfaceContainerHighest,
                                    child: Icon(
                                      Icons.storefront_outlined,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  )
                                : Image.network(
                                    logoUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      color: scheme.surfaceContainerHighest,
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -6,
                        bottom: -6,
                        child: IconButton.filledTonal(
                          onPressed: _uploadingLogo
                              ? null
                              : () => _uploadImage(
                                    bucket: 'business_logos',
                                    column: 'logo_path',
                                  ),
                          tooltip: 'Modifier le logo',
                          icon: _uploadingLogo
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.edit_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 46),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isEmpty ? 'Boutique' : name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (slug.isNotEmpty)
                              Text(
                                '@$slug',
                                style: TextStyle(color: scheme.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: () {
                          if (slug.isEmpty) return;
                          context.push('/b/$slug');
                        },
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.public, size: 18),
                            SizedBox(width: 8),
                            Text('Aperçu public'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (categoryName != null)
                        Chip(
                          label: Text(categoryName),
                          side: BorderSide(color: scheme.outlineVariant),
                          backgroundColor: scheme.surface,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final scheme = Theme.of(context).colorScheme;
    final name = (business?['name'] ?? '').toString();
    final slug = (business?['slug'] ?? '').toString();

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
        title: const Text('Paramètres'),
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

                _mediaHeader(name: name, slug: slug, logoUrl: logoUrl, coverUrl: coverUrl),

                const SizedBox(height: 16),
                _sectionTitle('Infos mini-site'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (_dbCategoriesAvailable) ...[
                          DropdownButtonFormField<String>(
                            key: ValueKey(_selectedCategoryId),
                            initialValue:
                                _selectedCategoryId.isEmpty ? '' : _selectedCategoryId,
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
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          controller: _whatsapp,
                          decoration: const InputDecoration(
                            labelText: 'WhatsApp',
                            prefixIcon: Icon(Icons.chat_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _address,
                          decoration: const InputDecoration(
                            labelText: 'Adresse',
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _desc,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            prefixIcon: Icon(Icons.description_outlined),
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                _sectionTitle('Avancé'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.tonal(
                          onPressed: () => context.push(
                            '/business/${widget.businessId}/settings/hours',
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.access_time, size: 18),
                              SizedBox(width: 8),
                              Text('Horaires'),
                            ],
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () => context.push(
                            '/business/${widget.businessId}/settings/links',
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.link, size: 18),
                              SizedBox(width: 8),
                              Text('Liens'),
                            ],
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () => context.push(
                            '/business/${widget.businessId}/settings/domains',
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.domain, size: 18),
                              SizedBox(width: 8),
                              Text('Domaines'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                _sectionTitle('Zone dangereuse'),
                Card(
                  color: scheme.errorContainer.withAlpha(89),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Supprimer archive la boutique (elle n'apparaît plus publiquement).",
                          style: TextStyle(color: scheme.onErrorContainer),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _deleting ? null : _deleteBusiness,
                            style: FilledButton.styleFrom(
                              backgroundColor: scheme.error,
                              foregroundColor: scheme.onError,
                            ),
                            icon: _deleting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.delete),
                            label: const Text('Supprimer la boutique'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 90),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveText,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Enregistrer'),
            ),
          ),
        ),
      ),
    );
  }
}
