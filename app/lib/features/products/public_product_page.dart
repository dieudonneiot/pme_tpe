import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../cart/cart_scope.dart';
import '../cart/cart_service.dart';

// IMPORTANT:
// 1) Create a global RouteObserver in (example) lib/core/route_observer.dart:
//    final RouteObserver<PageRoute<dynamic>> routeObserver = RouteObserver<PageRoute<dynamic>>();
// 2) Add it to GoRouter(observers: [routeObserver])
// Adjust this import path to your project:
import '../../core/route_observer.dart';

class PublicProductPage extends StatefulWidget {
  final String productId;
  const PublicProductPage({super.key, required this.productId});

  @override
  State<PublicProductPage> createState() => _PublicProductPageState();
}

class _PublicProductPageState extends State<PublicProductPage>
    with RouteAware, WidgetsBindingObserver {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _product;
  List<Map<String, dynamic>> _variants = [];

  String? _selectedVariantId;

  static const _productMediaBucket = 'product_media';

  bool get _loggedIn => _sb.auth.currentSession != null;

  // Audio: OFF by default (page-level)
  bool _muted = true;

  bool get _videoSupported {
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => true,
      _ => false,
    };
  }

  // Route/app visibility => hard-stop video audio when not visible
  bool _routeVisible = true;
  bool _appResumed = true;

  bool get _pageActive => _routeVisible && _appResumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = ModalRoute.of(context);
    if (r is PageRoute) routeObserver.subscribe(this, r);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // RouteAware: another route covers this page
  @override
  void didPushNext() {
    if (!mounted) return;
    setState(() => _routeVisible = false);
  }

  // RouteAware: coming back to this page
  @override
  void didPopNext() {
    if (!mounted) return;
    setState(() => _routeVisible = true);
  }

  // App lifecycle: background/foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (!mounted) return;
    setState(() => _appResumed = resumed);
  }

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      Map<String, dynamic>? p;
      try {
        final row = await _sb
            .from('products')
            .select(
              'id,title,description,price_amount,currency,business_id,primary_media_id,'
              'businesses(id,name,slug),'
              'product_media!product_media_product_id_fkey(id,media_type,storage_path,sort_order,created_at)',
             )
            .eq('id', widget.productId)
            .order('sort_order', referencedTable: 'product_media', ascending: true)
            .order('created_at', referencedTable: 'product_media', ascending: true)
            .maybeSingle();
        if (row != null) p = Map<String, dynamic>.from(row as Map);
      } on PostgrestException catch (e) {
        final m = e.message.toLowerCase();
        if (m.contains('primary_media_id') || m.contains('sort_order')) {
          final row = await _sb
              .from('products')
              .select(
                'id,title,description,price_amount,currency,business_id,'
                'businesses(id,name,slug),'
                'product_media!product_media_product_id_fkey(id,media_type,storage_path)',
              )
              .eq('id', widget.productId)
              .maybeSingle();
          if (row != null) p = Map<String, dynamic>.from(row as Map);
        } else {
          rethrow;
        }
      }

      if (p == null) {
        if (!mounted) return;
        setState(() => _error = 'Produit introuvable.');
        return;
      }

      final v = await _sb
          .from('product_variants')
          .select('id,title,price_amount,currency,is_active,options,created_at')
          .eq('product_id', widget.productId)
          .eq('is_active', true)
          .order('created_at', ascending: true);

      final variants = (v as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _product = p;
        _variants = variants;

        if (_variants.isNotEmpty) {
          _selectedVariantId ??= _variants.first['id']?.toString();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // ---------------- MEDIA HELPERS ----------------

  List<Map<String, dynamic>> _mediaList() {
    final media = _product?['product_media'];
    if (media is List) {
      return media.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (media is Map) {
      return [Map<String, dynamic>.from(media)];
    }
    return [];
  }

  ({String? url, String? type}) _primaryMedia({bool allowVideo = true}) {
    final list = _mediaList();
    if (list.isEmpty) return (url: null, type: null);

    final primaryId = _product?['primary_media_id']?.toString();
    if (primaryId != null && primaryId.isNotEmpty) {
      for (final m in list) {
        if (m['id']?.toString() == primaryId) {
          final type = (m['media_type'] ?? '').toString().toLowerCase();
          if (!allowVideo && type == 'video') {
            break; // ignore primary video when the platform can't play it
          }
          final path = (m['storage_path'] ?? '').toString();
          if (path.isEmpty) return (url: null, type: type.isEmpty ? null : type);
          final url = _sb.storage.from(_productMediaBucket).getPublicUrl(path);
          return (url: url, type: type.isEmpty ? null : type);
        }
      }
    }

    // Prefer image as hero if available
    Map<String, dynamic> chosen = list.first;
    for (final m in list) {
      final t = (m['media_type'] ?? '').toString().toLowerCase();
      if (t == 'image') {
        chosen = m;
        break;
      }
    }

    final type = (chosen['media_type'] ?? '').toString().toLowerCase();
    final path = (chosen['storage_path'] ?? '').toString();
    if (path.isEmpty) return (url: null, type: type.isEmpty ? null : type);

    final url = _sb.storage.from(_productMediaBucket).getPublicUrl(path);
    return (url: url, type: type.isEmpty ? null : type);
  }

  // Used for cart thumb: use primary hero media (prefer image)
  String? _mediaUrlForCart() {
    final variant = _selectedVariant;
    if (variant != null) {
      final coverId = _variantCoverMediaId(variant);
      if (coverId.isNotEmpty) {
        for (final m in _mediaList()) {
          if (m['id']?.toString() != coverId) continue;
          final t = (m['media_type'] ?? '').toString().toLowerCase();
          if (t != 'image') continue;
          final path = (m['storage_path'] ?? '').toString();
          if (path.isEmpty) break;
          return _sb.storage.from(_productMediaBucket).getPublicUrl(path);
        }
      }
    }

    return _primaryMedia(allowVideo: false).url;
  }

  String? _posterUrl() {
    for (final m in _mediaList()) {
      final t = (m['media_type'] ?? '').toString().toLowerCase();
      if (t != 'image') continue;
      final path = (m['storage_path'] ?? '').toString();
      if (path.isEmpty) continue;
      return _sb.storage.from(_productMediaBucket).getPublicUrl(path);
    }
    return null;
  }

  String _variantCoverMediaId(Map<String, dynamic> variant) {
    final opt = variant['options'];
    if (opt is Map) {
      final raw = (opt['cover_media_id'] ?? '').toString().trim();
      return raw;
    }
    return '';
  }

  List<_GalleryItem> _galleryItems({required bool allowVideo}) {
    final rows = _mediaList();
    final out = <_GalleryItem>[];
    for (final m in rows) {
      final id = (m['id'] ?? '').toString();
      if (id.isEmpty) continue;

      final type = (m['media_type'] ?? '').toString().toLowerCase();
      if (!allowVideo && type == 'video') continue;

      final path = (m['storage_path'] ?? '').toString();
      if (path.isEmpty) continue;

      out.add(
        _GalleryItem(
          id: id,
          type: type.isEmpty ? 'image' : type,
          url: _sb.storage.from(_productMediaBucket).getPublicUrl(path),
        ),
      );
    }
    return out;
  }

  String? _resolveInitialMediaId(
    List<_GalleryItem> items, {
    String? preferredMediaId,
  }) {
    if (items.isEmpty) return null;

    final byId = <String, _GalleryItem>{for (final i in items) i.id: i};

    final preferred = (preferredMediaId ?? '').trim();
    if (preferred.isNotEmpty && byId.containsKey(preferred)) return preferred;

    final primaryId = _product?['primary_media_id']?.toString().trim();
    if (primaryId != null && primaryId.isNotEmpty && byId.containsKey(primaryId)) {
      return primaryId;
    }

    for (final i in items) {
      if (i.type == 'image') return i.id;
    }
    return items.first.id;
  }

  // ---------------- CART ----------------

  Widget _cartIcon(BuildContext context) {
    final cart = CartScope.of(context);

    return AnimatedBuilder(
      animation: cart,
      builder: (context, child) {
        final qty = cart.totalQty;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Panier',
              onPressed: () => context.push('/cart'),
              icon: const Icon(Icons.shopping_cart_outlined),
            ),
            if (qty > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$qty',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _openBusinessSpace() {
    if (_loggedIn) {
      context.go('/home');
    } else {
      final next = Uri.encodeComponent('/home');
      context.push('/login?next=$next');
    }
  }

  Map<String, dynamic>? get _selectedVariant {
    if (_selectedVariantId == null) return null;
    for (final v in _variants) {
      if (v['id']?.toString() == _selectedVariantId) return v;
    }
    return null;
  }

  String _cartLineId(String productId, {String? variantId}) {
    if (variantId == null || variantId.isEmpty) return productId;
    return '$productId::$variantId';
  }

  Future<void> _addToCartAndOpen() async {
    final p = _product;
    if (p == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final cart = CartScope.of(context);

    final baseProductId = (p['id'] ?? '').toString();
    final businessId = (p['business_id'] ?? '').toString();
    final title = (p['title'] ?? '').toString();

    num? unitPrice = p['price_amount'] as num?;
    String currency = (p['currency'] ?? 'XOF').toString();

    final variant = _selectedVariant;
    final variantId = variant?['id']?.toString();
    final variantTitle = (variant?['title'] ?? '').toString().trim();

    if (variant != null) {
      final vPrice = variant['price_amount'];
      if (vPrice is num) unitPrice = vPrice;
      currency = (variant['currency'] ?? currency).toString();
    }

    if (unitPrice == null || unitPrice <= 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Prix indisponible pour ce produit.')),
      );
      return;
    }

    final lineId = _cartLineId(baseProductId, variantId: variantId);
    final lineTitle = variantTitle.isEmpty ? title : '$title — $variantTitle';

    try {
      cart.add(
        productId: lineId,
        businessId: businessId,
        title: lineTitle,
        unitPrice: unitPrice,
        currency: currency,
        mediaUrl: _mediaUrlForCart(),
        qty: 1,
      );

      messenger.showSnackBar(const SnackBar(content: Text('Ajouté au panier')));
      if (!mounted) return;
      context.push('/cart');
    } on CartBusinessMismatch {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Panier d’une autre boutique'),
          content: const Text(
            'Votre panier contient déjà des produits d’une autre boutique. Voulez-vous vider le panier ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Vider'),
            ),
          ],
        ),
      );

      if (ok == true) {
        cart.clear();
        cart.add(
          productId: lineId,
          businessId: businessId,
          title: lineTitle,
          unitPrice: unitPrice,
          currency: currency,
          mediaUrl: _mediaUrlForCart(),
          qty: 1,
        );
        if (!mounted) return;
        context.push('/cart');
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur panier: $e')));
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/explore'),
        ),
        title: const Text('Produit'),
        actions: [
          IconButton(
            tooltip: _muted ? 'Son: OFF' : 'Son: ON',
            onPressed: () => setState(() => _muted = !_muted),
            icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
          ),
          TextButton.icon(
            onPressed: _openBusinessSpace,
            icon: const Icon(Icons.storefront),
            label: const Text('Espace'),
          ),
          _cartIcon(context),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child:
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                )
              : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final p = _product!;
    final title = (p['title'] ?? '').toString();
    final desc = (p['description'] ?? '').toString();

    final biz = p['businesses'];
    Map<String, dynamic>? bizMap;
    if (biz is Map) bizMap = Map<String, dynamic>.from(biz);
    if (biz is List && biz.isNotEmpty) {
      bizMap = Map<String, dynamic>.from(biz.first as Map);
    }
    final slug = (bizMap?['slug'] ?? '').toString();

    final items = _galleryItems(allowVideo: _videoSupported);
    final imageUrlById = <String, String>{
      for (final it in items)
        if (it.type.toLowerCase() == 'image') it.id: it.url,
    };
    final posterUrl = _posterUrl();

    num? basePrice = p['price_amount'] as num?;
    String baseCur = (p['currency'] ?? 'XOF').toString();

    final variant = _selectedVariant;
    final coverMediaId = (variant == null) ? '' : _variantCoverMediaId(variant);

    final initialMediaId = _resolveInitialMediaId(items, preferredMediaId: coverMediaId);
    if (variant != null && variant['price_amount'] is num) {
      basePrice = variant['price_amount'] as num;
      baseCur = (variant['currency'] ?? baseCur).toString();
    }

    final priceText = (basePrice == null) ? '—' : '$basePrice $baseCur';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (items.isNotEmpty && initialMediaId != null)
          _ProductMediaGallery(
            key: ValueKey('${widget.productId}|${_selectedVariantId ?? ''}|$initialMediaId'),
            items: items,
            initialMediaId: initialMediaId,
            videoSupported: _videoSupported,
            posterUrl: posterUrl,
            active: _pageActive,
            muted: _muted,
            onToggleMute: () => setState(() => _muted = !_muted),
          ),
        const SizedBox(height: 14),
        Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        if (desc.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(desc),
        ],
        const SizedBox(height: 14),

        if (_variants.isNotEmpty) ...[
          const Text('Variantes', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _variants.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final scheme = Theme.of(context).colorScheme;

                if (i == 0) {
                  final selected = _selectedVariantId == null;
                  return InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() => _selectedVariantId = null),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: selected ? scheme.primary.withAlpha(18) : scheme.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected ? scheme.primary : scheme.outlineVariant,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'Standard',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  );
                }

                final v = _variants[i - 1];
                final id = v['id']?.toString() ?? '';
                final t = (v['title'] ?? 'Variante').toString();
                final pr = v['price_amount'];
                final cur = (v['currency'] ?? baseCur).toString();
                final subtitle = (pr is num) ? '$pr $cur' : '—';

                final coverId = _variantCoverMediaId(v);
                final coverUrl = coverId.isEmpty ? null : imageUrlById[coverId];

                final selected = _selectedVariantId == id;

                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: id.isEmpty ? null : () => setState(() => _selectedVariantId = id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? scheme.primary.withAlpha(18) : scheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? scheme.primary : scheme.outlineVariant,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: coverUrl == null
                              ? Icon(Icons.image_outlined, color: scheme.onSurfaceVariant)
                              : Image.network(
                                  coverUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
                                ),
                        ),
                        const SizedBox(width: 10),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 170),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                t,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  height: 1.0,
                                ),
                              ),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],

        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Text('Prix', style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(priceText,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),
        SizedBox(
          height: 46,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _addToCartAndOpen,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
            icon: const Icon(Icons.shopping_cart_checkout),
            label: const Text('Commander'),
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 520;

            final cartBtn = SizedBox(
              height: 44,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/cart'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
                icon: const Icon(Icons.shopping_cart_outlined),
                label: const Text('Panier'),
              ),
            );

            final shopBtn = SizedBox(
              height: 44,
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: slug.isEmpty ? null : () => context.push('/b/$slug'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Boutique'),
              ),
            );

            if (!wide) {
              return Column(
                children: [
                  cartBtn,
                  const SizedBox(height: 10),
                  shopBtn,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: cartBtn),
                const SizedBox(width: 10),
                Expanded(child: shopBtn),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _GalleryItem {
  final String id;
  final String type; // image | video
  final String url;

  const _GalleryItem({
    required this.id,
    required this.type,
    required this.url,
  });
}

class _ProductMediaGallery extends StatefulWidget {
  final List<_GalleryItem> items;
  final String initialMediaId;
  final bool videoSupported;
  final String? posterUrl;
  final bool active;
  final bool muted;
  final VoidCallback onToggleMute;

  const _ProductMediaGallery({
    super.key,
    required this.items,
    required this.initialMediaId,
    required this.videoSupported,
    required this.posterUrl,
    required this.active,
    required this.muted,
    required this.onToggleMute,
  });

  @override
  State<_ProductMediaGallery> createState() => _ProductMediaGalleryState();
}

class _ProductMediaGalleryState extends State<_ProductMediaGallery> {
  late final PageController _pages;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = _initialIndex();
    _pages = PageController(initialPage: _index);
  }

  int _initialIndex() {
    final idx = widget.items.indexWhere((i) => i.id == widget.initialMediaId);
    return idx < 0 ? 0 : idx;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int next) {
    if (next < 0 || next >= widget.items.length) return;
    _pages.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();

    final current = items[_index];
    final isVideo = current.type.toLowerCase() == 'video';
    final aspect = isVideo ? (16 / 9) : (4 / 3);
    final screenH = MediaQuery.sizeOf(context).height;

    return LayoutBuilder(
      builder: (context, c) {
        double maxH = screenH * 0.55;
        final hardMaxH = isVideo ? 560.0 : 680.0;
        if (maxH > hardMaxH) maxH = hardMaxH;
        if (maxH < 320) maxH = 320;

        final showSideThumbs = items.length > 1 && c.maxWidth >= 900;
        final thumbExtent = showSideThumbs ? 76.0 : 62.0;

        double maxW = isVideo ? 980 : 920;
        final byH = maxH * aspect;
        if (maxW > byH) maxW = byH;

        var w = c.maxWidth;
        if (showSideThumbs) w = w - thumbExtent - 12;
        if (w > maxW) w = maxW;
        if (w < 260) w = c.maxWidth;

        Widget hero() {
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: aspect,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _pages,
                    itemCount: items.length,
                    onPageChanged: (v) => setState(() => _index = v),
                    itemBuilder: (_, i) {
                      final it = items[i];
                      return _MediaHero(
                        url: it.url,
                        type: it.type,
                        videoSupported: widget.videoSupported,
                        posterUrl: widget.posterUrl,
                        active: widget.active,
                        muted: widget.muted,
                        onToggleMute: widget.onToggleMute,
                      );
                    },
                  ),
                  if (items.length > 1) ...[
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(120),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_index + 1}/${items.length}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: IconButton.filledTonal(
                        tooltip: 'Précédent',
                        onPressed: _index == 0 ? null : () => _go(_index - 1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: IconButton.filledTonal(
                        tooltip: 'Suivant',
                        onPressed: _index >= items.length - 1 ? null : () => _go(_index + 1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        Widget thumbTile(_GalleryItem it, int i, {required bool vertical}) {
          final selected = i == _index;
          final t = it.type.toLowerCase();
          final isVideoThumb = t == 'video';
          final size = vertical ? 64.0 : 58.0;

          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _go(i),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
                color: scheme.surfaceContainerHighest,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!isVideoThumb)
                    Image.network(
                      it.url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)),
                    )
                  else
                    Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      child: const Icon(Icons.play_arrow, color: Colors.white),
                    ),
                  if (isVideoThumb)
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Container(
                        margin: const EdgeInsets.all(6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(140),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.videocam, size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        if (showSideThumbs) {
          final heroH = w / aspect;
          final thumbsH = heroH < 220 ? 220.0 : heroH;

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: thumbExtent,
                height: thumbsH,
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => thumbTile(items[i], i, vertical: true),
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: w),
                child: hero(),
              ),
            ],
          );
        }

        return Column(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: w),
                child: hero(),
              ),
            ),
            if (items.length > 1) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 58,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => thumbTile(items[i], i, vertical: false),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _MediaHero extends StatelessWidget {
  final String url;
  final String type; // image | video
  final bool videoSupported;
  final String? posterUrl;
  final bool active; // route visible + app resumed
  final bool muted;
  final VoidCallback onToggleMute;

  const _MediaHero({
    required this.url,
    required this.type,
    required this.videoSupported,
    required this.posterUrl,
    required this.active,
    required this.muted,
    required this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    final t = type.toLowerCase();
    final scheme = Theme.of(context).colorScheme;

    if (t == 'video') {
      if (!videoSupported) {
        final p = posterUrl;
        if (p != null && p.isNotEmpty) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black),
              Image.network(p, fit: BoxFit.contain),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(115),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Vidéo indisponible sur cet appareil',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          );
        }
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const Text(
            'Vidéo indisponible sur cet appareil',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
          ),
        );
      }

      return _VideoHero(
        url: url,
        posterUrl: posterUrl,
        active: active,
        muted: muted,
        onToggleMute: onToggleMute,
      );
    }

    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}

class _VideoHero extends StatefulWidget {
  final String url;
  final String? posterUrl;
  final bool active;
  final bool muted;
  final VoidCallback onToggleMute;

  const _VideoHero({
    required this.url,
    required this.posterUrl,
    required this.active,
    required this.muted,
    required this.onToggleMute,
  });

  @override
  State<_VideoHero> createState() => _VideoHeroState();
}

class _VideoHeroState extends State<_VideoHero> {
  VideoPlayerController? _controller;
  bool _init = false;
  String? _err;

  // If user paused manually, we do NOT auto-resume (safety + predictable UX)
  bool _userPaused = true;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void didUpdateWidget(covariant _VideoHero oldWidget) {
    super.didUpdateWidget(oldWidget);

    // URL changed => full reset
    if (oldWidget.url != widget.url) {
      _disposeController();
      _err = null;
      _init = false;
      _userPaused = true;
      _setup();
      return;
    }

    final c = _controller;
    if (!_init || c == null) return;

    // If page not active => hard stop (pause + volume 0)
    if (!widget.active) {
      _userPaused = true; // do not auto-resume when user comes back
      _pauseAndSilence(c);
      return;
    }

    // Active: apply volume
    c.setVolume(widget.muted ? 0.0 : 1.0);

    // If user had not paused and was playing, keep it playing.
    // If user paused, keep it paused.
    if (_userPaused) {
      if (c.value.isPlaying) _pauseAndSilence(c);
    }
  }

  Future<void> _setup() async {
    try {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
        ),
      );
      _controller = c;

      await c.initialize();
      c.setLooping(true);

      if (!mounted) return;
      setState(() => _init = true);

      // Start paused by default (user taps to play).
      _pauseAndSilence(c);

      // Apply current mute state even while paused
      c.setVolume(widget.muted ? 0.0 : 1.0);

      // If page not active, enforce silence
      if (!widget.active) {
        _userPaused = true;
        _pauseAndSilence(c);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    }
  }

  void _pauseAndSilence(VideoPlayerController c) {
    if (c.value.isPlaying) c.pause();
    c.setVolume(0.0);
  }

  void _disposeController() {
    final c = _controller;
    _controller = null;
    _init = false;
    if (c != null) {
      _pauseAndSilence(c);
      c.dispose();
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _toggle() {
    final c = _controller;
    if (c == null || !_init) return;

    // If page is not active, never play
    if (!widget.active) {
      _userPaused = true;
      _pauseAndSilence(c);
      return;
    }

    setState(() {
      if (c.value.isPlaying) {
        _userPaused = true;
        _pauseAndSilence(c);
      } else {
        _userPaused = false;
        c.setVolume(widget.muted ? 0.0 : 1.0);
        c.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null) {
      final poster = widget.posterUrl;
      if ((poster ?? '').isNotEmpty) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            Image.network(poster!, fit: BoxFit.contain),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(115),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Vidéo indisponible',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        );
      }
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Text(
          'Vidéo indisponible',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    if (!_init || _controller == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    final c = _controller!;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.black),
        FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: c.value.size.width,
            height: c.value.size.height,
            child: VideoPlayer(c),
          ),
        ),

        // Tap anywhere: play/pause
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(onTap: _toggle),
          ),
        ),

        // Play overlay
        Align(
          alignment: Alignment.center,
          child: AnimatedOpacity(
            opacity: c.value.isPlaying ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 180),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(115),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 44),
            ),
          ),
        ),

        // Mute button (video-level)
        Positioned(
          right: 12,
          top: 12,
          child: IconButton.filledTonal(
            onPressed: widget.onToggleMute,
            icon: Icon(widget.muted ? Icons.volume_off : Icons.volume_up),
          ),
        ),
      ],
    );
  }
}
