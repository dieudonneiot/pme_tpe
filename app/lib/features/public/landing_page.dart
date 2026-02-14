import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _scroll = ScrollController();
  final _search = TextEditingController();

  bool _loadingBusinesses = true;
  String? _businessError;
  List<Map<String, dynamic>> _businesses = const [];
  String _region = '';

  bool _loadingCategories = true;
  String? _categoryError;
  List<_LandingCategory> _categories = const [];

  bool get _loggedIn => Supabase.instance.client.auth.currentSession != null;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadBusinesses();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  String? _publicUrl(String bucket, String? path) {
    if (path == null || path.isEmpty) return null;
    return Supabase.instance.client.storage.from(bucket).getPublicUrl(path);
  }

  Future<void> _loadBusinesses() async {
    setState(() {
      _loadingBusinesses = true;
      _businessError = null;
    });

    try {
      final sb = Supabase.instance.client;
      final q = _search.text.trim();

      var req = sb
          .from('businesses')
          .select(
            'id,name,slug,description,is_active,is_verified,whatsapp_phone,address_text,logo_path,cover_path',
          )
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(12);

      if (q.isNotEmpty) {
        req = sb
            .from('businesses')
            .select(
              'id,name,slug,description,is_active,is_verified,whatsapp_phone,address_text,logo_path,cover_path',
            )
            .eq('is_active', true)
            .or('name.ilike.%$q%,slug.ilike.%$q%')
            .order('created_at', ascending: false)
            .limit(12);
      }

      final rows = await req;
      _businesses =
          (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _businessError = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loadingBusinesses = false);
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loadingCategories = true;
      _categoryError = null;
    });

    try {
      final sb = Supabase.instance.client;
      dynamic resp;
      try {
        resp = await sb
            .from('categories')
            .select('id,name,slug,sort_order')
            .order('sort_order', ascending: true)
            .order('name', ascending: true);
      } on PostgrestException catch (e) {
        if (e.message.contains('slug') || e.message.contains('sort_order')) {
          resp = await sb.from('categories').select('id,name').order('name', ascending: true);
        } else {
          rethrow;
        }
      }

      final rows = (resp as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _categories = rows.map(_LandingCategory.fromRow).where((c) => c.id.isNotEmpty).toList();
    } catch (e) {
      _categoryError = e.toString();
      _categories = const [];
    } finally {
      if (mounted) {
        setState(() => _loadingCategories = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final contentMaxWidth = math.min(1100.0, width);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0xFFF97316),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text(
                'PT',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'PME/TPME Togo',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Langue',
            itemBuilder:
                (_) => const [
                  PopupMenuItem(value: 'fr', child: Text('Français')),
                  PopupMenuItem(value: 'ee', child: Text('Ewé')),
                  PopupMenuItem(value: 'kb', child: Text('Kabyè')),
                ],
            icon: const Icon(Icons.language),
            onSelected: (_) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Langue: à venir.')),
              );
            },
          ),
          const SizedBox(width: 6),
          if (_loggedIn)
            TextButton(
              onPressed: () => context.go('/home'),
              child: const Text('Dashboard'),
            )
          else
            FilledButton.icon(
              onPressed: () => context.push('/login'),
              icon: const Icon(Icons.person_add),
              label: const Text("S'inscrire"),
            ),
          const SizedBox(width: 8),
          if (_loggedIn)
            IconButton(
              tooltip: 'Déconnexion',
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scroll,
        child: Column(
          children: [
            _HeroSection(
              contentMaxWidth: contentMaxWidth,
              search: _search,
              region: _region,
              onChangedRegion: (v) => setState(() => _region = v),
              onSearch: () {
                final params = <String, String>{};
                final q = _search.text.trim();
                if (q.isNotEmpty) params['q'] = q;
                final r = _region.trim();
                if (r.isNotEmpty) params['region'] = r;

                final uri = Uri(path: '/explore', queryParameters: params.isEmpty ? null : params);
                context.go(uri.toString());
              },
            ),
            const SizedBox(height: 22),
            _SectionShell(
              contentMaxWidth: contentMaxWidth,
              title: 'Catégories populaires',
              subtitle:
                  "Trouvez rapidement une PME selon son secteur d'activité.",
              child: _CategoriesGrid(
                loading: _loadingCategories,
                error: _categoryError,
                categories: _categories,
                onOpenCategory: (id) {
                  final uri = Uri(path: '/explore', queryParameters: {'category': id});
                  context.go(uri.toString());
                },
              ),
            ),
            const SizedBox(height: 16),
            _SectionShell(
              contentMaxWidth: contentMaxWidth,
              title: 'Entreprises en vedette',
              subtitle:
                  "Une sélection d'entreprises locales actives (et vérifiées quand disponible).",
              trailing: TextButton(
                onPressed: () => context.go('/explore'),
                child: const Text('Découvrir'),
              ),
              child: _FeaturedBusinesses(
                loading: _loadingBusinesses,
                error: _businessError,
                businesses: _businesses,
                coverUrl: (path) => _publicUrl('business_covers', path),
                logoUrl: (path) => _publicUrl('business_logos', path),
                onOpen: (slug) => context.push('/b/$slug'),
              ),
            ),
            const SizedBox(height: 22),
            _Footer(contentMaxWidth: contentMaxWidth),
          ],
        ),
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  final double contentMaxWidth;
  final TextEditingController search;
  final String region;
  final ValueChanged<String> onChangedRegion;
  final VoidCallback onSearch;

  const _HeroSection({
    required this.contentMaxWidth,
    required this.search,
    required this.region,
    required this.onChangedRegion,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF97316), Color(0xFFF59E0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: Column(
              crossAxisAlignment:
                  isWide ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                Text(
                  'Découvrez et soutenez les PME togolaises',
                  textAlign: isWide ? TextAlign.center : TextAlign.left,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        height: 1.12,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Plateforme de référence pour trouver et promouvoir les petites et moyennes entreprises locales dans tous les secteurs d'activité.",
                  textAlign: isWide ? TextAlign.center : TextAlign.left,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white.withAlpha(235),
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 18),
                _SearchCard(
                  search: search,
                  region: region,
                  onChangedRegion: onChangedRegion,
                  onSearch: onSearch,
                ),
                const SizedBox(height: 18),
                Wrap(
                  alignment: isWide ? WrapAlignment.center : WrapAlignment.start,
                  spacing: 10,
                  runSpacing: 10,
                  children: const [
                    _StatChip(
                      icon: Icons.storefront,
                      label: 'PME référencées',
                      value: '5 000+',
                    ),
                    _StatChip(
                      icon: Icons.category,
                      label: 'Catégories',
                      value: '80+',
                    ),
                    _StatChip(
                      icon: Icons.location_on,
                      label: 'Villes couvertes',
                      value: '30+',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  final TextEditingController search;
  final String region;
  final ValueChanged<String> onChangedRegion;
  final VoidCallback onSearch;

  const _SearchCard({
    required this.search,
    required this.region,
    required this.onChangedRegion,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: isWide
            ? Row(
                children: [
                  Expanded(child: _SearchField(search: search, onSearch: onSearch)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 210,
                    child: _RegionField(region: region, onChanged: onChangedRegion),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: onSearch,
                      icon: const Icon(Icons.search),
                      label: const Text('Rechercher'),
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  _SearchField(search: search, onSearch: onSearch),
                  const SizedBox(height: 10),
                  _RegionField(region: region, onChanged: onChangedRegion),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: onSearch,
                      icon: const Icon(Icons.search),
                      label: const Text('Rechercher'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController search;
  final VoidCallback onSearch;
  const _SearchField({required this.search, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: search,
      decoration: const InputDecoration(
        labelText:
            'Que recherchez-vous ? (coiffure, restaurant, quincaillerie...)',
        prefixIcon: Icon(Icons.search),
      ),
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSearch(),
    );
  }
}

class _RegionField extends StatelessWidget {
  final String region;
  final ValueChanged<String> onChanged;
  const _RegionField({required this.region, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: ValueKey(region),
      initialValue: region.isEmpty ? '' : region,
      decoration: const InputDecoration(
        labelText: 'Localisation',
        prefixIcon: Icon(Icons.location_on),
      ),
      items: const [
        DropdownMenuItem(value: '', child: Text('Tout le Togo')),
        DropdownMenuItem(value: 'Lomé', child: Text('Lomé')),
        DropdownMenuItem(value: 'Kpalimé', child: Text('Kpalimé')),
        DropdownMenuItem(value: 'Sokodé', child: Text('Sokodé')),
        DropdownMenuItem(value: 'Kara', child: Text('Kara')),
        DropdownMenuItem(value: 'Tsévié', child: Text('Tsévié')),
      ],
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            '$value  ',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: TextStyle(color: Colors.white.withAlpha(235)),
          ),
        ],
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  final double contentMaxWidth;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  const _SectionShell({
    required this.contentMaxWidth,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth),
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
                          title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _LandingCategory {
  final String id;
  final String name;
  final String slug;
  final int sortOrder;

  const _LandingCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.sortOrder,
  });

  factory _LandingCategory.fromRow(Map<String, dynamic> row) {
    return _LandingCategory(
      id: (row['id'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      slug: (row['slug'] ?? '').toString(),
      sortOrder: (row['sort_order'] is int) ? row['sort_order'] as int : 0,
    );
  }
}

class _CategoriesGrid extends StatelessWidget {
  final bool loading;
  final String? error;
  final List<_LandingCategory> categories;
  final ValueChanged<String> onOpenCategory;

  const _CategoriesGrid({
    required this.loading,
    required this.error,
    required this.categories,
    required this.onOpenCategory,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1000 ? 4 : (width >= 700 ? 3 : 2);

    if (loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (categories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Aucune catégorie disponible.'),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.25,
      ),
      itemBuilder: (context, i) => _CategoryCard(
        cat: categories[i],
        onTap: () => onOpenCategory(categories[i].id),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final _LandingCategory cat;
  final VoidCallback onTap;
  const _CategoryCard({required this.cat, required this.onTap});

  IconData _iconForSlug(String slug, String name) {
    final s = slug.trim().toLowerCase();
    final n = name.trim().toLowerCase();
    final key = s.isEmpty ? n : s;
    if (key.contains('beau') || key.contains('coiff')) return Icons.content_cut;
    if (key.contains('rest') || key.contains('cuisin')) return Icons.restaurant;
    if (key.contains('btp') || key.contains('construct')) return Icons.construction;
    if (key.contains('trans') || key.contains('livr')) return Icons.local_shipping;
    if (key.contains('comm') || key.contains('bout')) return Icons.shopping_bag;
    if (key.contains('sant') || key.contains('pharma')) return Icons.medical_services;
    if (key.contains('educ') || key.contains('édu') || key.contains('ecol')) return Icons.school;
    if (key.contains('tech') || key.contains('info')) return Icons.devices;
    return Icons.category;
  }

  String _subtitleForSlug(String slug, String name) {
    final s = slug.trim().toLowerCase();
    final n = name.trim().toLowerCase();
    final key = s.isEmpty ? n : s;
    if (key.contains('beau') || key.contains('coiff')) return 'Coiffure & soins';
    if (key.contains('rest') || key.contains('cuisin')) return 'Restaurants & traiteurs';
    if (key.contains('btp') || key.contains('construct')) return 'Quincaillerie & services';
    if (key.contains('trans') || key.contains('livr')) return 'Logistique & livraison';
    if (key.contains('comm') || key.contains('bout')) return 'Boutiques & marchés';
    if (key.contains('sant') || key.contains('pharma')) return 'Cabinets & pharmacies';
    if (key.contains('educ') || key.contains('édu') || key.contains('ecol')) return 'Formations & écoles';
    if (key.contains('tech') || key.contains('info')) return 'Informatique & services';
    return 'Découvrir';
  }

  @override
  Widget build(BuildContext context) {
    final icon = _iconForSlug(cat.slug, cat.name);
    final subtitle = _subtitleForSlug(cat.slug, cat.name);

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF97316).withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFFF97316)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cat.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.black54),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, size: 18, color: Colors.black45),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedBusinesses extends StatelessWidget {
  final bool loading;
  final String? error;
  final List<Map<String, dynamic>> businesses;
  final String? Function(String? path) coverUrl;
  final String? Function(String? path) logoUrl;
  final ValueChanged<String> onOpen;

  const _FeaturedBusinesses({
    required this.loading,
    required this.error,
    required this.businesses,
    required this.coverUrl,
    required this.logoUrl,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (businesses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Aucune entreprise trouvée.'),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1000 ? 3 : (width >= 700 ? 2 : 1);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: businesses.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: cols == 1 ? 1.8 : 1.35,
      ),
      itemBuilder: (context, i) {
        final b = businesses[i];
        final name = (b['name'] ?? '').toString();
        final slug = (b['slug'] ?? '').toString();
        final desc = (b['description'] ?? '').toString();
        final verified = b['is_verified'] == true;
        final phone = (b['whatsapp_phone'] ?? '').toString();
        final cover = coverUrl(b['cover_path']?.toString());
        final logo = logoUrl(b['logo_path']?.toString());
        return _BusinessCard(
          name: name,
          slug: slug,
          description: desc,
          verified: verified,
          phone: phone,
          coverUrl: cover,
          logoUrl: logo,
          onTap: () => onOpen(slug),
        );
      },
    );
  }
}

class _BusinessCard extends StatelessWidget {
  final String name;
  final String slug;
  final String description;
  final bool verified;
  final String phone;
  final String? coverUrl;
  final String? logoUrl;
  final VoidCallback onTap;

  const _BusinessCard({
    required this.name,
    required this.slug,
    required this.description,
    required this.verified,
    required this.phone,
    required this.coverUrl,
    required this.logoUrl,
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
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (coverUrl != null)
                    Image.network(
                      coverUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                    )
                  else
                    Container(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Center(
                        child: Icon(Icons.storefront, size: 42),
                      ),
                    ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(245),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star,
                            size: 16,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            verified ? '4.8' : '4.5',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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
                              const Icon(
                                Icons.verified,
                                size: 18,
                                color: Color(0xFFF97316),
                              ),
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
                            const Icon(
                              Icons.phone,
                              size: 16,
                              color: Color(0xFFF97316),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                phone.isEmpty
                                    ? 'Contact: non renseigné'
                                    : phone,
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
        : parts
            .take(2)
            .map((p) => p.substring(0, 1).toUpperCase())
            .join();

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

class _Footer extends StatelessWidget {
  final double contentMaxWidth;
  const _Footer({required this.contentMaxWidth});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF111827),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PME/TPME Togo',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Annuaire et plateforme de promotion des entreprises togolaises.",
                  style: TextStyle(color: Colors.white.withAlpha(210)),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 18,
                  runSpacing: 10,
                  children: const [
                    _FooterItem(icon: Icons.location_on, text: 'Lomé, Togo'),
                    _FooterItem(icon: Icons.phone, text: '+228 22 22 22 22'),
                    _FooterItem(icon: Icons.email, text: 'contact@pme-togo.tg'),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: Colors.white.withAlpha(40)),
                const SizedBox(height: 10),
                Text(
                  '© 2026 PME Togo. Tous droits réservés.',
                  style: TextStyle(color: Colors.white.withAlpha(190)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FooterItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: const Color(0xFFF97316)),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: Colors.white.withAlpha(210))),
      ],
    );
  }
}
