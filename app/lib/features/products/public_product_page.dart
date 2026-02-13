import 'dart:ui' show ImageFilter;

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
      final p = await _sb
          .from('products')
          .select(
            'id,title,description,price_amount,currency,business_id,'
            'businesses(id,name,slug),'
            'product_media(id,media_type,storage_path)',
          )
          .eq('id', widget.productId)
          .maybeSingle();

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
        _product = Map<String, dynamic>.from(p as Map);
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

  ({String? url, String? type}) _primaryMedia() {
    final list = _mediaList();
    if (list.isEmpty) return (url: null, type: null);

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
  String? _mediaUrlForCart() => _primaryMedia().url;

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

    final media = _primaryMedia();
    final mediaUrl = media.url;
    final mediaType = (media.type ?? '').toLowerCase();

    num? basePrice = p['price_amount'] as num?;
    String baseCur = (p['currency'] ?? 'XOF').toString();

    final variant = _selectedVariant;
    if (variant != null && variant['price_amount'] is num) {
      basePrice = variant['price_amount'] as num;
      baseCur = (variant['currency'] ?? baseCur).toString();
    }

    final priceText = (basePrice == null) ? '—' : '$basePrice $baseCur';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (mediaUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 1,
              child: _MediaHero(
                url: mediaUrl,
                type: mediaType,
                active: _pageActive,
                muted: _muted,
                onToggleMute: () => setState(() => _muted = !_muted),
              ),
            ),
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
          const Text('Variante', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedVariantId,
            decoration: const InputDecoration(labelText: 'Choisir une variante'),
            items: _variants.map((v) {
              final id = v['id']?.toString() ?? '';
              final t = (v['title'] ?? 'Variante').toString();
              final pr = v['price_amount'];
              final cur = (v['currency'] ?? baseCur).toString();
              final subtitle = (pr is num) ? ' — $pr $cur' : '';
              return DropdownMenuItem(
                value: id,
                child: Text('$t$subtitle',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (val) => setState(() => _selectedVariantId = val),
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
        FilledButton.icon(
          onPressed: _addToCartAndOpen,
          icon: const Icon(Icons.shopping_cart_checkout),
          label: const Text('Commander'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => context.push('/cart'),
          icon: const Icon(Icons.shopping_cart_outlined),
          label: const Text('Voir le panier'),
        ),

        const SizedBox(height: 12),
        FilledButton(
          onPressed: slug.isEmpty ? null : () => context.push('/b/$slug'),
          child: const Text('Voir la boutique'),
        ),
      ],
    );
  }
}

class _MediaHero extends StatelessWidget {
  final String url;
  final String type; // image | video
  final bool active; // route visible + app resumed
  final bool muted;
  final VoidCallback onToggleMute;

  const _MediaHero({
    required this.url,
    required this.type,
    required this.active,
    required this.muted,
    required this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    final t = type.toLowerCase();

    if (t == 'video') {
      return _VideoHero(
        url: url,
        active: active,
        muted: muted,
        onToggleMute: onToggleMute,
      );
    }

    // IMAGE: blur background + contain foreground
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(child: Icon(Icons.broken_image)),
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(color: Colors.black.withAlpha(38)),
        ),
        Center(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
          ),
        ),
      ],
    );
  }
}

class _VideoHero extends StatefulWidget {
  final String url;
  final bool active;
  final bool muted;
  final VoidCallback onToggleMute;

  const _VideoHero({
    required this.url,
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
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Text(
          'Impossible de lire la vidéo.\n$_err',
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
        FittedBox(
          fit: BoxFit.cover,
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
