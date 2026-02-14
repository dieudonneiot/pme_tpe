import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _loading = true;
  String? _error;
  bool _isAppAdmin = false;

  List<Map<String, dynamic>> _businesses = [];
  String? _selectedBusinessId;
  Map<String, dynamic>? _entitlements;

  Map<String, dynamic>? get _selectedBusiness {
    if (_selectedBusinessId == null) return null;
    for (final b in _businesses) {
      if (b['id'] == _selectedBusinessId) return b;
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sb = Supabase.instance.client;
      final user = sb.auth.currentUser;
      if (user == null) {
        throw Exception('Session manquante. Reconnecte-toi.');
      }

      final rows = await sb
          .from('business_members')
          .select('business_id, role, businesses:businesses(id,name,slug)')
          .eq('user_id', user.id);

      final list =
          (rows as List).map((e) {
            final biz = Map<String, dynamic>.from(e['businesses'] as Map);
            biz['role'] = e['role'];
            return biz;
          }).toList()..sort(
            (a, b) => (a['name'] as String).toLowerCase().compareTo(
              (b['name'] as String).toLowerCase(),
            ),
          );

      _businesses = list;

      if (_businesses.isEmpty) {
        _selectedBusinessId = null;
        _entitlements = null;
        return;
      }

      _selectedBusinessId ??= _businesses.first['id'] as String;

      if (_selectedBusiness == null) {
        _selectedBusinessId = _businesses.first['id'] as String;
      }

      final bid = _selectedBusinessId!;
      final ent = await sb
          .from('entitlements')
          .select(
            'can_receive_orders, can_run_ads, visibility_multiplier, plans:plans(code,name)',
          )
          .eq('business_id', bid)
          .single();

      _entitlements = Map<String, dynamic>.from(ent as Map);

      try {
        final v = await sb.rpc('is_app_admin');
        _isAppAdmin = v == true;
      } on PostgrestException {
        _isAppAdmin = false;
      } catch (_) {
        _isAppAdmin = false;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
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

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'admin':
        return 'Admin';
      default:
        return 'Staff';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedBusiness;
    final planCode = _entitlements?['plans']?['code']?.toString() ?? 'free';
    final planName = _entitlements?['plans']?['name']?.toString() ?? 'Free';
    final canOrders = _entitlements?['can_receive_orders'] == true;
    final canAds = _entitlements?['can_run_ads'] == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          TextButton(onPressed: _signOut, child: const Text('Déconnexion')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: _error != null
                  ? _ErrorCard(message: _error!, onRetry: _load)
                  : _businesses.isEmpty
                  ? _EmptyState(onCreate: () => context.push('/business/create'))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HeaderCard(
                          businesses: _businesses,
                          selectedBusinessId: _selectedBusinessId!,
                          onChangedBusinessId: (id) async {
                            setState(() => _selectedBusinessId = id);
                            await _load();
                          },
                          onCreateNew: () => context.push('/business/create'),
                          onOpenSettings: selected == null
                              ? null
                              : () => context.push(
                                  '/business/${selected['id']}/settings',
                                ),
                        ),
                        const SizedBox(height: 12),

                        // Plan + rôle
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _InfoChip(
                              label: 'Plan',
                              value: '$planName ($planCode)',
                            ),
                            _InfoChip(
                              label: 'Rôle',
                              value: _roleLabel(
                                (selected?['role'] ?? 'staff').toString(),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Tuiles fonctionnalités - CORRIGÉ
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // Calcul dynamique du nombre de colonnes
                              final crossAxisCount = constraints.maxWidth >= 900
                                  ? 4
                                  : constraints.maxWidth >= 600
                                  ? 2
                                  : 1;
                              // Calcul dynamique du ratio d'aspect
                              final childAspectRatio =
                                  constraints.maxWidth >= 900
                                  ? 1.4
                                  : constraints.maxWidth >= 600
                                  ? 1.6
                                  : 1.8;

                              return GridView.count(
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: childAspectRatio,
                                // Empêche le débordement en permettant le scroll
                                shrinkWrap: true,
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  _Tile(
                                    title: 'Mini-site public (B1)',
                                    subtitle: 'Voir la boutique publique',
                                    enabled: selected != null,
                                    onTap: () {
                                      final slug = (selected?['slug'] ?? '').toString();
                                      if (slug.isEmpty) return;
                                      context.push('/b/$slug');
                                    },
                                  ),

                                  _Tile(
                                    title: 'Paramètres mini-site (B1)',
                                    subtitle: 'Logo, couverture, infos + B1',
                                    enabled: selected != null,
                                    onTap: () {
                                      final id = (selected?['id'] ?? '').toString();
                                      if (id.isEmpty) return;
                                      context.push('/business/$id/settings');
                                    },
                                  ),

                                  _Tile(
                                    title: 'Horaires (B1)',
                                    subtitle: 'Ouv./Ferm. + plages horaires',
                                    enabled: selected != null,
                                    onTap: () {
                                      final id = (selected?['id'] ?? '').toString();
                                      if (id.isEmpty) return;
                                      context.push('/business/$id/settings/hours');
                                    },
                                  ),

                                  _Tile(
                                    title: 'Liens & réseaux (B1)',
                                    subtitle: 'WhatsApp, Instagram, etc.',
                                    enabled: selected != null,
                                    onTap: () {
                                      final id = (selected?['id'] ?? '').toString();
                                      if (id.isEmpty) return;
                                      context.push('/business/$id/settings/links');
                                    },
                                  ),

                                  _Tile(
                                    title: 'Domaines (B1)',
                                    subtitle: 'Custom domain + vérification',
                                    enabled: selected != null,
                                    onTap: () {
                                      final id = (selected?['id'] ?? '').toString();
                                      if (id.isEmpty) return;
                                      context.push('/business/$id/settings/domains');
                                    },
                                  ),

                                  _Tile(
                                    title: 'Posts',
                                    subtitle: 'Publier & gérer le feed',
                                    enabled: true,
                                    onTap: () {
                                      final id = (selected?['id'] ?? '').toString();
                                      if (id.isEmpty) return;
                                      context.push('/business/$id/posts'); // IMPORTANT: push, pas go
                                    },
                                  ),

                                  _Tile(
                                    title: 'Produits (B2)',
                                    subtitle: 'Catalogue avancé (variants + stock)',
                                    enabled: true,
                                    onTap: () {
                                      final id = (selected?['id'] ?? '').toString();
                                      if (id.isEmpty) return;

                                      // Route à créer ensuite (B2)
                                      context.push('/business/$id/products');
                                    },
                                  ),

                                  _Tile(
                                    title: 'Commandes / Demandes (B3)',
                                    subtitle: canOrders ? 'Workflow devis/facture/paiement' : 'Bloqué par le plan',
                                    enabled: canOrders,
                                    onTap: () {
                                      final id = (selected?['id'] ?? '').toString();
                                      if (id.isEmpty) return;

                                      // Route à créer ensuite (B3)
                                      context.push('/business/$id/requests');
                                    },
                                  ),

                                  _Tile(
                                    title: 'Publicités (Ads)',
                                    subtitle: canAds ? 'Activé' : 'Bloqué par le plan',
                                    enabled: canAds,
                                    onTap: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Fonctionnalité à venir.'),
                                        ),
                                      );
                                    },
                                  ),

                                  _Tile(
                                    title: 'Admin · Catégories',
                                    subtitle: _isAppAdmin
                                        ? 'Gérer la liste globale'
                                        : 'Réservé aux admins',
                                    enabled: _isAppAdmin,
                                    onTap: () => context.push('/admin/categories'),
                                  ),
                                ],
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

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Aucune entreprise',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Crée ta première entreprise pour activer le mini-site, les posts, le catalogue et les demandes.",
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onCreate,
                    child: const Text('Créer une entreprise'),
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

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Erreur',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(color: Colors.red),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final List<Map<String, dynamic>> businesses;
  final String selectedBusinessId;
  final ValueChanged<String> onChangedBusinessId;
  final VoidCallback onCreateNew;
  final VoidCallback? onOpenSettings;

  const _HeaderCard({
    required this.businesses,
    required this.selectedBusinessId,
    required this.onChangedBusinessId,
    required this.onCreateNew,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'Entreprise : ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selectedBusinessId,
                    items: businesses.map((b) {
                      final name = (b['name'] ?? '').toString();
                      final role = (b['role'] ?? 'staff').toString();
                      return DropdownMenuItem<String>(
                        value: b['id'] as String,
                        child: Text(
                          '$name • ${role.toUpperCase()}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (id) {
                      if (id == null) return;
                      onChangedBusinessId(id);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: onCreateNew,
                    child: const Text('Nouvelle entreprise'),
                  ),
                ),
                const SizedBox(width: 8),
                if (onOpenSettings != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onOpenSettings,
                      child: const Text('Paramètres mini-site'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: $value', overflow: TextOverflow.ellipsis));
  }
}

class _Tile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _Tile({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Icon(
                    enabled ? Icons.arrow_forward : Icons.lock,
                    size: 20,
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
