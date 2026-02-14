import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExploreBusinessesPage extends StatefulWidget {
  final String initialCategoryId;
  final String initialQuery;
  final String initialRegion;
  const ExploreBusinessesPage({
    super.key,
    this.initialCategoryId = '',
    this.initialQuery = '',
    this.initialRegion = '',
  });

  @override
  State<ExploreBusinessesPage> createState() => _ExploreBusinessesPageState();
}

enum _SortOption { newest, verifiedFirst, nameAz }

class _DbCategory {
  final String id;
  final String slug;
  final String name;
  final int sortOrder;

  const _DbCategory({
    required this.id,
    required this.slug,
    required this.name,
    required this.sortOrder,
  });

  factory _DbCategory.fromRow(Map<String, dynamic> row) {
    return _DbCategory(
      id: (row['id'] ?? '').toString(),
      slug: (row['slug'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      sortOrder: (row['sort_order'] is int) ? row['sort_order'] as int : 0,
    );
  }
}

class _CategoryOption {
  final String value;
  final String label;
  const _CategoryOption({required this.value, required this.label});
}

class _ExploreBusinessesPageState extends State<ExploreBusinessesPage> {
  final _sb = Supabase.instance.client;

  final _scroll = ScrollController();
  final _search = TextEditingController();

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  static const _pageSize = 20;
  int _offset = 0;

  String _region = '';
  String _category = '';
  _SortOption _sort = _SortOption.verifiedFirst;

  bool _dbCategoriesAvailable = false;
  final _dbCategories = <_DbCategory>[];

  final _items = <Map<String, dynamic>>[];

  static const _logoBucket = 'business_logos';
  static const _coverBucket = 'business_covers';

  static const _regions = <String, List<String>>{
    '': [''],
    'Lomé': ['Lomé', 'Lome', 'LomÃ©', 'LomÃƒÂ©', 'LomÃƒÂ©'],
    'Kpalimé': ['Kpalimé', 'Kpalime', 'KpalimÃ©', 'KpalimÃƒÂ©'],
    'Sokodé': ['Sokodé', 'Sokode', 'SokodÃ©', 'SokodÃƒÂ©'],
    'Kara': ['Kara'],
    'Tsévié': ['Tsévié', 'Tsevie', 'TsÃ©viÃ©', 'TsÃƒÂ©viÃƒÂ©'],
  };

  static const _regionSlugs = <String, String>{
    'lome': 'Lomé',
    'kpalime': 'Kpalimé',
    'sokode': 'Sokodé',
    'kara': 'Kara',
    'tsevie': 'Tsévié',
  };

  static const _categories = <String, List<String>>{
    '': [''],
    'Beauté': ['coiff', 'salon', 'beaute', 'beauté', 'beautÃ©', 'BeautÃ©'],
    'Restauration': ['restaurant', 'resto', 'traiteur', 'cuisine', 'bar', 'café', 'cafe', 'cafÃ©'],
    'BTP': ['btp', 'construction', 'quincaillerie', 'chantier'],
    'Transport': ['transport', 'livraison', 'logistique', 'taxi'],
    'Commerce': ['boutique', 'commerce', 'magasin', 'market', 'marché', 'marche', 'marchÃ©'],
    'Santé': ['santé', 'sante', 'santÃ©', 'pharmacie', 'clinique', 'cabinet'],
    'Éducation': ['école', 'ecole', 'Ã©cole', 'formation', 'cours'],
    'Tech': [
      'tech',
      'informatique',
      'numérique',
      'numerique',
      'numÃ©rique',
      'développement',
      'developpement',
      'dÃ©veloppement',
    ],
  };

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _category = widget.initialCategoryId;
    _search.text = widget.initialQuery.trim();
    _region = _normalizeRegionFromParam(widget.initialRegion);
    unawaited(_reloadAll());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    final pos = _scroll.position;
    if (!pos.hasPixels || !pos.hasContentDimensions) return;
    if (pos.pixels >= (pos.maxScrollExtent * 0.8)) {
      _loadMore();
    }
  }

  String _normalizeRegionFromParam(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    final lower = v.toLowerCase();

    final bySlug = _regionSlugs[lower];
    if (bySlug != null) return bySlug;

    for (final entry in _regions.entries) {
      final key = entry.key;
      if (key.isEmpty) continue;
      if (key.toLowerCase() == lower) return key;

      for (final pat in entry.value) {
        if (pat.trim().isEmpty) continue;
        if (pat.toLowerCase() == lower) return key;
      }
    }
    return '';
  }

  Future<void> _initDbCategoriesSupport() async {
    try {
      dynamic resp;
      try {
        resp = await _sb
            .from('categories')
            .select('id,slug,name,sort_order')
            .order('sort_order', ascending: true)
            .order('name', ascending: true);
      } on PostgrestException catch (e) {
        // Older schema may not include slug/sort_order yet.
        if (e.message.contains('slug') || e.message.contains('sort_order')) {
          resp = await _sb.from('categories').select('id,name').order('name', ascending: true);
        } else {
          rethrow;
        }
      }

      final rows = (resp as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final cats = rows.map(_DbCategory.fromRow).where((c) => c.id.isNotEmpty).toList();

      // Detect if the businesses column exists (query fails if not).
      await _sb.from('businesses').select('business_category_id').limit(1);

      if (!mounted) return;
      setState(() {
        _dbCategoriesAvailable = true;
        _dbCategories
          ..clear()
          ..addAll(cats);

        // If we were previously in legacy mode, the selected value might not be a UUID.
        final ids = _dbCategories.map((c) => c.id).toSet();
        if (_category.isNotEmpty && !ids.contains(_category)) {
          _category = '';
        }
      });
    } on PostgrestException {
      if (!mounted) return;
      setState(() {
        _dbCategoriesAvailable = false;
        _dbCategories.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dbCategoriesAvailable = false;
        _dbCategories.clear();
      });
    }
  }

  Future<void> _reloadAll() async {
    await _initDbCategoriesSupport();
    if (!mounted) return;
    await _loadInitial();
  }

  String? _publicUrl(String bucket, String? path) {
    if (path == null || path.isEmpty) return null;
    return _sb.storage.from(bucket).getPublicUrl(path);
  }

  String _sanitizeFilterValue(String input) {
    return input.trim().replaceAll(RegExp(r'[(),]'), ' ');
  }

  String? _buildSearchOrFilter(String query) {
    final q = _sanitizeFilterValue(query);
    if (q.isEmpty) return null;
    final pat = '%$q%';
    return [
      'name.ilike.$pat',
      'slug.ilike.$pat',
      'description.ilike.$pat',
    ].join(',');
  }

  String? _buildLegacyOrFilter({required String query, required String category}) {
    final q = _sanitizeFilterValue(query);
    final c = category.trim();

    final searchClauses = <String>[];
    if (q.isNotEmpty) {
      final pat = '%$q%';
      searchClauses.addAll([
        'name.ilike.$pat',
        'slug.ilike.$pat',
        'description.ilike.$pat',
      ]);
    }

    final catClauses = <String>[];
    final keywords = _categories[c] ?? const <String>[];
    for (final kwRaw in keywords) {
      final kw = _sanitizeFilterValue(kwRaw);
      if (kw.isEmpty) continue;
      final pat = '%$kw%';
      catClauses.addAll(['name.ilike.$pat', 'description.ilike.$pat']);
    }

    if (searchClauses.isEmpty && catClauses.isEmpty) return null;
    if (searchClauses.isNotEmpty && catClauses.isNotEmpty) {
      return 'and(or(${searchClauses.join(',')}),or(${catClauses.join(',')}))';
    }
    return (searchClauses.isNotEmpty ? searchClauses : catClauses).join(',');
  }

  PostgrestTransformBuilder<PostgrestList> _buildQuery() {
    final selectFields = _dbCategoriesAvailable
        ? 'id,name,slug,description,is_active,is_verified,whatsapp_phone,address_text,logo_path,cover_path,business_category_id,created_at'
        : 'id,name,slug,description,is_active,is_verified,whatsapp_phone,address_text,logo_path,cover_path,created_at';

    PostgrestFilterBuilder<PostgrestList> f = _sb
        .from('businesses')
        .select(selectFields)
        .eq('is_active', true);

    if (_dbCategoriesAvailable) {
      final searchOr = _buildSearchOrFilter(_search.text);
      if (searchOr != null) {
        f = f.or(searchOr);
      }
      if (_category.trim().isNotEmpty) {
        f = f.eq('business_category_id', _category.trim());
      }
    } else {
      final orFilter = _buildLegacyOrFilter(
        query: _search.text,
        category: _category,
      );
      if (orFilter != null) {
        f = f.or(orFilter);
      }
    }

    final regionPatterns = _regions[_region] ?? const <String>[];
    final patterns = regionPatterns.where((e) => e.trim().isNotEmpty).toList();
    if (patterns.isNotEmpty) {
      f = f
          .ilikeAnyOf('address_text', patterns.map((e) => '%$e%').toList())
          as PostgrestFilterBuilder<PostgrestList>;
    }

    PostgrestTransformBuilder<PostgrestList> q = f;
    switch (_sort) {
      case _SortOption.newest:
        q = q.order('created_at', ascending: false);
        break;
      case _SortOption.verifiedFirst:
        q = q.order('is_verified', ascending: false).order('created_at', ascending: false);
        break;
      case _SortOption.nameAz:
        q = q.order('name', ascending: true);
        break;
    }

    return q;
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
      _hasMore = true;
      _loadingMore = false;
      _offset = 0;
      _items.clear();
    });

    try {
      await _loadMore(reset: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loadingMore) return;
    if (!_hasMore && !reset) return;

    setState(() => _loadingMore = true);

    final offset = reset ? 0 : _offset;
    try {
      final resp = await _buildQuery().range(offset, offset + _pageSize - 1);
      final rows = (resp as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(rows);
        _offset = offset + rows.length;
        _hasMore = rows.length == _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingMore = false;
      });
    }
  }

