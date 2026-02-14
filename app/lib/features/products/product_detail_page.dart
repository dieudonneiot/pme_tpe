import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/app_back_button.dart';

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
  List<Map<String, dynamic>> _media = [];
  bool _variantLowStockEnabled = false;

  bool _uploadingMedia = false;
  final Set<String> _deletingMediaIds = {};

  static const _productMediaBucket = 'product_media';
  static const _maxUploadBytes = 20 * 1024 * 1024; // 20MB (safe for desktop memory)

  String? _primaryMediaId() => _product?['primary_media_id']?.toString();

  String _fmtDateTime(Object? v) {
    if (v == null) return '-';
    final s = v.toString();
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    String two(int n) => n.toString().padLeft(2, '0');
    final local = dt.toLocal();
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

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

      Map<String, dynamic> p;
      try {
        final row = await sb
            .from('products')
            .select('id,business_id,title,description,price_amount,currency,is_active,primary_media_id')
            .eq('id', widget.productId)
            .single();
        p = Map<String, dynamic>.from(row as Map);
      } on PostgrestException catch (e) {
        // Backward-compatible: column might not exist yet if migration wasn't run.
        if (e.message.toLowerCase().contains('primary_media_id')) {
          final row = await sb
              .from('products')
              .select('id,business_id,title,description,price_amount,currency,is_active')
              .eq('id', widget.productId)
              .single();
          p = Map<String, dynamic>.from(row as Map);
        } else {
          rethrow;
        }
      }

      _product = p;

      try {
        final v = await sb
            .from('product_variants')
            .select('id,title,sku,options,price_amount,currency,is_active,low_stock_threshold,created_at')
            .eq('product_id', widget.productId)
            .order('created_at', ascending: false);
        _variants = (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _variantLowStockEnabled = _variants.isNotEmpty && _variants.first.containsKey('low_stock_threshold');
      } on PostgrestException catch (e) {
        if (e.message.toLowerCase().contains('low_stock_threshold')) {
          final v = await sb
              .from('product_variants')
              .select('id,title,sku,options,price_amount,currency,is_active,created_at')
              .eq('product_id', widget.productId)
              .order('created_at', ascending: false);
          _variants = (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _variantLowStockEnabled = false;
        } else {
          rethrow;
        }
      }

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

      try {
        final media = await sb
            .from('product_media')
            .select('id,media_type,storage_path,sort_order,created_at')
            .eq('product_id', widget.productId)
            .order('sort_order', ascending: true)
            .order('created_at', ascending: true);
        _media = (media as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } on PostgrestException catch (e) {
        // Backward-compatible: sort_order might not exist yet.
        if (e.message.toLowerCase().contains('sort_order')) {
          final media = await sb
              .from('product_media')
              .select('id,media_type,storage_path,created_at')
              .eq('product_id', widget.productId)
              .order('created_at', ascending: true);
          _media = (media as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } else {
          rethrow;
        }
      }
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
    String coverMediaId = '';

    String mediaLabel(Map<String, dynamic> m) {
      final type = (m['media_type'] ?? '').toString().toUpperCase();
      final path = (m['storage_path'] ?? '').toString();
      final file = path.isEmpty ? '' : path.split('/').last;
      return file.isEmpty ? type : '$type • $file';
    }

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
            const SizedBox(height: 10),
            if (_media.isNotEmpty)
              DropdownButtonFormField<String>(
                key: ValueKey('variant_cover_$coverMediaId'),
                initialValue: coverMediaId.isEmpty ? '' : coverMediaId,
                decoration: const InputDecoration(labelText: 'Photo/Vidéo (optionnel)'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Aucun')),
                  ..._media
                      .where((m) {
                        final t = (m['media_type'] ?? '').toString().toLowerCase();
                        return t == 'image' || t == 'video';
                      })
                      .map((m) {
                        final id = (m['id'] ?? '').toString();
                        return DropdownMenuItem(
                          value: id,
                          child: Text(mediaLabel(m), overflow: TextOverflow.ellipsis),
                        );
                      }),
                ],
                onChanged: (v) => coverMediaId = (v ?? ''),
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
        'options': coverMediaId.isEmpty ? {} : {'cover_media_id': coverMediaId},
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

  Future<void> _toggleVariantActive(String variantId, bool active) async {
    try {
      final sb = Supabase.instance.client;
      await sb.from('product_variants').update({'is_active': active}).eq('id', variantId);
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DB: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _editVariant(Map<String, dynamic> v) async {
    final id = v['id']?.toString() ?? '';
    if (id.isEmpty) return;

    final existingOptions = v['options'];
    final options = existingOptions is Map ? Map<String, dynamic>.from(existingOptions) : <String, dynamic>{};
    String coverMediaId = (options['cover_media_id'] ?? '').toString();

    String mediaLabel(Map<String, dynamic> m) {
      final type = (m['media_type'] ?? '').toString().toUpperCase();
      final path = (m['storage_path'] ?? '').toString();
      final file = path.isEmpty ? '' : path.split('/').last;
      return file.isEmpty ? type : '$type • $file';
    }

    final titleCtrl = TextEditingController(text: v['title']?.toString() ?? '');
    final skuCtrl = TextEditingController(text: v['sku']?.toString() ?? '');
    final priceCtrl = TextEditingController(text: v['price_amount']?.toString() ?? '');
    final lowCtrl = TextEditingController(
      text: _variantLowStockEnabled ? (v['low_stock_threshold']?.toString() ?? '0') : '',
    );
    bool isActive = v['is_active'] == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Modifier variante'),
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
              const SizedBox(height: 10),
              if (_media.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey('variant_cover_edit_$coverMediaId'),
                  initialValue: coverMediaId.isEmpty ? '' : coverMediaId,
                  decoration: const InputDecoration(labelText: 'Photo/Vidéo (optionnel)'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Aucun')),
                    ..._media
                        .where((m) {
                          final t = (m['media_type'] ?? '').toString().toLowerCase();
                          return t == 'image' || t == 'video';
                        })
                        .map((m) {
                          final mid = (m['id'] ?? '').toString();
                          return DropdownMenuItem(
                            value: mid,
                            child: Text(mediaLabel(m), overflow: TextOverflow.ellipsis),
                          );
                        }),
                  ],
                  onChanged: (v) => setState(() => coverMediaId = (v ?? '')),
                ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: isActive,
                onChanged: (x) => setState(() => isActive = x),
                title: const Text('Variante active'),
              ),
              if (_variantLowStockEnabled) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: lowCtrl,
                  decoration: const InputDecoration(labelText: 'Seuil stock bas (0 = désactivé)'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );

    if (ok != true) return;

    try {
      final sb = Supabase.instance.client;
      final title = titleCtrl.text.trim();
      if (title.isEmpty) return;

      final price = num.tryParse(priceCtrl.text.trim());
      final update = <String, dynamic>{
        'title': title,
        'sku': skuCtrl.text.trim().isEmpty ? null : skuCtrl.text.trim(),
        'price_amount': price,
        'is_active': isActive,
        'options': coverMediaId.isEmpty
            ? (options..remove('cover_media_id'))
            : (options..['cover_media_id'] = coverMediaId),
      };

      if (_variantLowStockEnabled) {
        final thr = int.tryParse(lowCtrl.text.trim()) ?? 0;
        update['low_stock_threshold'] = thr < 0 ? 0 : thr;
      }

      try {
        await sb.from('product_variants').update(update).eq('id', id);
      } on PostgrestException catch (e) {
        // Backward-compatible: column might not exist yet.
        if (_variantLowStockEnabled && e.message.toLowerCase().contains('low_stock_threshold')) {
          update.remove('low_stock_threshold');
          await sb.from('product_variants').update(update).eq('id', id);
        } else {
          rethrow;
        }
      }

      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DB: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      titleCtrl.dispose();
      skuCtrl.dispose();
      priceCtrl.dispose();
      lowCtrl.dispose();
    }
  }

  Future<void> _deleteVariant(String variantId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer variante ?'),
        content: const Text(
          'Si cette variante a un historique de stock (mouvements), la suppression peut être bloquée. '
          'Dans ce cas, désactive-la plutôt.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final sb = Supabase.instance.client;
      await sb.from('product_variants').delete().eq('id', variantId);
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Suppression impossible: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _showStockHistory({required String variantId, required String title}) async {
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, scrollController) => FutureBuilder(
          future: () async {
            final sb = Supabase.instance.client;
            final rows = await sb
                .from('inventory_movements')
                .select('id,delta_qty,reason,created_by,created_at')
                .eq('variant_id', variantId)
                .order('created_at', ascending: false)
                .limit(50);
            return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          }(),
          builder: (context, snap) {
            final onHand = _onHandByVariant[variantId] ?? 0;
            final rows = snap.data ?? const <Map<String, dynamic>>[];

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text('Stock actuel: $onHand', style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 12),
                  if (snap.connectionState != ConnectionState.done)
                    const Expanded(child: Center(child: CircularProgressIndicator()))
                  else if (snap.hasError)
                    Expanded(child: Center(child: Text('${snap.error}', style: const TextStyle(color: Colors.red))))
                  else if (rows.isEmpty)
                    const Expanded(child: Center(child: Text('Aucun mouvement enregistré.')))
                  else
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = rows[i];
                          final delta = (r['delta_qty'] as num?)?.toInt() ?? 0;
                          final reason = (r['reason'] ?? '').toString();
                          final by = (r['created_by'] ?? '').toString();
                          final at = _fmtDateTime(r['created_at']);
                          final color = delta > 0 ? Colors.green : Colors.red;
                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                delta > 0 ? '+$delta' : '$delta',
                                style: TextStyle(color: color, fontWeight: FontWeight.w800),
                              ),
                            ),
                            title: Text(reason.isEmpty ? '—' : reason),
                            subtitle: Text('$at • $by'),
                            trailing: IconButton(
                              tooltip: 'Copier user id',
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: by));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copié.')));
                              },
                              icon: const Icon(Icons.copy),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------------- MEDIA MANAGEMENT ----------------

  String _randToken([int length = 6]) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  String _contentTypeFromExt(String ext) {
    final e = ext.toLowerCase();
    if (e == 'png') return 'image/png';
    if (e == 'jpg' || e == 'jpeg') return 'image/jpeg';
    if (e == 'webp') return 'image/webp';
    if (e == 'mp4') return 'video/mp4';
    if (e == 'webm') return 'video/webm';
    if (e == 'mov') return 'video/quicktime';
    if (e == 'pdf') return 'application/pdf';
    return 'application/octet-stream';
  }

  String? _mediaTypeFromExt(String ext) {
    final e = ext.toLowerCase();
    if (['png', 'jpg', 'jpeg', 'webp'].contains(e)) return 'image';
    if (['mp4', 'webm', 'mov'].contains(e)) return 'video';
    if (e == 'pdf') return 'pdf';
    return null;
  }

  Future<void> _addMedia() async {
    if (_uploadingMedia) return;

    setState(() {
      _uploadingMedia = true;
    });

    try {
      final sb = Supabase.instance.client;
      if (sb.auth.currentSession == null) {
        throw Exception('Session manquante. Reconnecte-toi.');
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'mp4', 'webm', 'mov', 'pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.size > _maxUploadBytes) {
        throw Exception(
          'Fichier trop volumineux (${(file.size / (1024 * 1024)).toStringAsFixed(1)} MB). '
          'Max: ${(_maxUploadBytes / (1024 * 1024)).toInt()} MB.',
        );
      }

      final ext = (file.extension ?? '').toLowerCase();
      final mediaType = _mediaTypeFromExt(ext);
      if (mediaType == null) {
        throw Exception('Type de fichier non supporté: .$ext');
      }

      // UX rules (pro): limit images/videos per product.
      final imageCount =
          _media.where((m) => (m['media_type'] ?? '').toString().toLowerCase() == 'image').length;
      final videoCount =
          _media.where((m) => (m['media_type'] ?? '').toString().toLowerCase() == 'video').length;
      if (mediaType == 'image' && imageCount >= 3) {
        throw Exception('Max 3 photos par produit.');
      }
      if (mediaType == 'video' && videoCount >= 1) {
        throw Exception('Max 1 vidéo par produit.');
      }

      final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Impossible de lire le fichier.');
      }

      // IMPORTANT: storage path must start with "<business_uuid>/..." due to RLS policies.
      final objectPath =
          '${widget.businessId}/products/${widget.productId}/${DateTime.now().millisecondsSinceEpoch}_${_randToken()}.$ext';

      await sb.storage.from(_productMediaBucket).uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFromExt(ext),
            ),
          );

      try {
        final nextOrder = _media.fold<int>(0, (acc, m) {
          final v = m['sort_order'];
          final n = v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
          return max(acc, n + 1);
        });

        try {
          await sb.from('product_media').insert({
            'product_id': widget.productId,
            'media_type': mediaType,
            'storage_path': objectPath,
            'sort_order': nextOrder,
          });
        } on PostgrestException catch (e) {
          // Backward-compatible: sort_order might not exist yet.
          if (e.message.toLowerCase().contains('sort_order')) {
            await sb.from('product_media').insert({
              'product_id': widget.productId,
              'media_type': mediaType,
              'storage_path': objectPath,
            });
          } else {
            rethrow;
          }
        }
      } catch (e) {
        // Best-effort rollback (avoid orphaned storage file)
        await sb.storage.from(_productMediaBucket).remove([objectPath]);
        rethrow;
      }

      await _load();
    } on StorageException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Storage: ${e.message}')));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DB: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  Future<void> _deleteMedia(Map<String, dynamic> m) async {
    final id = m['id']?.toString() ?? '';
    final path = m['storage_path']?.toString() ?? '';
    if (id.isEmpty || path.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer média ?'),
        content: const Text('Cette action est définitive.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _deletingMediaIds.add(id));

    try {
      final sb = Supabase.instance.client;
      await sb.from('product_media').delete().eq('id', id);

      // If it was the cover, clear it (FK on delete would do it too, but keep UI consistent)
      if (_primaryMediaId() == id) {
        try {
          await sb.from('products').update({'primary_media_id': null}).eq('id', widget.productId);
        } catch (_) {
          // ignore (migration not applied yet / column missing)
        }
      }

      // If the storage_path is still referenced by another row (e.g. duplicated product reuses the same media),
      // do NOT delete the file.
      final refs = await sb.from('product_media').select('id').eq('storage_path', path).limit(1);
      final stillReferenced = (refs as List).isNotEmpty;
      if (!stillReferenced) {
        await sb.storage.from(_productMediaBucket).remove([path]);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Média partagé: pointeur supprimé, fichier conservé.')),
        );
      }

      await _load();
    } on StorageException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Storage: ${e.message}')));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DB: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      if (mounted) setState(() => _deletingMediaIds.remove(id));
    }
  }

  Future<void> _openMedia(Map<String, dynamic> m) async {
    final sb = Supabase.instance.client;
    final path = (m['storage_path'] ?? '').toString();
    if (path.isEmpty) return;

    final url = sb.storage.from(_productMediaBucket).getPublicUrl(path);
    final type = (m['media_type'] ?? '').toString().toLowerCase();

    if (type == 'image') {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    tooltip: 'Copier URL',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('URL copiée.')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d’ouvrir le lien.')));
    }
  }

  Future<void> _setCover(String mediaId) async {
    try {
      final sb = Supabase.instance.client;
      await sb.from('products').update({'primary_media_id': mediaId}).eq('id', widget.productId);
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DB: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _moveMedia(String mediaId, int delta) async {
    final i = _media.indexWhere((m) => m['id']?.toString() == mediaId);
    if (i == -1) return;
    final j = i + delta;
    if (j < 0 || j >= _media.length) return;

    final a = _media[i];
    final b = _media[j];

    final aId = a['id']?.toString() ?? '';
    final bId = b['id']?.toString() ?? '';
    if (aId.isEmpty || bId.isEmpty) return;

    final aOrder = (a['sort_order'] is num)
        ? (a['sort_order'] as num).toInt()
        : int.tryParse(a['sort_order']?.toString() ?? '') ?? i;
    final bOrder = (b['sort_order'] is num)
        ? (b['sort_order'] as num).toInt()
        : int.tryParse(b['sort_order']?.toString() ?? '') ?? j;

    try {
      final sb = Supabase.instance.client;
      await sb.from('product_media').update({'sort_order': bOrder}).eq('id', aId);
      await sb.from('product_media').update({'sort_order': aOrder}).eq('id', bId);
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DB: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Widget _mediaSection() {
    final sb = Supabase.instance.client;
    final primaryId = _primaryMediaId();
    final coverEnabled = _product?.containsKey('primary_media_id') == true;
    final orderingEnabled = _media.isNotEmpty && _media.first.containsKey('sort_order');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Médias',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: _uploadingMedia ? null : _addMedia,
                  icon: _uploadingMedia
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Ajouter'),
                ),
              ],
            ),
            if (!coverEnabled || !orderingEnabled)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Astuce: exécute `app/_supabase_sql/product_media_cover_ordering.sql` pour activer Couverture + Ordre.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 8),
            if (_media.isEmpty)
              const Text(
                'Ajoute des photos/vidéos/PDF pour rendre le produit plus attractif.',
                style: TextStyle(color: Colors.black54),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final crossAxisCount = w >= 900 ? 5 : (w >= 600 ? 4 : 3);
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _media.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (context, i) {
                      final m = _media[i];
                      final id = m['id']?.toString() ?? '';
                      final type = (m['media_type'] ?? '').toString().toLowerCase();
                      final path = (m['storage_path'] ?? '').toString();
                      final url = path.isEmpty ? null : sb.storage.from(_productMediaBucket).getPublicUrl(path);
                      final deleting = id.isNotEmpty && _deletingMediaIds.contains(id);
                      final isCover = primaryId != null && primaryId.isNotEmpty && primaryId == id;

                      Widget preview;
                      if (type == 'image' && url != null) {
                        preview = Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                          },
                        );
                      } else if (type == 'video') {
                        preview = const Center(
                          child: Icon(Icons.videocam_outlined, size: 32),
                        );
                      } else if (type == 'pdf') {
                        preview = const Center(
                          child: Icon(Icons.picture_as_pdf_outlined, size: 32),
                        );
                      } else {
                        preview = const Center(child: Icon(Icons.insert_drive_file_outlined, size: 32));
                      }

                      return InkWell(
                        onTap: deleting ? null : () => _openMedia(m),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  color: Colors.black12,
                                  child: preview,
                                ),
                              ),
                            ),
                            if (type.isNotEmpty)
                              Positioned(
                                left: 8,
                                bottom: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    type.toUpperCase(),
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                  ),
                                ),
                              ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: deleting
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : PopupMenuButton<String>(
                                      tooltip: 'Actions',
                                      onSelected: (v) async {
                                        if (v == 'cover') await _setCover(id);
                                        if (v == 'left') await _moveMedia(id, -1);
                                        if (v == 'right') await _moveMedia(id, 1);
                                        if (v == 'delete') await _deleteMedia(m);
                                      },
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                          value: 'cover',
                                          enabled: coverEnabled,
                                          child: Row(
                                            children: [
                                              Icon(isCover ? Icons.star : Icons.star_border),
                                              const SizedBox(width: 10),
                                              const Text('Définir couverture'),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'left',
                                          enabled: orderingEnabled,
                                          child: Row(
                                            children: [
                                              Icon(Icons.arrow_back_ios_new,
                                                  color: orderingEnabled ? null : Colors.black26),
                                              const SizedBox(width: 10),
                                              const Text('Déplacer avant'),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'right',
                                          enabled: orderingEnabled,
                                          child: Row(
                                            children: [
                                              Icon(Icons.arrow_forward_ios,
                                                  color: orderingEnabled ? null : Colors.black26),
                                              const SizedBox(width: 10),
                                              const Text('Déplacer après'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuDivider(),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete_outline),
                                              SizedBox(width: 10),
                                              Text('Supprimer'),
                                            ],
                                          ),
                                        ),
                                      ],
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(18),
                                        ),
                                        padding: const EdgeInsets.all(6),
                                        child: const Icon(Icons.more_horiz, color: Colors.white, size: 18),
                                      ),
                                    ),
                            ),
                            if (isCover)
                              Positioned(
                                top: 6,
                                left: 6,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade700,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  padding: const EdgeInsets.all(6),
                                  child: const Icon(Icons.star, color: Colors.white, size: 18),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;

    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(fallbackPath: '/business/${widget.businessId}/products'),
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
                        _mediaSection(),

                        const SizedBox(height: 12),
                        const Text('Variantes & Stock', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),

                        if (_variants.isEmpty)
                          const Text('Aucune variante. Clique + pour en créer une.')
                        else
                          ..._variants.map((v) {
                            final sb = Supabase.instance.client;
                            final vid = v['id'].toString();
                            final onHand = _onHandByVariant[vid] ?? 0;
                            final active = v['is_active'] == true;
                            final title = v['title']?.toString() ?? '';
                            final sku = v['sku']?.toString();
                            final price = (v['price_amount'] ?? _product?['price_amount']);
                            final cur = (v['currency'] ?? _product?['currency'] ?? 'XOF').toString();

                            final optRaw = v['options'];
                            final opt = optRaw is Map ? Map<String, dynamic>.from(optRaw) : <String, dynamic>{};
                            final coverId = (opt['cover_media_id'] ?? '').toString();
                            String? coverUrl;
                            String coverType = '';
                            if (coverId.isNotEmpty) {
                              for (final m in _media) {
                                if ((m['id'] ?? '').toString() == coverId) {
                                  coverType = (m['media_type'] ?? '').toString().toLowerCase();
                                  final path = (m['storage_path'] ?? '').toString();
                                  if (coverType == 'image' && path.isNotEmpty) {
                                    coverUrl = sb.storage.from(_productMediaBucket).getPublicUrl(path);
                                  }
                                  break;
                                }
                              }
                            }

                            final thr = _variantLowStockEnabled
                                ? ((v['low_stock_threshold'] is num)
                                    ? (v['low_stock_threshold'] as num).toInt()
                                    : int.tryParse(v['low_stock_threshold']?.toString() ?? '') ?? 0)
                                : 0;
                            final low = _variantLowStockEnabled && thr > 0 && onHand <= thr;
                            final stockColor = onHand <= 0 ? Colors.red : (low ? Colors.orange : Colors.green);
                            return Card(
                              child: ListTile(
                                onTap: () => _editVariant(v),
                                leading: SizedBox(
                                  width: 54,
                                  height: 54,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(14),
                                          child: Container(
                                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                            child: coverUrl == null
                                                ? Icon(
                                                    coverType == 'video'
                                                        ? Icons.videocam_outlined
                                                        : Icons.image_outlined,
                                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                  )
                                                : Image.network(
                                                    coverUrl,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (context, error, stackTrace) => Icon(
                                                      Icons.broken_image_outlined,
                                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        right: 4,
                                        bottom: 4,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: stockColor.withAlpha(28),
                                            borderRadius: BorderRadius.circular(999),
                                            border: Border.all(color: stockColor.withAlpha(90)),
                                          ),
                                          child: Text(
                                            '$onHand',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: stockColor,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(child: Text(title)),
                                    if (!active)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black12,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: const Text('Inactif', style: TextStyle(fontSize: 12)),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  [
                                    'SKU: ${sku == null || sku.isEmpty ? '-' : sku}',
                                    'Prix: ${price ?? '-'} $cur',
                                    if (_variantLowStockEnabled && thr > 0) 'Seuil: $thr',
                                    'Stock: $onHand',
                                    if (low) 'Stock bas',
                                  ].join(' • '),
                                ),
                                trailing: Wrap(
                                  spacing: 6,
                                  children: [
                                    IconButton(
                                      tooltip: 'Ajuster stock',
                                      onPressed: () => _adjustStock(vid),
                                      icon: const Icon(Icons.inventory_2_outlined),
                                    ),
                                    IconButton(
                                      tooltip: 'Historique stock',
                                      onPressed: () => _showStockHistory(variantId: vid, title: title),
                                      icon: const Icon(Icons.history),
                                    ),
                                    PopupMenuButton<String>(
                                      tooltip: 'Actions',
                                      onSelected: (action) async {
                                        if (action == 'edit') await _editVariant(v);
                                        if (action == 'toggle') await _toggleVariantActive(vid, !active);
                                        if (action == 'delete') await _deleteVariant(vid);
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit_outlined),
                                              SizedBox(width: 10),
                                              Text('Modifier'),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'toggle',
                                          child: Row(
                                            children: [
                                              Icon(active ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                              SizedBox(width: 10),
                                              Text(active ? 'Désactiver' : 'Activer'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuDivider(),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete_outline),
                                              SizedBox(width: 10),
                                              Text('Supprimer'),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
    );
  }
}
