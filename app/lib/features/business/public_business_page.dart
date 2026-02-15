import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/app_back_button.dart';

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
  Map<String, dynamic>? _category;
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

      Map<String, dynamic>? biz;
      var hasCategoryColumn = true;
      try {
        final row = await sb
            .from('businesses')
            .select(
              'id,name,slug,description,logo_path,cover_path,whatsapp_phone,address_text,is_active,is_verified,business_category_id',
            )
            .eq('slug', widget.slug)
            .maybeSingle();
        if (row != null) biz = Map<String, dynamic>.from(row as Map);
      } on PostgrestException catch (e) {
        if (e.message.contains('business_category_id')) {
          hasCategoryColumn = false;
          final row = await sb
              .from('businesses')
              .select(
                'id,name,slug,description,logo_path,cover_path,whatsapp_phone,address_text,is_active,is_verified',
              )
              .eq('slug', widget.slug)
              .maybeSingle();
          if (row != null) biz = Map<String, dynamic>.from(row as Map);
        } else {
          rethrow;
        }
      }

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

      Map<String, dynamic>? category;
      if (hasCategoryColumn) {
        final catId = (biz['business_category_id'] ?? '').toString().trim();
        if (catId.isNotEmpty) {
          try {
            final row = await sb
                .from('business_categories')
                .select('id,slug,name,sort_order')
                .eq('id', catId)
                .maybeSingle();
            if (row != null) category = Map<String, dynamic>.from(row as Map);
          } catch (_) {
            category = null;
          }
        }
      }

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

      _biz = biz;
      _category = category;
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
    // Supports both conventions:
    // - 0..6 with 0=Sunday (Dim)
    // - 1..7 with 7=Sunday (Dim)
    const labels0 = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
    if (dow0to6 >= 0 && dow0to6 <= 6) return labels0[dow0to6];
    if (dow0to6 >= 1 && dow0to6 <= 7) return labels0[dow0to6 % 7];
    return '?';
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
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(okMsg ?? 'Copié'),
      ),
    );
  }

  Widget _pill(String text, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.surface.withAlpha(220),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
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
          leading: const AppBackButton(fallbackPath: '/explore'),
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
    final categoryName = (_category?['name'] ?? '').toString().trim();

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
              leading: const AppBackButton(fallbackPath: '/explore'),
              actions: [
                IconButton(
                  tooltip: 'Copier le lien',
                  onPressed: () => _copy('/b/$slug', okMsg: 'Chemin copié: /b/$slug'),
                  icon: const Icon(Icons.link),
                ),
                IconButton(
                  tooltip: 'Actualiser',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
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
                                    if (verified) _pill('Vérifié', icon: Icons.verified),
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
                                if (categoryName.isNotEmpty || address.trim().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (categoryName.isNotEmpty)
                                        _pill(categoryName, icon: Icons.category_outlined),
                                      if (address.trim().isNotEmpty)
                                        _pill(address.trim(), icon: Icons.location_on_outlined),
                                    ],
                                  ),
                                ],
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
                    businessName: name,
                    slug: slug,
                    categoryName: categoryName,
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
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (thumb == null)
                            const Center(child: Icon(Icons.inventory_2_outlined, size: 28))
                          else
                            Image.network(
                              thumb,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                alignment: Alignment.center,
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          if (media.length > 1)
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(140),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.photo_library_outlined,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${media.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
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

class _OpenNowSummary {
  final bool open;
  final String subtitle;
  const _OpenNowSummary({required this.open, required this.subtitle});
}

class _InfosTab extends StatelessWidget {
  final String businessName;
  final String slug;
  final String categoryName;
  final String desc;
  final String address;
  final String whatsapp;
  final List<Map<String, dynamic>> links;
  final List<Map<String, dynamic>> hours;
  final String Function(int) dowLabel;
  final String Function(Map<String, dynamic>) formatHours;
  final Future<void> Function(String, {String? okMsg}) onCopy;

  const _InfosTab({
    required this.businessName,
    required this.slug,
    required this.categoryName,
    required this.desc,
    required this.address,
    required this.whatsapp,
    required this.links,
    required this.hours,
    required this.dowLabel,
    required this.formatHours,
    required this.onCopy,
  });

  Uri? _toUri(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final u = Uri.tryParse(v);
    if (u == null) return null;
    if (u.hasScheme) return u;
    return Uri.tryParse('https://$v');
  }

  String _digitsOnly(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _launch(BuildContext context, Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text("Impossible d'ouvrir le lien."),
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text("Impossible d'ouvrir le lien."),
        ),
      );
    }
  }

  int _normalizeDow(int raw) {
    if (raw >= 0 && raw <= 6) return raw;
    if (raw >= 1 && raw <= 7) return raw % 7;
    return -1;
  }

  int _timeToMinutes(String? time) {
    if (time == null) return -1;
    final m = RegExp(r'^(\\d{1,2}):(\\d{2})').firstMatch(time.trim());
    if (m == null) return -1;
    final h = int.tryParse(m.group(1) ?? '') ?? -1;
    final min = int.tryParse(m.group(2) ?? '') ?? -1;
    if (h < 0 || h > 23 || min < 0 || min > 59) return -1;
    return (h * 60) + min;
  }

  _OpenNowSummary _openNowSummary() {
    if (hours.isEmpty) {
      return const _OpenNowSummary(open: false, subtitle: 'Horaires non renseignés');
    }

    final now = DateTime.now();
    final nowDow = now.weekday % 7; // 0=Sunday, 1=Monday, ..., 6=Saturday
    final nowMin = (now.hour * 60) + now.minute;

    Map<String, dynamic>? row;
    for (final h in hours) {
      final raw = (h['day_of_week'] as int?) ?? -1;
      if (_normalizeDow(raw) == nowDow) {
        row = h;
        break;
      }
    }

    if (row == null) return const _OpenNowSummary(open: false, subtitle: 'Horaires non renseignés');
    if (row['is_closed'] == true) return const _OpenNowSummary(open: false, subtitle: "Fermé aujourd'hui");

    final openMin = _timeToMinutes(row['open_time']?.toString());
    final closeMin = _timeToMinutes(row['close_time']?.toString());
    if (openMin < 0 || closeMin < 0) {
      return const _OpenNowSummary(open: false, subtitle: 'Horaires non renseignés');
    }

    final openNow = closeMin > openMin
        ? (nowMin >= openMin && nowMin < closeMin)
        : (nowMin >= openMin || nowMin < closeMin); // overnight

    final o = (row['open_time'] ?? '').toString();
    final c = (row['close_time'] ?? '').toString();
    final o5 = o.length >= 5 ? o.substring(0, 5) : o;
    final c5 = c.length >= 5 ? c.substring(0, 5) : c;

    return _OpenNowSummary(open: openNow, subtitle: openNow ? 'Ferme à $c5' : 'Ouvre $o5 – $c5');
  }

  IconData _platformIcon(String platform) {
    switch (platform.trim().toLowerCase()) {
      case 'website':
      case 'site':
      case 'web':
        return Icons.public;
      case 'whatsapp':
        return Icons.chat_bubble_outline;
      case 'facebook':
        return Icons.facebook;
      case 'instagram':
        return Icons.camera_alt_outlined;
      case 'tiktok':
        return Icons.music_note_outlined;
      case 'youtube':
        return Icons.play_circle_outline;
      case 'x':
      case 'twitter':
        return Icons.alternate_email;
      default:
        return Icons.link;
    }
  }

  String _platformLabel(String platform) {
    final p = platform.trim();
    if (p.isEmpty) return 'Lien';
    return '${p[0].toUpperCase()}${p.substring(1)}';
  }

  Widget _sectionTitle(BuildContext context, String title, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: scheme.primary.withAlpha(18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final openNow = _openNowSummary();

    final hasAnyContact = address.trim().isNotEmpty || whatsapp.trim().isNotEmpty;
    final phoneDigits = _digitsOnly(whatsapp);

    final waUri = phoneDigits.isEmpty ? null : Uri.parse('https://wa.me/$phoneDigits');
    final telUri = whatsapp.trim().isEmpty ? null : Uri.tryParse('tel:${whatsapp.trim()}');
    final mapUri = address.trim().isEmpty
        ? null
        : Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address.trim())}');

    final usableLinks = links
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => (e['url'] ?? '').toString().trim().isNotEmpty)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (openNow.open ? const Color(0xFF10B981) : scheme.error).withAlpha(22),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.schedule,
                    color: openNow.open ? const Color(0xFF10B981) : scheme.error,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        openNow.open ? 'Ouvert maintenant' : 'Fermé',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(openNow.subtitle, style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Copier le lien',
                  onPressed: () => onCopy('/b/$slug', okMsg: 'Chemin copié: /b/$slug'),
                  icon: const Icon(Icons.link),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),
        _sectionTitle(context, 'À propos', Icons.info_outline),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (categoryName.trim().isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.primary.withAlpha(16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.category_outlined, size: 16, color: scheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          categoryName,
                          style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onSurface),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  desc.trim().isEmpty ? 'Aucune description pour le moment.' : desc.trim(),
                  style: const TextStyle(height: 1.25),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        _sectionTitle(context, 'Contact', Icons.contact_phone_outlined),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                if (!hasAnyContact)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Contact non renseigné.', style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                if (address.trim().isNotEmpty) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_on_outlined),
                    title: const Text('Adresse', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(address.trim()),
                    trailing: Wrap(
                      spacing: 6,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Copier',
                          onPressed: () => onCopy(address.trim(), okMsg: 'Adresse copiée'),
                          icon: const Icon(Icons.copy),
                        ),
                        if (mapUri != null)
                          IconButton.filledTonal(
                            tooltip: 'Ouvrir Maps',
                            onPressed: () => _launch(context, mapUri),
                            icon: const Icon(Icons.map_outlined),
                          ),
                      ],
                    ),
                  ),
                  if (whatsapp.trim().isNotEmpty) const Divider(height: 22),
                ],
                if (whatsapp.trim().isNotEmpty) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(whatsapp.trim()),
                    trailing: Wrap(
                      spacing: 6,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Copier',
                          onPressed: () => onCopy(whatsapp.trim(), okMsg: 'WhatsApp copié'),
                          icon: const Icon(Icons.copy),
                        ),
                        if (waUri != null)
                          IconButton.filledTonal(
                            tooltip: 'Ouvrir WhatsApp',
                            onPressed: () => _launch(context, waUri),
                            icon: const Icon(Icons.send_outlined),
                          ),
                        if (telUri != null)
                          IconButton.filledTonal(
                            tooltip: 'Appeler',
                            onPressed: () => _launch(context, telUri),
                            icon: const Icon(Icons.phone_outlined),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        _sectionTitle(context, 'Horaires', Icons.access_time),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hours.isEmpty)
                  Text('Horaires non renseignés.', style: TextStyle(color: scheme.onSurfaceVariant))
                else
                  ...hours.map((h) {
                    final raw = (h['day_of_week'] as int?) ?? -1;
                    final label = dowLabel(raw);
                    final normalized = _normalizeDow(raw);
                    final nowDow = DateTime.now().weekday % 7;
                    final isToday = normalized >= 0 && normalized == nowDow;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 48,
                            child: Text(
                              label,
                              style: TextStyle(
                                fontWeight: isToday ? FontWeight.w900 : FontWeight.w700,
                                color: isToday ? scheme.primary : scheme.onSurface,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              formatHours(h),
                              style: TextStyle(
                                fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
                                color: isToday ? scheme.primary : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (isToday)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: scheme.primary.withAlpha(14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: scheme.outlineVariant),
                              ),
                              child: Text(
                                "Aujourd'hui",
                                style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        _sectionTitle(context, 'Liens', Icons.link),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                if (usableLinks.isEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Aucun lien.', style: TextStyle(color: scheme.onSurfaceVariant)),
                  )
                else
                  ...usableLinks.map((l) {
                    final platform = (l['platform'] ?? '').toString();
                    final url = (l['url'] ?? '').toString().trim();
                    final label = (l['label'] ?? '').toString().trim();

                    final uri = _toUri(url);
                    final title = label.isNotEmpty ? label : _platformLabel(platform);

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_platformIcon(platform), color: scheme.primary),
                      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          IconButton.filledTonal(
                            tooltip: 'Copier',
                            onPressed: () => onCopy(url, okMsg: 'Lien copié'),
                            icon: const Icon(Icons.copy),
                          ),
                          if (uri != null)
                            IconButton.filledTonal(
                              tooltip: 'Ouvrir',
                              onPressed: () => _launch(context, uri),
                              icon: const Icon(Icons.open_in_new),
                            ),
                        ],
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
