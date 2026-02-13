import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class OrderProductPage extends StatefulWidget {
  final String productId;
  const OrderProductPage({super.key, required this.productId});

  @override
  State<OrderProductPage> createState() => _OrderProductPageState();
}

class _OrderProductPageState extends State<OrderProductPage> {
  final sb = Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _product;

  @override
  void initState() {
    super.initState();
    _loadProduct();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProduct() async {
    setState(() {
      _error = null;
      _product = null;
    });

    try {
      final row = await sb
          .from('products')
          .select('id, title, price_amount, business_id')
          .eq('id', widget.productId)
          .single();

      if (!mounted) return;
      setState(() => _product = Map<String, dynamic>.from(row as Map));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _submit() async {
    // Capture tout ce qui dépend de context AVANT le premier await (lint OK)
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final session = sb.auth.currentSession;
    if (session == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Connecte-toi d'abord pour commander.")),
      );
      router.push('/login');
      return;
    }

    if (_product == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Produit indisponible. Réessaie.")),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final userId = session.user.id;
      final p = _product!;

      final priceNum = (p['price_amount'] as num?) ?? 0;
      final amount = priceNum.toDouble();

      // 1) Créer la request (status 'new' + total_estimate)
      final req = await sb
          .from('service_requests')
          .insert({
            'business_id': p['business_id'],
            'customer_user_id': userId,
            'type': 'catalog',
            'status': 'new',
            'notes':
                "Commande produit: ${p['title']} | Client: ${_nameCtrl.text.trim()} | Tel: ${_phoneCtrl.text.trim()}",
            'address_text': _addressCtrl.text.trim(),
            'total_estimate': amount,
            'currency': 'XOF',
          })
          .select('id')
          .single();

      final requestId = (req as Map)['id'];

      // 2) Créer l’item (unit_price_snapshot + title_snapshot)
      await sb.from('service_request_items').insert({
        'request_id': requestId,
        'product_id': p['id'],
        'title_snapshot': (p['title'] ?? '').toString(),
        'qty': 1,
        'unit_price_snapshot': amount,
      });

      // 3) Appeler l’Edge Function
      // IMPORTANT: le nom ici = nom du dossier de fonction.
      // Si ton dossier est supabase/functions/create_payment_intent => invoke('create_payment_intent')
      final res = await sb.functions.invoke(
        'create_payment_intent',
        body: {
          'request_id': requestId,
          'provider': 'PAYDUNYA',
          // 'amount': amount, // optionnel (si tu veux forcer)
        },
      );

      final data = res.data;
      final paymentUrl = (data is Map) ? data['payment_url'] : null;

      if (paymentUrl == null || paymentUrl.toString().isEmpty) {
        throw Exception("payment_url absent dans la réponse: $data");
      }

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Redirection vers paiement...')),
      );

      final ok = await launchUrl(
        Uri.parse(paymentUrl.toString()),
        mode: LaunchMode.externalApplication,
      );

      if (!ok) {
        throw Exception("Impossible d'ouvrir l'URL de paiement.");
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;

    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Commander')),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
        ),
      );
    }

    final title = (p['title'] ?? '').toString();
    final price = (p['price_amount'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: Text('Commander $title')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text('$price XOF', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),

              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom complet'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
                textInputAction: TextInputAction.next,
              ),
              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: 'Téléphone'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Téléphone requis' : null,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
              ),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(labelText: 'Adresse complète'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Adresse requise' : null,
                minLines: 2,
                maxLines: 4,
              ),

              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loading ? null : _submit,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.payment),
                label: Text(_loading ? 'Traitement...' : 'Procéder au paiement'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
