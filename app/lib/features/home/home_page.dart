import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/app_back_button.dart';

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
          .select('business_id, role, businesses:businesses(id,name,slug,logo_path)')
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
      dynamic ent;
      try {
        ent = await sb
            .from('entitlements')
            .select(
              'can_receive_orders, can_run_ads, visibility_multiplier, orders_grant_until, orders_paid_until, plans:plans(code,name)',
            )
            .eq('business_id', bid)
            .single();
      } on PostgrestException catch (e) {
        final m = e.message.toLowerCase();
        if (m.contains('orders_grant_until') || m.contains('orders_paid_until')) {
          ent = await sb
              .from('entitlements')
              .select(
                'can_receive_orders, can_run_ads, visibility_multiplier, plans:plans(code,name)',
              )
              .eq('business_id', bid)
              .single();
        } else {
          rethrow;
        }
      }

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
    } finally {
      if (mounted) context.go('/');
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
    final now = DateTime.now();
    final hasPaidUntil = _entitlements?.containsKey('orders_paid_until') == true;
    final paidUntil = DateTime.tryParse((_entitlements?['orders_paid_until'] ?? '').toString());
    final grantUntil = DateTime.tryParse((_entitlements?['orders_grant_until'] ?? '').toString());

    final paid = paidUntil != null && paidUntil.isAfter(now);
    final granted = grantUntil != null && grantUntil.isAfter(now);

    final canOrdersFlag = _entitlements?['can_receive_orders'] == true;
    final canOrders = hasPaidUntil
        ? (canOrdersFlag && (paid || granted))
        : (canOrdersFlag || granted);
    final canAds = _entitlements?['can_run_ads'] == true;

    final selectedLogoPath = (selected?['logo_path'] ?? '').toString();
    final selectedLogoUrl = selectedLogoPath.isEmpty
        ? null
        : Supabase.instance.client.storage.from('business_logos').getPublicUrl(selectedLogoPath);

    final roleLabel = _roleLabel((selected?['role'] ?? 'staff').toString());
    final ordersStatus = canOrders ? 'Actif' : 'Inactif';
    final adsStatus = canAds ? 'Actif' : 'Inactif';
    final monetisationStatus = hasPaidUntil
        ? (paid ? 'Abonnement actif' : (granted ? 'Grant admin' : 'Abonnement requis'))
        : '$planName ($planCode)';

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackPath: '/'),
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
                  ? _EmptyState(
                      onCreate: () => context.push('/business/create'),
                      onExplore: () => context.go('/explore'),
                      onOrders: () => context.push('/my/orders'),
                      onNotifications: () => context.push('/notifications'),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HeaderCard(
                          businesses: _businesses,
                          selectedBusinessId: _selectedBusinessId!,
                          selectedLogoUrl: selectedLogoUrl,
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
                          planLabel: '$planName ($planCode)',
                          roleLabel: roleLabel,
                          ordersLabel: 'Commandes: $ordersStatus',
                          adsLabel: 'Ads: $adsStatus',
                          monetisationLabel: monetisationStatus,
                          onOpenBilling: selected == null
                              ? null
                              : () => context.push(
                                  '/business/${selected['id']}/settings/billing',
                                ),
                          onOpenOrders: selected == null
                              ? null
                              : () {
                                  final id = (selected['id'] ?? '').toString();
                                  if (id.isEmpty) return;
                                  if (canOrders) {
                                    context.push('/business/$id/requests');
                                  } else {
                                    context.push('/business/$id/settings/billing');
                                  }
                                },
                          onOpenMembers: selected == null
                              ? null
                              : () {
                                  final id = (selected['id'] ?? '').toString();
                                  if (id.isEmpty) return;
                                  context.push('/business/$id/members');
                                },
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
                                    icon: Icons.public,
                                    tag: 'B1',
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
                                    icon: Icons.settings_outlined,
                                    tag: 'B1',
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
                                    icon: Icons.access_time,
                                    tag: 'B1',
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
                                    icon: Icons.hub_outlined,
                                    tag: 'B1',
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
                                    icon: Icons.domain_outlined,
                                    tag: 'B1',
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
                                    icon: Icons.inventory_2_outlined,
                                    tag: 'B2',
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
                                    icon: Icons.stacked_line_chart_outlined,
                                    tag: 'B2',
                                    title: 'Stock (B2)',
                                    subtitle: 'Inventaire, stocks bas, ajustements',
                                    enabled: true,
                                    onTap: () {
                                      final id = (selected?['id'] ?? '').toString();
                                      if (id.isEmpty) return;
                                      context.push('/business/$id/inventory');
                                    },
                                  ),

                                  _Tile(
                                    icon: Icons.workspace_premium_outlined,
                                    tag: 'PRO',
                                    title: 'Monetisation',
                                    subtitle: hasPaidUntil
                                        ? (paid
                                            ? 'Abonnement actif'
                                            : (granted ? 'Actif (grant admin)' : 'Inactif (abonnement requis)'))
                                        : 'Plan: $planName ($planCode)',
                                    enabled: selected != null,
                                    onTap: () {
                                      final id = (selected?['id'] ?? '').toString();
                                      if (id.isEmpty) return;
                                      context.push('/business/$id/settings/billing');
                                    },
                                  ),

                                  _Tile(
                                    icon: Icons.receipt_long_outlined,
                                    tag: 'B3',
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
                                    icon: Icons.campaign_outlined,
                                    tag: 'ADS',
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
                                    icon: Icons.category_outlined,
                                    tag: 'ADMIN',
                                    title: 'Admin · Catégories',
                                    subtitle: _isAppAdmin
                                        ? 'Gérer la liste globale'
                                        : 'Réservé aux admins',
                                    enabled: _isAppAdmin,
                                    onTap: () => context.push('/admin/categories'),
                                  ),

                                  _Tile(
                                    icon: Icons.workspace_premium,
                                    tag: 'ADMIN',
                                    title: 'Admin · Abonnements',
                                    subtitle: _isAppAdmin
                                        ? 'Entitlements (orders/ads)'
                                        : 'Réservé aux admins',
                                    enabled: _isAppAdmin,
                                    onTap: () => context.push('/admin/entitlements'),
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
  final VoidCallback onExplore;
  final VoidCallback onOrders;
  final VoidCallback onNotifications;

  const _EmptyState({
    required this.onCreate,
    required this.onExplore,
    required this.onOrders,
    required this.onNotifications,
  });

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
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onExplore,
                        icon: const Icon(Icons.explore),
                        label: const Text('Explorer'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onOrders,
                        icon: const Icon(Icons.receipt_long),
                        label: const Text('Mes commandes'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onNotifications,
                    icon: const Icon(Icons.notifications_none),
                    label: const Text('Notifications'),
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
  final String? selectedLogoUrl;
  final ValueChanged<String> onChangedBusinessId;
  final VoidCallback onCreateNew;
  final VoidCallback? onOpenSettings;
  final String planLabel;
  final String roleLabel;
  final String ordersLabel;
  final String adsLabel;
  final String monetisationLabel;
  final VoidCallback? onOpenBilling;
  final VoidCallback? onOpenOrders;
  final VoidCallback? onOpenMembers;

  const _HeaderCard({
    required this.businesses,
    required this.selectedBusinessId,
    required this.selectedLogoUrl,
    required this.onChangedBusinessId,
    required this.onCreateNew,
    required this.onOpenSettings,
    required this.planLabel,
    required this.roleLabel,
    required this.ordersLabel,
    required this.adsLabel,
    required this.monetisationLabel,
    required this.onOpenBilling,
    required this.onOpenOrders,
    required this.onOpenMembers,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary.withAlpha(24),
                scheme.tertiary.withAlpha(18),
                scheme.surface,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: scheme.primaryContainer,
                      foregroundImage:
                          selectedLogoUrl == null ? null : NetworkImage(selectedLogoUrl!),
                      child: selectedLogoUrl == null
                          ? Icon(Icons.storefront_outlined, color: scheme.onPrimaryContainer)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Entreprise',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            key: ValueKey(selectedBusinessId),
                            initialValue: selectedBusinessId,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding:
                                  EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
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
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _StatPill(
                      icon: Icons.workspace_premium_outlined,
                      text: planLabel,
                      onTap: onOpenBilling,
                      tooltip: 'Ouvrir la monétisation',
                    ),
                    _StatPill(
                      icon: Icons.verified_user_outlined,
                      text: 'Rôle: $roleLabel',
                      onTap: onOpenMembers,
                      tooltip: 'Gérer les membres',
                    ),
                    _StatPill(
                      icon: Icons.receipt_long_outlined,
                      text: ordersLabel,
                      onTap: onOpenOrders,
                      tooltip: 'Ouvrir les commandes',
                    ),
                    _StatPill(
                      icon: Icons.campaign_outlined,
                      text: adsLabel,
                      onTap: onOpenBilling,
                      tooltip: 'Voir les options Ads',
                    ),
                    _StatPill(
                      icon: Icons.payments_outlined,
                      text: monetisationLabel,
                      onTap: onOpenBilling,
                      tooltip: 'Ouvrir la monétisation',
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: onCreateNew,
                        icon: const Icon(Icons.add_business_outlined),
                        label: const Text('Nouvelle entreprise'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (onOpenSettings != null)
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: onOpenSettings,
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('Paramètres mini-site'),
                        ),
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

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  final String? tooltip;
  const _StatPill({
    required this.icon,
    required this.text,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurface),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
    );

    if (onTap == null) return child;

    return Tooltip(
      message: tooltip ?? 'Ouvrir',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: child,
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String tag;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = enabled ? scheme.surface : scheme.surfaceContainerHighest;
    final border = enabled ? scheme.outlineVariant : scheme.outlineVariant;

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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: scheme.primary.withAlpha(18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icon, color: scheme.primary),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
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
