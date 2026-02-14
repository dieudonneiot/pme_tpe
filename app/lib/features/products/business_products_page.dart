import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/app_back_button.dart';

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
  Map<String, int> _variantCountByProductId = {};
  final Random _rnd = Random();

  String _query = '';
  bool? _activeFilter; // null=all
  Timer? _debounce;
  bool _exporting = false;
  bool _importing = false;
  final Set<String> _duplicatingProductIds = {};

  static const _productMediaBucket = 'product_media';
  static const _maxUploadBytes = 20 * 1024 * 1024; // 20MB

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
      var q = sb
          .from('products')
          .select(
            'id,title,price_amount,currency,is_active,created_at,primary_media_id,'
            'product_media!product_media_product_id_fkey(id,storage_path,media_type,sort_order,created_at)',
          )
          .eq('business_id', widget.businessId);

      if (_activeFilter != null) {
        q = q.eq('is_active', _activeFilter!);
      }
      if (_query.trim().isNotEmpty) {
        q = q.ilike('title', '%${_query.trim()}%');
      }

      dynamic rows;
      try {
        rows = await q
            .order('created_at', ascending: false)
            .order('sort_order', referencedTable: 'product_media', ascending: true)
            .order('created_at', referencedTable: 'product_media', ascending: true);
      } on PostgrestException catch (e) {
        final m = e.message.toLowerCase();
        if (m.contains('primary_media_id') || m.contains('sort_order')) {
          // Backward-compatible: migration not applied yet.
          rows = await sb
              .from('products')
              .select('id,title,price_amount,currency,is_active,created_at,product_media!product_media_product_id_fkey(storage_path,media_type,created_at)')
              .eq('business_id', widget.businessId)
              .order('created_at', ascending: false);
        } else {
          rethrow;
        }
      }

      _products = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      // Best-effort: variants count (for a nicer UI)
      final ids = _products.map((p) => (p['id'] ?? '').toString()).where((s) => s.isNotEmpty).toList();
      if (ids.isNotEmpty) {
        try {
          final vrows = await sb.from('product_variants').select('product_id').inFilter('product_id', ids);
          final counts = <String, int>{};
          for (final r in (vrows as List)) {
            final m = Map<String, dynamic>.from(r as Map);
            final pid = (m['product_id'] ?? '').toString();
            if (pid.isEmpty) continue;
            counts[pid] = (counts[pid] ?? 0) + 1;
          }
          _variantCountByProductId = counts;
        } catch (_) {
          _variantCountByProductId = {};
        }
      } else {
        _variantCountByProductId = {};
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createProduct() async {
    if (!mounted) return;

    final sb = Supabase.instance.client;
    if (sb.auth.currentSession == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session manquante. Reconnecte-toi.')),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    final images = <_PickedMedia>[];
    _PickedMedia? video;
    final variants = <_DraftVariant>[];

    Future<Uint8List> readBytes(PlatformFile f) async {
      if (f.bytes != null && f.bytes!.isNotEmpty) return f.bytes!;
      if (f.path == null) throw Exception('Impossible de lire le fichier.');
      return File(f.path!).readAsBytes();
    }

    Future<void> pickImages(void Function(void Function()) setModalState) async {
      final remaining = 3 - images.length;
      if (remaining <= 0) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Max 3 photos par produit.')),
        );
        return;
      }

      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
        allowMultiple: true,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      if (!context.mounted) return;

      final picked = res.files.take(remaining).toList();
      for (final f in picked) {
        if (f.size > _maxUploadBytes) {
          messenger.showSnackBar(
            SnackBar(content: Text('Fichier trop volumineux: ${f.name}')),
          );
          continue;
        }
        final ext = (f.extension ?? '').toLowerCase();
        final bytes = await readBytes(f);
        setModalState(() {
          images.add(
            _PickedMedia(
              name: f.name,
              bytes: bytes,
              ext: ext.isEmpty ? 'png' : ext,
              mediaType: 'image',
              size: f.size,
            ),
          );
        });
      }

      if (res.files.length > remaining && mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Limite atteinte: $remaining photos ajoutées.')),
        );
      }
    }

    Future<void> pickVideo(void Function(void Function()) setModalState) async {
      if (video != null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Max 1 vidéo par produit.')),
        );
        return;
      }
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp4', 'webm', 'mov'],
        allowMultiple: false,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      if (!context.mounted) return;
      final f = res.files.first;
      if (f.size > _maxUploadBytes) {
        messenger.showSnackBar(
          SnackBar(content: Text('Vidéo trop volumineuse: ${f.name}')),
        );
        return;
      }
      final ext = (f.extension ?? '').toLowerCase();
      final bytes = await readBytes(f);
      setModalState(() {
        video = _PickedMedia(
          name: f.name,
          bytes: bytes,
          ext: ext.isEmpty ? 'mp4' : ext,
          mediaType: 'video',
          size: f.size,
        );
      });
    }

    Future<void> addVariantDialog(void Function(void Function()) setModalState) async {
      final vTitle = TextEditingController();
      final vSku = TextEditingController();
      final vPrice = TextEditingController();

      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Ajouter une variante'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: vTitle, decoration: const InputDecoration(labelText: 'Nom')),
              TextField(controller: vSku, decoration: const InputDecoration(labelText: 'SKU (optionnel)')),
              TextField(
                controller: vPrice,
                decoration: const InputDecoration(labelText: 'Prix (optionnel)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ajouter')),
          ],
        ),
      );

      if (ok == true) {
        final t = vTitle.text.trim();
        if (t.isNotEmpty) {
          setModalState(() {
            variants.add(
              _DraftVariant(
                title: t,
                sku: vSku.text.trim().isEmpty ? null : vSku.text.trim(),
                priceAmount: num.tryParse(vPrice.text.trim()),
              ),
            );
          });
        }
      }

      vTitle.dispose();
      vSku.dispose();
      vPrice.dispose();
    }

    String? createdProductId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (modalCtx) {
        bool saving = false;
        final scheme = Theme.of(modalCtx).colorScheme;

        Future<String> uploadAndInsertMedia({
          required String productId,
          required _PickedMedia m,
          required int sortOrder,
        }) async {
          final objectPath =
              '${widget.businessId}/products/$productId/${DateTime.now().millisecondsSinceEpoch}_${_randToken(6)}.${m.ext}';

          await sb.storage.from(_productMediaBucket).uploadBinary(
                objectPath,
                m.bytes,
                fileOptions: FileOptions(
                  upsert: false,
                  contentType: _contentTypeFromExt(m.ext),
                ),
              );

          try {
            final inserted = await sb
                .from('product_media')
                .insert({
                  'product_id': productId,
                  'media_type': m.mediaType,
                  'storage_path': objectPath,
                  'sort_order': sortOrder,
                })
                .select('id')
                .single();
            return (inserted as Map)['id'].toString();
          } on PostgrestException catch (e) {
            if (e.message.toLowerCase().contains('sort_order')) {
              final inserted = await sb
                  .from('product_media')
                  .insert({
                    'product_id': productId,
                    'media_type': m.mediaType,
                    'storage_path': objectPath,
                  })
                  .select('id')
                  .single();
              return (inserted as Map)['id'].toString();
            }
            rethrow;
          } catch (_) {
            await sb.storage.from(_productMediaBucket).remove([objectPath]);
            rethrow;
          }
        }

        Future<void> submit(void Function(void Function()) setModalState) async {
          if (saving) return;
          final title = titleCtrl.text.trim();
          if (title.isEmpty) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Le titre est obligatoire.')),
            );
            return;
          }

          setModalState(() => saving = true);
          try {
            final price = num.tryParse(priceCtrl.text.trim());
            final desc = descCtrl.text.trim();

            final inserted = await sb
                .from('products')
                .insert({
                  'business_id': widget.businessId,
                  'title': title,
                  'description': desc.isEmpty ? null : desc,
                  'price_amount': price,
                  'currency': 'XOF',
                  'is_active': true,
                })
                .select('id')
                .single();

            final productId = (inserted as Map)['id'].toString();

            String? firstImageMediaId;
            var order = 0;
            for (final m in images) {
              final mid = await uploadAndInsertMedia(productId: productId, m: m, sortOrder: order++);
              firstImageMediaId ??= mid;
            }
            if (video != null) {
              await uploadAndInsertMedia(productId: productId, m: video!, sortOrder: order++);
            }

            if (firstImageMediaId != null && firstImageMediaId.isNotEmpty) {
              try {
                await sb
                    .from('products')
                    .update({'primary_media_id': firstImageMediaId})
                    .eq('id', productId);
              } catch (_) {
                // ignore if column doesn't exist yet
              }
            }

            if (variants.isNotEmpty) {
              final inserts = variants
                  .map(
                    (v) => {
                      'product_id': productId,
                      'title': v.title,
                      'sku': v.sku,
                      'price_amount': v.priceAmount,
                      'currency': 'XOF',
                      'is_active': true,
                      'options': {},
                    },
                  )
                  .toList();
              await sb.from('product_variants').insert(inserts);
            }

            if (modalCtx.mounted) Navigator.of(modalCtx).pop(productId);
          } catch (e) {
            if (!modalCtx.mounted) return;
            ScaffoldMessenger.of(modalCtx).showSnackBar(SnackBar(content: Text('Erreur: $e')));
            setModalState(() => saving = false);
          }
        }

        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: StatefulBuilder(
                builder: (modalCtx, setModalState) {
                  return Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 16,
                      top: 10,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nouveau produit',
                            style: Theme.of(modalCtx).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Crée un produit, ajoute jusqu’à 3 photos + 1 vidéo, puis configure les variantes si besoin.',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 14),

                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  TextField(
                                    controller: titleCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Titre',
                                      prefixIcon: Icon(Icons.inventory_2_outlined),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: priceCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Prix (optionnel)',
                                      prefixIcon: Icon(Icons.payments_outlined),
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: descCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Description (optionnel)',
                                      prefixIcon: Icon(Icons.description_outlined),
                                    ),
                                    maxLines: 3,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Médias',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      FilledButton.tonalIcon(
                                        onPressed: saving ? null : () => pickImages(setModalState),
                                        icon: const Icon(Icons.add_photo_alternate_outlined),
                                        label: Text('Photos (${images.length}/3)'),
                                      ),
                                      const SizedBox(width: 10),
                                      FilledButton.tonalIcon(
                                        onPressed: saving ? null : () => pickVideo(setModalState),
                                        icon: const Icon(Icons.videocam_outlined),
                                        label: Text(video == null ? 'Vidéo' : 'Vidéo ✓'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (images.isEmpty && video == null)
                                    Text(
                                      'Optionnel: ajoute des médias pour rendre le produit plus attractif.',
                                      style: TextStyle(color: scheme.onSurfaceVariant),
                                    )
                                  else
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        for (int i = 0; i < images.length; i++)
                                          _MediaThumb(
                                            bytes: images[i].bytes,
                                            label: 'Photo ${i + 1}',
                                            onRemove: saving
                                                ? null
                                                : () => setModalState(() => images.removeAt(i)),
                                          ),
                                        if (video != null)
                                          _MediaThumb.video(
                                            label: video!.name,
                                            onRemove: saving ? null : () => setModalState(() => video = null),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Variantes (optionnel)',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      FilledButton.tonalIcon(
                                        onPressed: saving ? null : () => addVariantDialog(setModalState),
                                        icon: const Icon(Icons.add),
                                        label: const Text('Ajouter'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (variants.isEmpty)
                                    Text(
                                      'Ex: tailles, couleurs, packs…',
                                      style: TextStyle(color: scheme.onSurfaceVariant),
                                    )
                                  else
                                    Column(
                                      children: [
                                        for (int i = 0; i < variants.length; i++)
                                          ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(variants[i].title),
                                            subtitle: Text(
                                              [
                                                if ((variants[i].sku ?? '').isNotEmpty) 'SKU: ${variants[i].sku}',
                                                if (variants[i].priceAmount != null)
                                                  'Prix: ${variants[i].priceAmount} XOF',
                                              ].join(' • ').isEmpty
                                                  ? '—'
                                                  : [
                                                      if ((variants[i].sku ?? '').isNotEmpty)
                                                        'SKU: ${variants[i].sku}',
                                                      if (variants[i].priceAmount != null)
                                                        'Prix: ${variants[i].priceAmount} XOF',
                                                    ].join(' • '),
                                            ),
                                            trailing: IconButton(
                                              tooltip: 'Retirer',
                                              onPressed: saving
                                                  ? null
                                                  : () => setModalState(() => variants.removeAt(i)),
                                              icon: const Icon(Icons.close),
                                            ),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: saving ? null : () => Navigator.of(modalCtx).pop(null),
                                  child: const Text('Annuler'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: saving ? null : () => submit(setModalState),
                                  icon: saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.check),
                                  label: const Text('Créer'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    if (createdProductId != null && createdProductId.trim().isNotEmpty && mounted) {
      await _load();
      if (!mounted) return;
      context.push('/business/${widget.businessId}/products/$createdProductId');
    }

    titleCtrl.dispose();
    descCtrl.dispose();
    priceCtrl.dispose();
  }

  String _randToken(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(length, (_) => chars[_rnd.nextInt(chars.length)]).join();
  }

  String _contentTypeFromExt(String ext) {
    final e = ext.toLowerCase();
    if (e == 'png') return 'image/png';
    if (e == 'jpg' || e == 'jpeg') return 'image/jpeg';
    if (e == 'webp') return 'image/webp';
    if (e == 'mp4') return 'video/mp4';
    if (e == 'webm') return 'video/webm';
    if (e == 'mov') return 'video/quicktime';
    return 'application/octet-stream';
  }

  Future<void> _exportCsv() async {
    if (_exporting) return;
    setState(() => _exporting = true);

    try {
      final sb = Supabase.instance.client;

      final products = await sb
          .from('products')
          .select('id,title,description,price_amount,currency,is_active,created_at')
          .eq('business_id', widget.businessId)
          .order('created_at', ascending: false);

      final productList =
          (products as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final productIds = productList.map((p) => p['id'].toString()).where((s) => s.isNotEmpty).toList();

      List<Map<String, dynamic>> variants = [];
      bool hasLowStock = false;
      if (productIds.isNotEmpty) {
        try {
          final v = await sb
              .from('product_variants')
              .select('product_id,title,sku,price_amount,currency,is_active,low_stock_threshold,created_at')
              .inFilter('product_id', productIds)
              .order('created_at', ascending: true);
          variants = (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          hasLowStock = variants.isNotEmpty && variants.first.containsKey('low_stock_threshold');
        } on PostgrestException catch (e) {
          if (e.message.toLowerCase().contains('low_stock_threshold')) {
            final v = await sb
                .from('product_variants')
                .select('product_id,title,sku,price_amount,currency,is_active,created_at')
                .inFilter('product_id', productIds)
                .order('created_at', ascending: true);
            variants = (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            hasLowStock = false;
          } else {
            rethrow;
          }
        }
      }

      final variantsByProductId = <String, List<Map<String, dynamic>>>{};
      for (final v in variants) {
        final pid = v['product_id']?.toString() ?? '';
        (variantsByProductId[pid] ??= []).add(v);
      }

      final headers = <String>[
        'product_ref',
        'product_title',
        'product_description',
        'product_price_amount',
        'product_currency',
        'product_is_active',
        'variant_title',
        'variant_sku',
        'variant_price_amount',
        'variant_currency',
        'variant_is_active',
        if (hasLowStock) 'low_stock_threshold',
      ];

      final rows = <List<dynamic>>[headers];
      for (final p in productList) {
        final pid = p['id']?.toString() ?? '';
        final pvars = variantsByProductId[pid] ?? const <Map<String, dynamic>>[];

        if (pvars.isEmpty) {
          rows.add([
            pid,
            p['title'] ?? '',
            p['description'] ?? '',
            p['price_amount']?.toString() ?? '',
            p['currency'] ?? 'XOF',
            (p['is_active'] == true).toString(),
            '',
            '',
            '',
            '',
            '',
            if (hasLowStock) '',
          ]);
          continue;
        }

        for (final v in pvars) {
          rows.add([
            pid,
            p['title'] ?? '',
            p['description'] ?? '',
            p['price_amount']?.toString() ?? '',
            p['currency'] ?? 'XOF',
            (p['is_active'] == true).toString(),
            v['title'] ?? '',
            v['sku'] ?? '',
            v['price_amount']?.toString() ?? '',
            v['currency'] ?? (p['currency'] ?? 'XOF'),
            (v['is_active'] == true).toString(),
            if (hasLowStock) (v['low_stock_threshold']?.toString() ?? ''),
          ]);
        }
      }

      final csv = const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Exporter catalogue (CSV)',
        fileName: 'catalogue_${widget.businessId}_${DateTime.now().toIso8601String().substring(0, 10)}.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (path == null || path.trim().isEmpty) return;

      await File(path).writeAsString(csv, encoding: utf8);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export terminé: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur export: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _saveTemplateCsv() async {
    final headers = [
      'product_ref',
      'product_title',
      'product_description',
      'product_price_amount',
      'product_currency',
      'product_is_active',
      'variant_title',
      'variant_sku',
      'variant_price_amount',
      'variant_currency',
      'variant_is_active',
      'low_stock_threshold',
    ];

    final csv = const ListToCsvConverter(fieldDelimiter: ';').convert([headers]);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Télécharger modèle CSV',
      fileName: 'catalogue_template.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (path == null || path.trim().isEmpty) return;
    await File(path).writeAsString(csv, encoding: utf8);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Modèle enregistré: $path')));
  }

  bool _parseBool(Object? v) {
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'y' || s == 'oui';
  }

  num? _parseNum(Object? v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    return num.tryParse(s.replaceAll(',', '.'));
  }

  Future<void> _importCsv() async {
    if (_importing) return;
    setState(() => _importing = true);

    try {
      final sb = Supabase.instance.client;
      if (sb.auth.currentSession == null) {
        throw Exception('Session manquante. Reconnecte-toi.');
      }

      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
      if (pick == null || pick.files.isEmpty) return;

      final file = pick.files.first;
      final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Impossible de lire le fichier CSV.');
      }

      final text = utf8.decode(bytes);
      final lines = text.split(RegExp(r'\r?\n'));
      final firstLine = lines.isEmpty ? '' : lines.first;
      final commaCount = ','.allMatches(firstLine).length;
      final semiCount = ';'.allMatches(firstLine).length;
      final delimiter = semiCount > commaCount ? ';' : ',';

      final table = CsvToListConverter(
        shouldParseNumbers: false,
        fieldDelimiter: delimiter,
      ).convert(text);
      if (table.length < 2) {
        throw Exception('CSV vide ou incomplet.');
      }

      final headers = table.first.map((e) => e.toString().trim()).toList();
      int col(String name) => headers.indexWhere((h) => h.toLowerCase() == name.toLowerCase());

      final iProductTitle = col('product_title');
      if (iProductTitle < 0) {
        throw Exception('Colonne requise manquante: product_title');
      }

      final iProductRef = col('product_ref');
      final iProductDesc = col('product_description');
      final iProductPrice = col('product_price_amount');
      final iProductCur = col('product_currency');
      final iProductActive = col('product_is_active');

      final iVarTitle = col('variant_title');
      final iVarSku = col('variant_sku');
      final iVarPrice = col('variant_price_amount');
      final iVarCur = col('variant_currency');
      final iVarActive = col('variant_is_active');
      final iVarLow = col('low_stock_threshold');

      String cell(List<dynamic> r, int idx) {
        if (idx < 0) return '';
        if (idx >= r.length) return '';
        return (r[idx] ?? '').toString();
      }

      final dataRows = table.skip(1).where((r) => r.isNotEmpty).toList();
      if (dataRows.isEmpty) throw Exception('Aucune ligne à importer.');

      String groupKey(List<dynamic> r) {
        final ref = cell(r, iProductRef).trim();
        if (ref.isNotEmpty) return ref;
        return cell(r, iProductTitle).trim();
      }

      final groups = <String, List<List<dynamic>>>{};
      for (final r in dataRows) {
        final key = groupKey(r);
        if (key.isEmpty) continue;
        (groups[key] ??= []).add(r);
      }

      final ctx = context;
      if (!ctx.mounted) return;
      final ok = await showDialog<bool>(
        context: ctx,
        builder: (_) => AlertDialog(
          title: const Text('Importer catalogue'),
          content: Text(
            'Fichier: ${file.name}\n'
            'Produits à créer: ${groups.length}\n\n'
            'Notes:\n'
            '- Les produits seront importés comme INACTIFS par défaut (tu pourras les activer ensuite).\n'
            '- Les médias ne sont pas importés via CSV.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Importer')),
          ],
        ),
      );
      if (ok != true) return;

      int createdProducts = 0;
      int createdVariants = 0;

      for (final entry in groups.entries) {
        final rows = entry.value;
        final first = rows.first;

        final title = cell(first, iProductTitle).trim();
        if (title.isEmpty) continue;

        final desc = cell(first, iProductDesc).trim();
        final pPrice = _parseNum(cell(first, iProductPrice));
        final pCur = cell(first, iProductCur).trim().isEmpty ? 'XOF' : cell(first, iProductCur).trim();
        final pActive = _parseBool(cell(first, iProductActive));

        final inserted = await sb
            .from('products')
            .insert({
              'business_id': widget.businessId,
              'title': title,
              'description': desc.isEmpty ? null : desc,
              'price_amount': pPrice,
              'currency': pCur.isEmpty ? 'XOF' : pCur,
              // Safety: import as inactive by default (even if CSV says true)
              'is_active': false,
            })
            .select('id')
            .single();

        createdProducts++;
        final newPid = (inserted as Map)['id'].toString();

        // Optional: if CSV explicitly marked active, we still keep product inactive by default.
        // The user can activate it after checking the content.
        if (pActive) {
          // noop
        }

        final varInserts = <Map<String, dynamic>>[];
        for (final r in rows) {
          if (iVarTitle < 0) continue;
          final vt = cell(r, iVarTitle).trim();
          if (vt.isEmpty) continue;

          final sku = cell(r, iVarSku).trim();
          final vPrice = _parseNum(cell(r, iVarPrice));
          final vCur = cell(r, iVarCur).trim();
          final vActive = iVarActive >= 0 ? _parseBool(cell(r, iVarActive)) : true;

          final row = <String, dynamic>{
            'product_id': newPid,
            'title': vt,
            'sku': sku.isEmpty ? null : sku,
            'price_amount': vPrice,
            'currency': vCur.isEmpty ? (pCur.isEmpty ? 'XOF' : pCur) : vCur,
            'is_active': vActive,
            'options': {},
          };

          if (iVarLow >= 0) {
            final thr = int.tryParse(cell(r, iVarLow).trim()) ?? 0;
            row['low_stock_threshold'] = thr < 0 ? 0 : thr;
          }

          varInserts.add(row);
        }

        if (varInserts.isNotEmpty) {
          try {
            await sb.from('product_variants').insert(varInserts);
            createdVariants += varInserts.length;
          } on PostgrestException catch (e) {
            // Backward-compatible: low_stock_threshold might not exist.
            if (e.message.toLowerCase().contains('low_stock_threshold')) {
              for (final r in varInserts) {
                r.remove('low_stock_threshold');
              }
              await sb.from('product_variants').insert(varInserts);
              createdVariants += varInserts.length;
            } else {
              rethrow;
            }
          }
        }
      }

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import terminé: $createdProducts produits, $createdVariants variantes.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur import: $e')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _duplicateProduct(String productId) async {
    if (_duplicatingProductIds.contains(productId)) return;

    final ctx = context;
    setState(() {
      _error = null;
      _duplicatingProductIds.add(productId);
    });

    try {
      final sb = Supabase.instance.client;

      // Load full product (backward-compatible with optional cover column)
      Map<String, dynamic> product;
      try {
        final p = await sb
            .from('products')
            .select('id,business_id,title,description,price_amount,currency,is_active,primary_media_id')
            .eq('id', productId)
            .single();
        product = Map<String, dynamic>.from(p as Map);
      } on PostgrestException catch (e) {
        if (e.message.toLowerCase().contains('primary_media_id')) {
          final p = await sb
              .from('products')
              .select('id,business_id,title,description,price_amount,currency,is_active')
              .eq('id', productId)
              .single();
          product = Map<String, dynamic>.from(p as Map);
        } else {
          rethrow;
        }
      }

      final titleCtrl = TextEditingController(text: '${product['title'] ?? ''} (copie)');
      bool copyVariants = true;
      bool copyMediaPointers = true;
      bool copyCategories = true;
      bool keepInactive = true;

      if (!ctx.mounted) return;
      final ok = await showDialog<bool>(
        context: ctx,
        builder: (_) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Dupliquer produit'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Nouveau titre'),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: copyVariants,
                  onChanged: (v) => setState(() => copyVariants = v == true),
                  title: const Text('Copier les variantes'),
                ),
                CheckboxListTile(
                  value: copyMediaPointers,
                  onChanged: (v) => setState(() => copyMediaPointers = v == true),
                  title: const Text('Copier les médias (pointeurs)'),
                  subtitle: const Text(
                    'Les fichiers Storage ne sont pas dupliqués, on réutilise les mêmes chemins.',
                  ),
                ),
                CheckboxListTile(
                  value: copyCategories,
                  onChanged: (v) => setState(() => copyCategories = v == true),
                  title: const Text('Copier les catégories produit'),
                ),
                CheckboxListTile(
                  value: keepInactive,
                  onChanged: (v) => setState(() => keepInactive = v == true),
                  title: const Text('Créer le produit en inactif (recommandé)'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Dupliquer')),
            ],
          ),
        ),
      );

      if (ok != true) return;
      final newTitle = titleCtrl.text.trim();
      if (newTitle.isEmpty) return;

      // 1) Create new product
      final inserted = await sb
          .from('products')
          .insert({
            'business_id': widget.businessId,
            'title': newTitle,
            'description': (product['description'] ?? '').toString().trim().isEmpty ? null : product['description'],
            'price_amount': product['price_amount'],
            'currency': product['currency'] ?? 'XOF',
            'is_active': keepInactive ? false : (product['is_active'] == true),
          })
          .select('id')
          .single();

      final newProductId = (inserted as Map)['id'].toString();

      // 2) Copy product categories map
      if (copyCategories) {
        try {
          final pcm = await sb
              .from('product_categories_map')
              .select('category_id')
              .eq('product_id', productId);
          final catIds = (pcm as List)
              .map((e) => (e as Map)['category_id']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
          if (catIds.isNotEmpty) {
            await sb.from('product_categories_map').insert(
                  catIds.map((cid) => {'product_id': newProductId, 'category_id': cid}).toList(),
                );
          }
        } catch (_) {
          // ignore (mapping table may not exist in some environments)
        }
      }

      // 3) Copy variants (SKU must be unique per product -> set to null by default)
      if (copyVariants) {
        List<Map<String, dynamic>> variants = [];
        bool hasLowStock = false;
        try {
          final v = await sb
              .from('product_variants')
              .select('title,sku,options,price_amount,currency,is_active,low_stock_threshold,created_at')
              .eq('product_id', productId)
              .order('created_at', ascending: true);
          variants = (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          hasLowStock = variants.isNotEmpty && variants.first.containsKey('low_stock_threshold');
        } on PostgrestException catch (e) {
          if (e.message.toLowerCase().contains('low_stock_threshold')) {
            final v = await sb
                .from('product_variants')
                .select('title,sku,options,price_amount,currency,is_active,created_at')
                .eq('product_id', productId)
                .order('created_at', ascending: true);
            variants = (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            hasLowStock = false;
          } else {
            rethrow;
          }
        }

        if (variants.isNotEmpty) {
          final inserts = variants.map((v) {
            final row = <String, dynamic>{
              'product_id': newProductId,
              'title': v['title'],
              'sku': null, // avoid duplicates
              'options': v['options'] ?? {},
              'price_amount': v['price_amount'],
              'currency': v['currency'] ?? (product['currency'] ?? 'XOF'),
              'is_active': v['is_active'] == true,
            };
            if (hasLowStock) row['low_stock_threshold'] = v['low_stock_threshold'] ?? 0;
            return row;
          }).toList();

          try {
            await sb.from('product_variants').insert(inserts);
          } on PostgrestException catch (e) {
            if (hasLowStock && e.message.toLowerCase().contains('low_stock_threshold')) {
              for (final r in inserts) {
                r.remove('low_stock_threshold');
              }
              await sb.from('product_variants').insert(inserts);
            } else {
              rethrow;
            }
          }
        }
      }

      // 4) Copy media pointers (same storage_path)
      if (copyMediaPointers) {
        // Get old media list (backward-compatible with optional sort_order)
        List<Map<String, dynamic>> media = [];
        bool hasOrder = false;
        try {
          final m = await sb
              .from('product_media')
              .select('id,media_type,storage_path,sort_order,created_at')
              .eq('product_id', productId)
              .order('sort_order', ascending: true)
              .order('created_at', ascending: true);
          media = (m as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          hasOrder = media.isNotEmpty && media.first.containsKey('sort_order');
        } on PostgrestException catch (e) {
          if (e.message.toLowerCase().contains('sort_order')) {
            final m = await sb
                .from('product_media')
                .select('id,media_type,storage_path,created_at')
                .eq('product_id', productId)
                .order('created_at', ascending: true);
            media = (m as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            hasOrder = false;
          } else {
            rethrow;
          }
        }

        final oldToNewMediaId = <String, String>{};
        for (final m in media) {
          final oldId = (m['id'] ?? '').toString();
          final path = (m['storage_path'] ?? '').toString();
          if (path.isEmpty) continue;

          final insertRow = <String, dynamic>{
            'product_id': newProductId,
            'media_type': m['media_type'],
            'storage_path': path,
          };
          if (hasOrder) insertRow['sort_order'] = m['sort_order'] ?? 0;

          final insertedMedia = await sb
              .from('product_media')
              .insert(insertRow)
              .select('id')
              .single();
          final newMid = (insertedMedia as Map)['id'].toString();
          if (oldId.isNotEmpty) oldToNewMediaId[oldId] = newMid;
        }

        final oldPrimary = product['primary_media_id']?.toString();
        if (oldPrimary != null && oldPrimary.isNotEmpty && oldToNewMediaId.containsKey(oldPrimary)) {
          try {
            await sb
                .from('products')
                .update({'primary_media_id': oldToNewMediaId[oldPrimary]})
                .eq('id', newProductId);
          } catch (_) {
            // ignore if column doesn't exist yet
          }
        }
      }

      await _load();
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Produit dupliqué.')),
      );
      ctx.push('/business/${widget.businessId}/products/$newProductId');
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erreur duplication: $e')));
    } finally {
      if (mounted) {
        setState(() => _duplicatingProductIds.remove(productId));
      }
    }
  }

  String? _thumbUrl(Map<String, dynamic> p) {
    final sb = Supabase.instance.client;
    final media = p['product_media'];
    if (media is! List || media.isEmpty) return null;

    final primaryId = p['primary_media_id']?.toString();
    if (primaryId != null && primaryId.isNotEmpty) {
      for (final item in media) {
        final m = Map<String, dynamic>.from(item as Map);
        if (m['id']?.toString() == primaryId) {
          final path = (m['storage_path'] ?? '').toString();
          if (path.isNotEmpty) return sb.storage.from(_productMediaBucket).getPublicUrl(path);
        }
      }
    }

    Map<String, dynamic>? chosen;
    for (final item in media) {
      final m = Map<String, dynamic>.from(item as Map);
      final type = (m['media_type'] ?? '').toString().toLowerCase();
      if (type == 'image') {
        chosen = m;
        break;
      }
      chosen ??= m;
    }
    if (chosen == null) return null;
    final path = (chosen['storage_path'] ?? '').toString();
    if (path.isEmpty) return null;
    return sb.storage.from(_productMediaBucket).getPublicUrl(path);
  }

  void _onQueryChanged(String v) {
    _query = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sbClient = Supabase.instance.client;
    final total = _products.length;
    final activeCount = _products.where((p) => p['is_active'] == true).length;
    final inactiveCount = total - activeCount;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Produits (B2)'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          PopupMenuButton<String>(
            tooltip: 'Outils',
            onSelected: (v) async {
              if (v == 'template') await _saveTemplateCsv();
              if (v == 'export') await _exportCsv();
              if (v == 'import') await _importCsv();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'template',
                child: Row(
                  children: [
                    Icon(Icons.description_outlined),
                    SizedBox(width: 10),
                    Text('Modèle CSV'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'export',
                enabled: !_exporting,
                child: Row(
                  children: [
                    const Icon(Icons.download_outlined),
                    const SizedBox(width: 10),
                    Text(_exporting ? 'Export…' : 'Exporter CSV'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'import',
                enabled: !_importing,
                child: Row(
                  children: [
                    const Icon(Icons.upload_outlined),
                    const SizedBox(width: 10),
                    Text(_importing ? 'Import…' : 'Importer CSV'),
                  ],
                ),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.more_vert),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Filtrer',
            onSelected: (v) async {
              if (v == 'all') _activeFilter = null;
              if (v == 'active') _activeFilter = true;
              if (v == 'inactive') _activeFilter = false;
              await _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'all', child: Text('Tous')),
              PopupMenuItem(value: 'active', child: Text('Actifs')),
              PopupMenuItem(value: 'inactive', child: Text('Inactifs')),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.filter_list),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProduct,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau produit'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: scheme.primary.withAlpha(18),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(Icons.inventory_2_outlined, color: scheme.primary),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Catalogue (B2)',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                              ),
                            ),
                            Text(
                              '$total produits',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          onChanged: _onQueryChanged,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'Rechercher un produit…',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ChoiceChip(
                              label: const Text('Tous'),
                              selected: _activeFilter == null,
                              onSelected: (v) async {
                                if (!v) return;
                                _activeFilter = null;
                                await _load();
                              },
                            ),
                            ChoiceChip(
                              label: Text('Actifs ($activeCount)'),
                              selected: _activeFilter == true,
                              onSelected: (v) async {
                                if (!v) return;
                                _activeFilter = true;
                                await _load();
                              },
                            ),
                            ChoiceChip(
                              label: Text('Inactifs ($inactiveCount)'),
                              selected: _activeFilter == false,
                              onSelected: (v) async {
                                if (!v) return;
                                _activeFilter = false;
                                await _load();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!, style: TextStyle(color: scheme.error)))
                          : _products.isEmpty
                              ? Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 520),
                                    child: Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(18),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.inventory_2_outlined,
                                                size: 54, color: scheme.onSurfaceVariant),
                                            const SizedBox(height: 10),
                                            const Text(
                                              'Aucun produit pour le moment',
                                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'Crée ton premier produit. Tu peux ajouter jusqu’à 3 photos et 1 vidéo (optionnel).',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(color: scheme.onSurfaceVariant),
                                            ),
                                            const SizedBox(height: 14),
                                            SizedBox(
                                              width: double.infinity,
                                              child: FilledButton.icon(
                                                onPressed: _createProduct,
                                                icon: const Icon(Icons.add),
                                                label: const Text('Créer un produit'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final w = constraints.maxWidth;
                                      final crossAxisCount = w >= 1100
                                          ? 4
                                          : w >= 850
                                              ? 3
                                              : w >= 560
                                                  ? 2
                                                  : 1;
                                      final childAspectRatio = w >= 560 ? 0.95 : 1.45;

                                      return GridView.builder(
                                        padding: const EdgeInsets.only(bottom: 80),
                                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: crossAxisCount,
                                          crossAxisSpacing: 12,
                                          mainAxisSpacing: 12,
                                          childAspectRatio: childAspectRatio,
                                        ),
                                        itemCount: _products.length,
                                        itemBuilder: (context, index) {
                                          final p = _products[index];
                                          final price = p['price_amount'];
                                          final cur = p['currency']?.toString() ?? 'XOF';
                                          final active = p['is_active'] == true;
                                          final thumb = _thumbUrl(p);
                                          final pid = (p['id'] ?? '').toString();
                                          final duplicating =
                                              pid.isNotEmpty && _duplicatingProductIds.contains(pid);
                                          final variants = _variantCountByProductId[pid] ?? 0;

                                          return Card(
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(16),
                                              onTap: () {
                                                if (pid.isEmpty) return;
                                                context.push(
                                                  '/business/${widget.businessId}/products/$pid',
                                                );
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(12),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: ClipRRect(
                                                        borderRadius: BorderRadius.circular(14),
                                                        child: Container(
                                                          width: double.infinity,
                                                          color: scheme.surfaceContainerHighest,
                                                          child: thumb == null
                                                              ? Icon(
                                                                  Icons.image_outlined,
                                                                  size: 36,
                                                                  color: scheme.onSurfaceVariant,
                                                                )
                                                              : Image.network(
                                                                  thumb,
                                                                  fit: BoxFit.cover,
                                                                  errorBuilder:
                                                                      (context, error, stackTrace) => Icon(
                                                                    Icons.broken_image_outlined,
                                                                    color: scheme.onSurfaceVariant,
                                                                  ),
                                                                ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 10),
                                                    Text(
                                                      (p['title'] ?? '').toString(),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w800,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Row(
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                              horizontal: 10, vertical: 6),
                                                          decoration: BoxDecoration(
                                                            color: active
                                                                ? scheme.primary.withAlpha(18)
                                                                : scheme.surfaceContainerHighest,
                                                            borderRadius: BorderRadius.circular(999),
                                                            border: Border.all(color: scheme.outlineVariant),
                                                          ),
                                                          child: Text(
                                                            active ? 'Actif' : 'Inactif',
                                                            style: TextStyle(
                                                              fontWeight: FontWeight.w700,
                                                              color: active
                                                                  ? scheme.primary
                                                                  : scheme.onSurfaceVariant,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                              horizontal: 10, vertical: 6),
                                                          decoration: BoxDecoration(
                                                            color: scheme.surface,
                                                            borderRadius: BorderRadius.circular(999),
                                                            border: Border.all(color: scheme.outlineVariant),
                                                          ),
                                                          child: Text(
                                                            'Variantes: $variants',
                                                            style: TextStyle(
                                                              fontWeight: FontWeight.w700,
                                                              color: scheme.onSurfaceVariant,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            price == null
                                                                ? (variants > 0 ? 'Prix variables' : 'Prix: —')
                                                                : 'Prix: $price $cur',
                                                            style: TextStyle(color: scheme.onSurfaceVariant),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        PopupMenuButton<String>(
                                                          tooltip: 'Actions',
                                                          onSelected: (action) async {
                                                            if (pid.isEmpty) return;
                                                            if (action == 'duplicate') {
                                                              await _duplicateProduct(pid);
                                                            }
                                                            if (action == 'toggle') {
                                                              try {
                                                                await sbClient
                                                                    .from('products')
                                                                    .update({'is_active': !active})
                                                                    .eq('id', pid);
                                                                await _load();
                                                              } catch (e) {
                                                                final ctx = context;
                                                                if (!ctx.mounted) return;
                                                                ScaffoldMessenger.of(ctx).showSnackBar(
                                                                  SnackBar(content: Text('Erreur: $e')),
                                                                );
                                                              }
                                                            }
                                                          },
                                                          itemBuilder: (_) => [
                                                            PopupMenuItem(
                                                              value: 'duplicate',
                                                              enabled: !duplicating,
                                                              child: Row(
                                                                children: [
                                                                  const Icon(Icons.copy),
                                                                  const SizedBox(width: 10),
                                                                  Text(duplicating
                                                                      ? 'Duplication…'
                                                                      : 'Dupliquer'),
                                                                ],
                                                              ),
                                                            ),
                                                            const PopupMenuDivider(),
                                                            PopupMenuItem(
                                                              value: 'toggle',
                                                              child: Row(
                                                                children: [
                                                                  Icon(active
                                                                      ? Icons.visibility_off_outlined
                                                                      : Icons.visibility_outlined),
                                                                  const SizedBox(width: 10),
                                                                  Text(active ? 'Désactiver' : 'Activer'),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                          child: duplicating
                                                              ? const SizedBox(
                                                                  width: 22,
                                                                  height: 22,
                                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                                )
                                                              : const Icon(Icons.more_horiz),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
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

class _PickedMedia {
  final String name;
  final Uint8List bytes;
  final String ext;
  final String mediaType; // image|video
  final int size;

  const _PickedMedia({
    required this.name,
    required this.bytes,
    required this.ext,
    required this.mediaType,
    required this.size,
  });
}

class _DraftVariant {
  final String title;
  final String? sku;
  final num? priceAmount;

  const _DraftVariant({
    required this.title,
    required this.sku,
    required this.priceAmount,
  });
}

class _MediaThumb extends StatelessWidget {
  final Uint8List? bytes;
  final String label;
  final VoidCallback? onRemove;
  final bool isVideo;

  const _MediaThumb({
    required this.bytes,
    required this.label,
    required this.onRemove,
  }) : isVideo = false;

  const _MediaThumb.video({
    required this.label,
    required this.onRemove,
  })  : bytes = null,
        isVideo = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 92,
                  width: 130,
                  color: scheme.surfaceContainerHighest,
                  child: isVideo
                      ? Center(
                          child: Icon(
                            Icons.videocam_outlined,
                            size: 32,
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      : (bytes == null
                          ? Center(
                              child: Icon(
                                Icons.image_outlined,
                                color: scheme.onSurfaceVariant,
                              ),
                            )
                          : Image.memory(bytes!, fit: BoxFit.cover)),
                ),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: IconButton.filledTonal(
                  tooltip: 'Retirer',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.surface.withAlpha(220),
                    foregroundColor: scheme.onSurface,
                  ),
                ),
              ),
              if (isVideo)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(130),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'VIDEO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
