import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BusinessProductsPage extends StatefulWidget {
  final String businessId;
  const BusinessProductsPage({super.key, required this.businessId});

  @override
  State<BusinessProductsPage> createState() => _BusinessProductsPageState();
}

class _BusinessProductsPageState extends State<BusinessProductsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _products = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sb = Supabase.instance.client;
      final rows = await sb
          .from('products')
          .select('id,title,price_amount,currency,is_active,created_at')
          .eq('business_id', widget.businessId)
          .order('created_at', ascending: false);

      _products = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createProduct() async {
    final titleCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nouveau produit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Titre')),
            TextField(
              controller: priceCtrl,
              decoration: const InputDecoration(labelText: 'Prix (optionnel)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Créer')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final title = titleCtrl.text.trim();
      if (title.isEmpty) return;

      final price = num.tryParse(priceCtrl.text.trim());
      final sb = Supabase.instance.client;
      await sb.from('products').insert({
        'business_id': widget.businessId,
        'title': title,
        'price_amount': price,
        'currency': 'XOF',
        'is_active': true,
      });

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      titleCtrl.dispose();
      priceCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produits (B2)'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _createProduct, icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _products.map((p) {
                    final price = p['price_amount'];
                    final cur = p['currency']?.toString() ?? 'XOF';
                    final active = p['is_active'] == true;
                    return Card(
                      child: ListTile(
                        title: Text(p['title']?.toString() ?? ''),
                        subtitle: Text(active ? 'Actif' : 'Inactif'),
                        trailing: Text(price == null ? '' : '$price $cur'),
                        onTap: () => context.push('/business/${widget.businessId}/products/${p['id']}'),
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}