  void _applyFilters({
    String? region,
    String? category,
    _SortOption? sort,
    bool resetSearch = false,
  }) {
    setState(() {
      if (region != null) _region = region;
      if (category != null) _category = category;
      if (sort != null) _sort = sort;
      if (resetSearch) _search.clear();
    });
    _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final contentMaxWidth = math.min(1100.0, width);
    final categories = _dbCategoriesAvailable
        ? [
            const _CategoryOption(value: '', label: 'Toutes'),
            ..._dbCategories.map((c) => _CategoryOption(value: c.id, label: c.name)),
          ]
        : const [
            _CategoryOption(value: '', label: 'Toutes'),
            _CategoryOption(value: 'Beauté', label: 'Beauté'),
            _CategoryOption(value: 'Restauration', label: 'Restauration'),
            _CategoryOption(value: 'BTP', label: 'BTP'),
            _CategoryOption(value: 'Transport', label: 'Transport'),
            _CategoryOption(value: 'Commerce', label: 'Commerce'),
            _CategoryOption(value: 'Santé', label: 'Santé'),
            _CategoryOption(value: 'Éducation', label: 'Éducation'),
            _CategoryOption(value: 'Tech', label: 'Tech'),
          ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explorer les entreprises'),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _reloadAll,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reloadAll,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FiltersCard(
                      search: _search,
                      region: _region,
                      category: _category,
                      categories: categories,
                      sort: _sort,
                      onChangedRegion: (v) => _applyFilters(region: v),
                      onChangedCategory: (v) => _applyFilters(category: v),
                      onChangedSort: (v) => _applyFilters(sort: v),
                      onSearch: _loadInitial,
                      onClear: () => _applyFilters(
                        region: '',
                        category: '',
                        sort: _SortOption.verifiedFirst,
                        resetSearch: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_loading)
                      const _LoadingBlock()
                    else if (_error != null)
                      _ErrorBlock(
                        message: _error!,
                        onRetry: _reloadAll,
                      )
                    else if (_items.isEmpty)
                      _EmptyBlock(
                        onReset: () => _applyFilters(
                          region: '',
                          category: '',
                          sort: _SortOption.verifiedFirst,
                          resetSearch: true,
                        ),
                      )
                    else
                      Column(
                        children: [
                          ..._items.map((b) {
                            final name = (b['name'] ?? '').toString();
                            final slug = (b['slug'] ?? '').toString();
                            final desc = (b['description'] ?? '').toString();
                            final verified = b['is_verified'] == true;
                            final phone = (b['whatsapp_phone'] ?? '').toString();
                            final address = (b['address_text'] ?? '').toString();
                            final logo = _publicUrl(_logoBucket, b['logo_path']?.toString());
                            final cover = _publicUrl(_coverBucket, b['cover_path']?.toString());

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _BusinessTile(
                                name: name,
                                slug: slug,
                                description: desc,
                                verified: verified,
                                phone: phone,
                                address: address,
                                logoUrl: logo,
                                coverUrl: cover,
                                onTap: slug.isEmpty ? null : () => context.push('/b/$slug'),
                              ),
                            );
                          }),
                          if (_loadingMore)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (!_hasMore)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                'Fin des résultats',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.black54),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FiltersCard extends StatelessWidget {
  final TextEditingController search;
  final String region;
  final String category;
  final List<_CategoryOption> categories;
  final _SortOption sort;

  final ValueChanged<String> onChangedRegion;
  final ValueChanged<String> onChangedCategory;
  final ValueChanged<_SortOption> onChangedSort;
  final VoidCallback onSearch;
  final VoidCallback onClear;

  const _FiltersCard({
    required this.search,
    required this.region,
    required this.category,
    required this.categories,
    required this.sort,
    required this.onChangedRegion,
    required this.onChangedCategory,
    required this.onChangedSort,
    required this.onSearch,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filtres',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: search,
              decoration: InputDecoration(
                labelText: 'Rechercher (nom, slug, description)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Rechercher',
                  onPressed: onSearch,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSearch(),
            ),
            const SizedBox(height: 10),
            isWide
                ? Row(
                    children: [
                      Expanded(
                        child: _RegionDropdown(value: region, onChanged: onChangedRegion),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _CategoryDropdown(
                          value: category,
                          categories: categories,
                          onChanged: onChangedCategory,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: _SortDropdown(value: sort, onChanged: onChangedSort)),
                    ],
                  )
                : Column(
                    children: [
                      _RegionDropdown(value: region, onChanged: onChangedRegion),
                      const SizedBox(height: 10),
                      _CategoryDropdown(
                        value: category,
                        categories: categories,
                        onChanged: onChangedCategory,
                      ),
                      const SizedBox(height: 10),
                      _SortDropdown(value: sort, onChanged: onChangedSort),
                    ],
                  ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: onSearch,
                  icon: const Icon(Icons.search),
                  label: const Text('Appliquer'),
                ),
                OutlinedButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear),
                  label: const Text('Réinitialiser'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RegionDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _RegionDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const items = <String>[
      '',
      'Lomé',
      'Kpalimé',
      'Sokodé',
      'Kara',
      'Tsévié',
    ];

    return DropdownButtonFormField<String>(
      key: ValueKey(value),
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Ville / région',
        prefixIcon: Icon(Icons.location_on),
      ),
      items: items
          .map(
            (r) => DropdownMenuItem(
              value: r,
              child: Text(r.isEmpty ? 'Tout le Togo' : r),
            ),
          )
          .toList(),
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  final String value;
  final List<_CategoryOption> categories;
  final ValueChanged<String> onChanged;
  const _CategoryDropdown({
    required this.value,
    required this.categories,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey(value),
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Catégorie',
        prefixIcon: Icon(Icons.category),
      ),
      items: categories
          .map(
            (c) => DropdownMenuItem(
              value: c.value,
              child: Text(c.label),
            ),
          )
          .toList(),
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}

class _SortDropdown extends StatelessWidget {
  final _SortOption value;
  final ValueChanged<_SortOption> onChanged;
  const _SortDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<_SortOption>(
      key: ValueKey(value),
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Tri',
        prefixIcon: Icon(Icons.sort),
      ),
      items: const [
        DropdownMenuItem(
          value: _SortOption.verifiedFirst,
          child: Text('Vérifiées d’abord'),
        ),
        DropdownMenuItem(value: _SortOption.newest, child: Text('Plus récentes')),
        DropdownMenuItem(value: _SortOption.nameAz, child: Text('Nom A → Z')),
      ],
      onChanged: (v) => onChanged(v ?? _SortOption.verifiedFirst),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Impossible de charger les entreprises',
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

class _EmptyBlock extends StatelessWidget {
  final VoidCallback onReset;
  const _EmptyBlock({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.search_off, size: 44),
            const SizedBox(height: 10),
            const Text(
              'Aucune entreprise ne correspond à ces filtres.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              "Essayez d'élargir la recherche ou de réinitialiser les filtres.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.clear),
              label: const Text('Réinitialiser'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessTile extends StatelessWidget {
  final String name;
  final String slug;
  final String description;
  final bool verified;
  final String phone;
  final String address;
  final String? logoUrl;
  final String? coverUrl;
  final VoidCallback? onTap;

  const _BusinessTile({
    required this.name,
    required this.slug,
    required this.description,
    required this.verified,
    required this.phone,
    required this.address,
    required this.logoUrl,
    required this.coverUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 160,
              child: coverUrl == null
                  ? Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Center(child: Icon(Icons.storefront, size: 42)),
                    )
                  : Image.network(
                      coverUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Logo(logoUrl: logoUrl, name: name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (verified) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified, size: 18, color: Color(0xFFF97316)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '@$slug',
                          style: const TextStyle(color: Colors.black54),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (address.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 16, color: Color(0xFFF59E0B)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  address,
                                  style: const TextStyle(color: Colors.black54),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          description.isEmpty ? '—' : description,
                          style: const TextStyle(color: Colors.black87),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.phone, size: 16, color: Color(0xFFF97316)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                phone.isEmpty ? 'Contact: non renseigné' : phone,
                                style: const TextStyle(color: Colors.black54),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Voir plus',
                              style: TextStyle(
                                color: Color(0xFFF97316),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final String? logoUrl;
  final String name;
  const _Logo({required this.logoUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    if (logoUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          logoUrl!,
          width: 46,
          height: 46,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _LogoFallback(name: name),
        ),
      );
    }
    return _LogoFallback(name: name);
  }
}

class _LogoFallback extends StatelessWidget {
  final String name;
  const _LogoFallback({required this.name});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final initials = parts.isEmpty
        ? 'PM'
        : parts.take(2).map((p) => p.substring(0, 1).toUpperCase()).join();

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFFF97316).withAlpha(26),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: Color(0xFFF97316),
        ),
      ),
    );
  }
}



