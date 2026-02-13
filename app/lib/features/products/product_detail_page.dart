import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductDetailPage extends StatefulWidget {
  final String businessId;
  final String productId;
  const ProductDetailPage({super.key, required this.businessId, required this.productId});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _product;
  List<Map<String, dynamic>> _variants = [];
  Map<String, int> _onHandByVariant = {};
  List<Map<String, dynamic>> _categories = [];
  Set<String> _selectedCategoryIds = {};

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

      final p = await sb
          .from('products')
          .select('id,business_id,title,description,price_amount,currency,is_active')
          .eq('id', widget.productId)
          .single();

      _product = Map<String, dynamic>.from(p as Map);

      final v = await sb
          .from('product_variants')
          .select('id,title,sku,options,price_amount,currency,is_active,created_at')
          .eq('product_id', widget.productId)
          .order('created_at', ascending: false);

      _variants = (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final oh = await sb
          .from('inventory_on_hand')
          .select('variant_id,on_hand')
          .eq('product_id', widget.productId);

      _onHandByVariant = {
        for (final r in (oh as List))
          (r as Map)['variant_id'].toString(): ((r)['on_hand'] as num?)?.toInt() ?? 0
      };

      final cats = await sb.from('categories').select('id,name').order('name');
      _categories = (cats as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final pcm = await sb
          .from('product_categories_map')
          .select('category_id')
          .eq('product_id', widget.productId);

      _selectedCategoryIds = (pcm as List)
          .map((e) => (e as Map)['category_id'].toString())
          .toSet();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _toggleActive(bool v) async {
    try {
      final sb = Supabase.instance.client;
      await sb.from('products').update({'is_active': v}).eq('id', widget.productId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _editProduct() async {
    final titleCtrl = TextEditingController(text: _product?['title']?.toString() ?? '');
    final descCtrl = TextEditingController(text: _product?['description']?.toString() ?? '');
    final priceCtrl = TextEditingController(text: _product?['price_amount']?.toString() ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Modifier produit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Titre')),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
            TextField(
              controller: priceCtrl,
              decoration: const InputDecoration(labelText: 'Prix (optionnel)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enregistrer')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final sb = Supabase.instance.client;
      final price = num.tryParse(priceCtrl.text.trim());
      await sb.from('products').update({
        'title': titleCtrl.text.trim(),
        'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        'price_amount': price,
      }).eq('id', widget.productId);

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      titleCtrl.dispose();
      descCtrl.dispose();
      priceCtrl.dispose();
    }
  }

  Future<void> _editCategories() async {
    final temp = Set<String>.from(_selectedCategoryIds);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Catégories'),
        content: SizedBox(
          width: 420,
          height: 420,
          child: ListView(
            children: _categories.map((c) {
              final id = c['id'].toString();
              final name = c['name'].toString();
              final checked = temp.contains(id);
              return CheckboxListTile(
                value: checked,
                title: Text(name),
                onChanged: (v) {
                  if (v == true) {
                    temp.add(id);
                  } else {
                    temp.remove(id);
                  }
                  (context as Element).markNeedsBuild();
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enregistrer')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final sb = Supabase.instance.client;

      // supprimer celles retirées
      final toDelete = _selectedCategoryIds.difference(temp);
      for (final id in toDelete) {
        await sb
            .from('product_categories_map')
            .delete()
            .eq('product_id', widget.productId)
            .eq('category_id', id);
      }

      // ajouter celles ajoutées
      final toAdd = temp.difference(_selectedCategoryIds);
      if (toAdd.isNotEmpty) {
        await sb.from('product_categories_map').insert(
          toAdd.map((id) => {'product_id': widget.productId, 'category_id': id}).toList(),
        );
      }

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _addVariant() async {
    final titleCtrl = TextEditingController();
    final skuCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nouvelle variante'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Titre')),
            TextField(controller: skuCtrl, decoration: const InputDecoration(labelText: 'SKU (optionnel)')),
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

      final sb = Supabase.instance.client;
      final price = num.tryParse(priceCtrl.text.trim());

      await sb.from('product_variants').insert({
        'product_id': widget.productId,
        'title': title,
        'sku': skuCtrl.text.trim().isEmpty ? null : skuCtrl.text.trim(),
        'price_amount': price,
        'currency': 'XOF',
        'is_active': true,
        'options': {},
      });

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      titleCtrl.dispose();
      skuCtrl.dispose();
      priceCtrl.dispose();
    }
  }

  Future<void> _adjustStock(String variantId) async {
    final deltaCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ajuster stock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: deltaCtrl,
              decoration: const InputDecoration(labelText: 'Delta (ex: 5 ou -2)'),
              keyboardType: TextInputType.number,
            ),
            TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Raison (optionnel)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enregistrer')),
        ],
      ),
    );

    if (ok != true) return;

    final delta = int.tryParse(deltaCtrl.text.trim());
    if (delta == null || delta == 0) return;

    try {
      final sb = Supabase.instance.client;
      final user = sb.auth.currentUser;
      if (user == null) throw Exception('Session manquante.');

      await sb.from('inventory_movements').insert({
        'variant_id': variantId,
        'delta_qty': delta,
        'reason': reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
        'created_by': user.id,
      });

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      deltaCtrl.dispose();
      reasonCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;

    return Scaffold(
      appBar: AppBar(
        title: Text(p?['title']?.toString() ?? 'Produit'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _editProduct, icon: const Icon(Icons.edit)),
          IconButton(onPressed: _editCategories, icon: const Icon(Icons.category)),
          IconButton(onPressed: _addVariant, icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : p == null
                  ? const Center(child: Text('Produit introuvable'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p['title']?.toString() ?? '',
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 6),
                                      Text(p['description']?.toString() ?? ''),
                                      const SizedBox(height: 8),
                                      Text('Prix: ${p['price_amount'] ?? '-'} ${p['currency'] ?? 'XOF'}'),
                                    ],
                                  ),
                                ),
                                Column(
                                  children: [
                                    const Text('Actif'),
                                    Switch(
                                      value: p['is_active'] == true,
                                      onChanged: _toggleActive,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),
                        const Text('Variantes & Stock', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),

                        if (_variants.isEmpty)
                          const Text('Aucune variante. Clique + pour en créer une.')
                        else
                          ..._variants.map((v) {
                            final vid = v['id'].toString();
                            final onHand = _onHandByVariant[vid] ?? 0;
                            return Card(
                              child: ListTile(
                                title: Text(v['title']?.toString() ?? ''),
                                subtitle: Text('SKU: ${v['sku'] ?? '-'} • Stock: $onHand'),
                                trailing: IconButton(
                                  tooltip: 'Ajuster stock',
                                  onPressed: () => _adjustStock(vid),
                                  icon: const Icon(Icons.inventory),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
    );
  }
}
