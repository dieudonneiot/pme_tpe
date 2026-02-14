import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PublicBusinessPage extends StatefulWidget {
  final String slug;
  const PublicBusinessPage({super.key, required this.slug});

  @override
  State<PublicBusinessPage> createState() => _PublicBusinessPageState();
}

class _PublicBusinessPageState extends State<PublicBusinessPage> {
  static const _logoBucket = 'business_logos';
  static const _coverBucket = 'business_covers';

  static const _productMediaBucket = 'product_media';

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _biz;
  List<Map<String, dynamic>> _links = [];
  List<Map<String, dynamic>> _hours = [];
  List<Map<String, dynamic>> _products = [];

  String? _publicUrl(String bucket, String? path) {
    if (path == null || path.isEmpty) return null;
    return Supabase.instance.client.storage.from(bucket).getPublicUrl(path);
  }

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
      final sb = Supabase.instance.client;

      final biz = await sb
          .from('businesses')
          .select(
            'id,name,slug,description,logo_path,cover_path,whatsapp_phone,address_text,is_active,is_verified',
          )
          .eq('slug', widget.slug)
          .maybeSingle();

      if (biz == null) {
        throw Exception("Boutique introuvable.");
      }

      if (biz['is_active'] != true) {
        throw Exception("Cette boutique n'est pas active.");
      }

      final bizId = (biz['id'] as String);

      final links = await sb
          .from('business_social_links')
          .select('platform,url,label,sort_order')
          .eq('business_id', bizId)
          .order('sort_order', ascending: true);

      final hours = await sb
          .from('business_hours')
          .select('day_of_week,is_closed,open_time,close_time,timezone')
          .eq('business_id', bizId)
          .order('day_of_week', ascending: true);

      dynamic products;
      try {
        products = await sb
            .from('products')
            .select(
              'id,title,description,price_amount,currency,created_at,is_active,primary_media_id,'
              'product_media!product_media_product_id_fkey(id,media_type,storage_path,sort_order,created_at)',
            )
            .eq('business_id', bizId)
            .eq('is_active', true)
            .order('created_at', ascending: false)
            .order('sort_order', referencedTable: 'product_media', ascending: true)
            .order('created_at', referencedTable: 'product_media', ascending: true)
            .limit(30);
      } on PostgrestException catch (e) {
        final m = e.message.toLowerCase();
        if (m.contains('primary_media_id') || m.contains('sort_order')) {
          // Backward-compatible: migration not applied yet.
          products = await sb
              .from('products')
              .select('id,title,description,price_amount,currency,created_at,is_active,product_media!product_media_product_id_fkey(id,media_type,storage_path)')
              .eq('business_id', bizId)
              .eq('is_active', true)
              .order('created_at', ascending: false)
              .limit(30);
        } else {
          rethrow;
        }
      }

