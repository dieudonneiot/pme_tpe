import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/app_back_button.dart';

class BusinessInventoryPage extends StatefulWidget {
  final String businessId;
  const BusinessInventoryPage({super.key, required this.businessId});

  @override
  State<BusinessInventoryPage> createState() => _BusinessInventoryPageState();
}

class _BusinessInventoryPageState extends State<BusinessInventoryPage> {
  bool _loading = true;
  String? _error;

  String _query = '';
  bool _onlyLow = false;

  List<Map<String, dynamic>> _rows = [];
  final Map<String, int> _onHandByVariant = {};
  bool _lowStockEnabled = false;

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

      // 1) Fetch products for this business (needed to filter inventory_on_hand by product_id)
      final products = await sb
          .from('products')
          .select('id,title')
          .eq('business_id', widget.businessId)
          .order('created_at', ascending: false);

      final productList =
          (products as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final productIds = productList.map((p) => p['id'].toString()).where((s) => s.isNotEmpty).toList();
      final productTitleById = {for (final p in productList) p['id'].toString(): (p['title'] ?? '').toString()};

      if (productIds.isEmpty) {
        _rows = [];
        _onHandByVariant.clear();
        return;
      }

      // 2) Fetch variants + basic fields (try to include low_stock_threshold if it exists)
      List<Map<String, dynamic>> variants;
      try {
        final v = await sb
            .from('product_variants')
            .select('id,product_id,title,sku,is_active,price_amount,currency,low_stock_threshold,created_at')
            .inFilter('product_id', productIds)
            .order('created_at', ascending: false);
        variants = (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _lowStockEnabled = variants.isNotEmpty && variants.first.containsKey('low_stock_threshold');
      } on PostgrestException catch (e) {
        if (e.message.toLowerCase().contains('low_stock_threshold')) {
          final v = await sb
              .from('product_variants')
              .select('id,product_id,title,sku,is_active,price_amount,currency,created_at')
              .inFilter('product_id', productIds)
              .order('created_at', ascending: false);
          variants = (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _lowStockEnabled = false;
        } else {
          rethrow;
        }
      }

      // 3) Fetch on-hand quantities from the view
      final inv = await sb
          .from('inventory_on_hand')
          .select('variant_id,on_hand,product_id')
          .inFilter('product_id', productIds);

      _onHandByVariant
        ..clear()
        ..addAll({
          for (final r in (inv as List))
            (r as Map)['variant_id'].toString(): ((r)['on_hand'] as num?)?.toInt() ?? 0
        });

      // 4) Merge: add product title
      _rows = variants
          .map((v) {
            final pid = v['product_id']?.toString() ?? '';
            return {
              ...v,
              'product_title': productTitleById[pid] ?? '',
            };
          })
          .toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
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
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DB: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      deltaCtrl.dispose();
      reasonCtrl.dispose();
    }
  }

  List<Map<String, dynamic>> _filtered() {
    final q = _query.trim().toLowerCase();

    bool match(Map<String, dynamic> r) {
      if (q.isNotEmpty) {
        final s = '${r['product_title'] ?? ''} ${r['title'] ?? ''} ${r['sku'] ?? ''}'.toLowerCase();
        if (!s.contains(q)) return false;
      }

      if (_onlyLow && _lowStockEnabled) {
        final id = r['id']?.toString() ?? '';
        final onHand = _onHandByVariant[id] ?? 0;
        final thr = (r['low_stock_threshold'] is num)
            ? (r['low_stock_threshold'] as num).toInt()
            : int.tryParse(r['low_stock_threshold']?.toString() ?? '') ?? 0;
        if (thr <= 0) return false;
        if (onHand > thr) return false;
      }

      return true;
    }

    return _rows.where(match).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered();

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Stock (B2)'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              onChanged: (v) => setState(() => _query = v),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search),
                                hintText: 'Produit, variante ou SKU…',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilterChip(
                            label: const Text('Low'),
                            selected: _onlyLow,
                            onSelected: _lowStockEnabled ? (v) => setState(() => _onlyLow = v) : null,
                            tooltip: _lowStockEnabled
                                ? 'Afficher uniquement les stocks bas'
                                : 'Exécute `variant_low_stock_threshold.sql` pour activer',
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: rows.isEmpty
                          ? const Center(child: Text('Aucune ligne à afficher.'))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              itemCount: rows.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final r = rows[i];
                                final id = r['id']?.toString() ?? '';
                                final pid = r['product_id']?.toString() ?? '';

                                final productTitle = (r['product_title'] ?? '').toString();
                                final title = (r['title'] ?? '').toString();
                                final sku = (r['sku'] ?? '').toString();
                                final active = r['is_active'] == true;
                                final onHand = _onHandByVariant[id] ?? 0;

                                final thr = _lowStockEnabled
                                    ? ((r['low_stock_threshold'] is num)
                                        ? (r['low_stock_threshold'] as num).toInt()
                                        : int.tryParse(r['low_stock_threshold']?.toString() ?? '') ?? 0)
                                    : 0;

                                final low = _lowStockEnabled && thr > 0 && onHand <= thr;
                                final color = onHand <= 0
                                    ? Colors.red
                                    : (low ? Colors.orange : Colors.green);

                                return Card(
                                  child: ListTile(
                                    onTap: () {
                                      if (pid.isEmpty) return;
                                      context.push('/business/${widget.businessId}/products/$pid');
                                    },
                                    leading: CircleAvatar(
                                      backgroundColor: color.withValues(alpha: 0.15),
                                      child: Text(
                                        '$onHand',
                                        style: TextStyle(color: color, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                    title: Text('$productTitle — $title'),
                                    subtitle: Text(
                                      [
                                        if (sku.isNotEmpty) 'SKU: $sku',
                                        if (!active) 'Inactif',
                                        if (_lowStockEnabled && thr > 0) 'Seuil: $thr',
                                        if (low) 'Stock bas',
                                      ].join(' • '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Ajuster stock',
                                      onPressed: id.isEmpty ? null : () => _adjustStock(id),
                                      icon: const Icon(Icons.inventory_2_outlined),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
