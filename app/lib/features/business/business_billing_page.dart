import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BusinessBillingPage extends StatefulWidget {
  final String businessId;
  const BusinessBillingPage({super.key, required this.businessId});

  @override
  State<BusinessBillingPage> createState() => _BusinessBillingPageState();
}

class _BusinessBillingPageState extends State<BusinessBillingPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _ent;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ent = await _sb
          .from('entitlements')
          .select('can_receive_orders, can_run_ads, visibility_multiplier, plans:plans(code,name)')
          .eq('business_id', widget.businessId)
          .single();

      _ent = Map<String, dynamic>.from(ent as Map);
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
    final planCode = _ent?['plans']?['code']?.toString() ?? 'free';
    final planName = _ent?['plans']?['name']?.toString() ?? 'Free';
    final canOrders = _ent?['can_receive_orders'] == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monétisation'),
        actions: [
          IconButton(onPressed: _load, tooltip: 'Rafraîchir', icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Colors.red))))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: ListView(
                    children: [
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.workspace_premium),
                          title: Text('Plan actuel: $planName'),
                          subtitle: Text('Code: $planCode'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: ListTile(
                          leading: Icon(canOrders ? Icons.check_circle : Icons.lock),
                          title: const Text('Réception des commandes'),
                          subtitle: Text(canOrders ? 'Activée' : 'Désactivée (plan requis)'),
                        ),
                      ),
                      const SizedBox(height: 12),

                      const Text(
                        'Étape suivante (pro)',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Ici on branchera le paiement d’abonnement (Stripe / Mobile Money) + la mise à jour des entitlements côté serveur.",
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Paiement abonnement: étape suivante')),
                          );
                        },
                        icon: const Icon(Icons.payments),
                        label: const Text('Activer via paiement (à implémenter)'),
                      ),
                    ],
                  ),
                ),
    );
  }
}