      _biz = Map<String, dynamic>.from(biz as Map);
      _links = (links as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _hours = (hours as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _products = (products as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _dowLabel(int dow0to6) {
    const labels = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
    if (dow0to6 < 0 || dow0to6 > 6) return '?';
    return labels[dow0to6];
  }

  String _formatHours(Map<String, dynamic> row) {
    final isClosed = row['is_closed'] == true;
    if (isClosed) return 'Fermé';

    final open = row['open_time']?.toString();
    final close = row['close_time']?.toString();
    if (open == null || close == null) return '—';
    return '${open.substring(0, 5)} – ${close.substring(0, 5)}';
  }

  Future<void> _copy(String text, {String? okMsg}) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(okMsg ?? 'Copié')),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  String _currency(String? c) => (c == null || c.isEmpty) ? 'XOF' : c;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
          ),
          title: const Text('Boutique'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        ),
      );
    }

    final biz = _biz!;
    final name = (biz['name'] ?? '').toString();
    final slug = (biz['slug'] ?? '').toString();
    final desc = (biz['description'] ?? '').toString();
    final whatsapp = (biz['whatsapp_phone'] ?? '').toString();
    final address = (biz['address_text'] ?? '').toString();
    final verified = biz['is_verified'] == true;

    final logoUrl = _publicUrl(_logoBucket, biz['logo_path'] as String?);
    final coverUrl = _publicUrl(_coverBucket, biz['cover_path'] as String?);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 260,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/');
                  }
                },
              ),
              actions: [
                IconButton(
                  tooltip: 'Copier le lien',
                  onPressed: () => _copy('/b/$slug', okMsg: 'Chemin copié: /b/$slug'),
                  icon: const Icon(Icons.link),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                    children: [
                      if (coverUrl != null)
                      Image.network(
                        coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                      )
                    else
                      Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.25),
                            Colors.black.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 90, 16, 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            width: 86,
                            height: 86,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).colorScheme.surface,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.surface,
                                width: 3,
                              ),
                            ),
                            child: ClipOval(
                              child: logoUrl == null
                                  ? const Icon(Icons.store, size: 40)
                                  : Image.network(
                                      logoUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        child: const Center(child: Icon(Icons.store)),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (verified) _pill('Vérifié'),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '@$slug',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Produits'),
                  Tab(text: 'Infos'),
                ],
              ),
            ),

            SliverFillRemaining(
              child: TabBarView(
                children: [
                  _ProductsTab(
                    products: _products,
                    mediaBucket: _productMediaBucket,
                    currency: _currency,
                    onOpenProduct: (id) => context.push('/p/$id'),
                  ),
                  _InfosTab(
                    desc: desc,
                    address: address,
                    whatsapp: whatsapp,
                    links: _links,
                    hours: _hours,
                    dowLabel: _dowLabel,
                    formatHours: _formatHours,
                    onCopy: _copy,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* Posts tab removed (unused) — keep code commented for future reuse.
class _PostsTab extends StatelessWidget {
  final List<Map<String, dynamic>> posts;
  final String mediaBucket;
  const _PostsTab({required this.posts, required this.mediaBucket});

  String? _mediaUrl(String bucket, String? path) {
    if (path == null || path.isEmpty) return null;
    return Supabase.instance.client.storage.from(bucket).getPublicUrl(path);
  }

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return const Center(child: Text('Aucun post pour le moment.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: posts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final p = posts[i];
        final title = (p['title'] ?? '').toString();
        final content = (p['content'] ?? '').toString();

        final media = (p['post_media'] as List?)?.cast<Map>() ?? [];
        String? thumb;
        if (media.isNotEmpty) {
          final first = Map<String, dynamic>.from(media.first);
          thumb = _mediaUrl(mediaBucket, first['storage_path']?.toString());
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  child: thumb == null
                      ? const Icon(Icons.play_circle_outline)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(thumb, fit: BoxFit.cover),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? 'Post' : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        content.isEmpty ? '—' : content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

*/

class _ProductsTab extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final String mediaBucket;
  final String Function(String?) currency;
  final ValueChanged<String> onOpenProduct;
  const _ProductsTab({
    required this.products,
    required this.mediaBucket,
    required this.currency,
    required this.onOpenProduct,
  });

  String? _mediaUrl(String bucket, String? path) {
    if (path == null || path.isEmpty) return null;
    return Supabase.instance.client.storage.from(bucket).getPublicUrl(path);
  }

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const Center(child: Text('Aucun produit pour le moment.'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        childAspectRatio: 0.92,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) {
        final pr = products[i];
        final title = (pr['title'] ?? '').toString();
        final price = pr['price_amount'];
        final cur = currency(pr['currency']?.toString());

        final media = (pr['product_media'] as List?)?.cast<Map>() ?? [];
        String? thumb;
        if (media.isNotEmpty) {
          final primaryId = pr['primary_media_id']?.toString();
          Map<String, dynamic>? chosenImage;

          if (primaryId != null && primaryId.isNotEmpty) {
            for (final item in media) {
              final m = Map<String, dynamic>.from(item);
              final t = (m['media_type'] ?? '').toString().toLowerCase();
              if (m['id']?.toString() == primaryId && t == 'image') {
                chosenImage = m;
                break;
              }
            }
          }

          chosenImage ??= () {
            for (final item in media) {
              final m = Map<String, dynamic>.from(item);
              final t = (m['media_type'] ?? '').toString().toLowerCase();
              if (t == 'image') return m;
            }
            return null;
          }();

          if (chosenImage != null) {
            thumb = _mediaUrl(mediaBucket, chosenImage['storage_path']?.toString());
          }
        }

        String priceText = '—';
        if (price is num) {
          final n = price;
          final s = (n % 1 == 0) ? n.toInt().toString() : n.toStringAsFixed(2);
          priceText = '$s $cur';
        }

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              final id = (pr['id'] ?? '').toString();
              if (id.isEmpty) return;
              onOpenProduct(id);
            },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: thumb == null
                          ? const Center(child: Icon(Icons.inventory_2_outlined, size: 28))
                          : Image.network(
                              thumb,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                alignment: Alignment.center,
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title.isEmpty ? 'Produit' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    priceText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InfosTab extends StatelessWidget {
  final String desc;
  final String address;
  final String whatsapp;
  final List<Map<String, dynamic>> links;
  final List<Map<String, dynamic>> hours;
  final String Function(int) dowLabel;
  final String Function(Map<String, dynamic>) formatHours;
  final Future<void> Function(String, {String? okMsg}) onCopy;

  const _InfosTab({
    required this.desc,
    required this.address,
    required this.whatsapp,
    required this.links,
    required this.hours,
    required this.dowLabel,
    required this.formatHours,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('À propos', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(desc.isEmpty ? '—' : desc),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Contact', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (address.isNotEmpty) Text('Adresse: $address'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: Text(whatsapp.isEmpty ? 'WhatsApp: —' : 'WhatsApp: $whatsapp')),
                    if (whatsapp.isNotEmpty)
                      TextButton(
                        onPressed: () => onCopy(whatsapp, okMsg: 'WhatsApp copié'),
                        child: const Text('Copier'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Horaires', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (hours.isEmpty)
                  const Text('—')
                else
                  ...hours.map((h) {
                    final day = (h['day_of_week'] as int?) ?? -1;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(width: 46, child: Text(dowLabel(day))),
                          Expanded(child: Text(formatHours(h))),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Liens', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (links.isEmpty)
                  const Text('—')
                else
                  ...links.map((l) {
                    final platform = (l['platform'] ?? '').toString();
                    final url = (l['url'] ?? '').toString();
                    final label = (l['label'] ?? '').toString();
                    final line = label.isNotEmpty ? '$platform: $label' : '$platform: $url';

                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(line, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: url.isEmpty
                          ? null
                          : TextButton(
                              onPressed: () => onCopy(url, okMsg: 'Lien copié'),
                              child: const Text('Copier'),
                            ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
