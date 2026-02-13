import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'cart_scope.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final sb = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _redirectToLogin(GoRouter router) {
    // Conserve l’historique: push, pas go
    router.push('/login?next=/checkout');
  }

  Future<void> _pay() async {
    // CAPTURE AVANT async gaps => pas de use_build_context_synchronously
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final cart = CartScope.of(context);

    if (cart.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Panier vide.')));
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final user = sb.auth.currentUser;
    if (user == null) {
      messenger.showSnackBar(const SnackBar(content: Text("Connecte-toi d'abord pour payer.")));
      _redirectToLogin(router);
      return;
    }

    setState(() => _loading = true);

    try {
      final businessId = cart.businessId!;
      final total = cart.subtotal;

      // 1) Créer service_request
      final reqRow = await sb.from('service_requests').insert({
        'business_id': businessId,
        'customer_user_id': user.id,
        'type': 'catalog',
        'status': 'new',
        'total_estimate': total,
        'currency': cart.currency,
        'address_text': _addressCtrl.text.trim(),
        'notes':
            'Commande depuis mini-site • Nom=${_nameCtrl.text.trim()} • Tel=${_phoneCtrl.text.trim()}',
      }).select('id').single();

      final requestId = reqRow['id'] as String;

      // 2) Créer service_request_items
      final itemsPayload = cart.items.map((it) {
        return {
          'request_id': requestId,
          'product_id': it.productId.split('::').first,
          'title_snapshot': it.title,
          'qty': it.qty,
          'unit_price_snapshot': it.unitPrice,
        };
      }).toList();

      await sb.from('service_request_items').insert(itemsPayload);

      // 3) Appeler Edge Function paiement (nom = dossier de la function)
      final res = await sb.functions.invoke(
        'create_payment_intent',
        body: {
          'request_id': requestId,
          'provider': 'PAYDUNYA',
          // 'amount': total, // optionnel (ta function accepte amount)
        },
      );

      final data = res.data;
      final url = (data is Map) ? (data['payment_url'] as String?) : null;
      if (url == null || url.isEmpty) {
        throw Exception('Aucune URL de paiement retournée.');
      }

      messenger.showSnackBar(const SnackBar(content: Text('Redirection vers paiement...')));

      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        throw Exception("Impossible d'ouvrir l'URL de paiement.");
      }

      cart.clear();

      if (!mounted) return;
      router.pop(); // retour panier
    } on PostgrestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur commande: ${e.message}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = CartScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Finaliser la commande')),
      body: AnimatedBuilder(
        animation: cart,
        builder: (context, child) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  Text(
                    'Total: ${cart.subtotal} ${cart.currency}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nom complet'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Téléphone'),
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Téléphone requis' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _addressCtrl,
                    decoration: const InputDecoration(labelText: 'Adresse complète'),
                    maxLines: 2,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Adresse requise' : null,
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _pay,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.payment),
                    label: Text(_loading ? 'Traitement...' : 'Procéder au paiement'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Note: si la boutique n'a pas l'autorisation de recevoir des commandes (entitlements), la création de commande peut être bloquée par RLS.",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
