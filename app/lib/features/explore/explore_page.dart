import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../cart/cart_scope.dart';
import '../cart/cart_service.dart';

// Ajuste le chemin selon ton projet :
import '../../core/route_observer.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> with RouteAware, WidgetsBindingObserver {
  final _sb = Supabase.instance.client;

  final _pageController = PageController();
  final _items = <_ExploreItem>[];

  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  static const _pageSize = 20;

  static const _productMediaBucket = 'product_media';
  static const _businessLogosBucket = 'business_logos';

  // UX
  int _currentIndex = 0;
  bool _videoAutoplay = true;

  // Son OFF par défaut
  bool _muted = true;

  // Visibilité de la route + app lifecycle
  bool _routeVisible = true;
  bool _appResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _loadInitial();
    _pageController.addListener(_onPageChangedListener);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);

    _pageController.removeListener(_onPageChangedListener);
    _pageController.dispose();
    super.dispose();
  }

  // RouteAware
  @override
  void didPushNext() {
    // Une nouvelle page couvre Explore => couper autoplay => pause/silence
    if (!mounted) return;
    setState(() => _routeVisible = false);
  }

  @override
  void didPopNext() {
    // Retour sur Explore
    if (!mounted) return;
    setState(() => _routeVisible = true);
  }

  // App lifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (!mounted) return;
    setState(() => _appResumed = resumed);
  }

  void _onPageChangedListener() {
    final page = _pageController.page;
    if (page == null) return;
    final idx = page.round();
    if (idx != _currentIndex && idx >= 0 && idx < max(1, _items.length)) {
      setState(() => _currentIndex = idx);
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _hasMore = true;
      _currentIndex = 0;
    });

    try {
      await _loadMore(reset: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loadingMore) return;
    if (!_hasMore && !reset) return;

    setState(() => _loadingMore = true);

    final offset = reset ? 0 : _items.length;

    final resp = await _sb
        .from('products')
        .select('''
          id,title,description,price_amount,currency,created_at,business_id,
          businesses(id,name,slug,logo_path),
          product_media!inner(id,media_type,storage_path)
        ''')
        .eq('is_active', true)
        .not('price_amount', 'is', null)
        .order('created_at', ascending: false)
        .range(offset, offset + _pageSize - 1);

    final rows = (resp as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    final newItems = rows
        .map(_ExploreItem.fromRow)
        .where((x) => x.businessSlug.isNotEmpty && (x.mediaPath ?? '').isNotEmpty)
        .toList();

    if (!mounted) return;
    setState(() {
      if (reset) _items.clear();
      _items.addAll(newItems);
      _hasMore = rows.length == _pageSize;
      _loadingMore = false;

      if (_currentIndex >= _items.length) {
        _currentIndex = max(0, _items.length - 1);
      }
    });
  }

  String? _productMediaUrl(_ExploreItem item) {
    final path = item.mediaPath;
    if (path == null || path.isEmpty) return null;
    return _sb.storage.from(_productMediaBucket).getPublicUrl(path);
  }

  String? _posterUrl(_ExploreItem item) {
    final logoPath = item.businessLogoPath;
    if (logoPath == null || logoPath.isEmpty) return null;
    return _sb.storage.from(_businessLogosBucket).getPublicUrl(logoPath);
  }

  Future<void> _addToCartAndOpen(_ExploreItem item, String? mediaUrl) async {
    final cart = CartScope.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (item.priceAmount == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Prix non défini pour ce produit.')));
      return;
    }

    try {
      cart.add(
        productId: item.productId,
        businessId: item.businessId,
        title: item.title,
        unitPrice: item.priceAmount!,
        currency: item.currency,
        mediaUrl: mediaUrl,
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
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Vider')),
          ],
        ),
      );

      if (ok == true) {
        cart.clear();
        cart.add(
          productId: item.productId,
          businessId: item.businessId,
          title: item.title,
          unitPrice: item.priceAmount!,
          currency: item.currency,
          mediaUrl: mediaUrl,
          qty: 1,
        );
        messenger.showSnackBar(const SnackBar(content: Text('Nouveau panier créé')));
        if (!mounted) return;
        context.push('/cart');
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Erreur panier: $e')));
    }
  }

  Widget _cartIcon(BuildContext context) {
    final cart = CartScope.of(context);

    return AnimatedBuilder(
      animation: cart,
      builder: (context, child) {
        final qty = cart.totalQty;
        return Stack(
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$qty',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _openBusinessSpace() {
    final user = _sb.auth.currentUser;
    if (user == null) {
      final next = Uri.encodeComponent('/home');
      context.push('/login?next=$next');
    } else {
      context.go('/home');
    }
  }

  bool get _canPlayMediaNow => _routeVisible && _appResumed;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null)
                ? _ErrorView(message: _error!, onRetry: _loadInitial)
                : NotificationListener<ScrollNotification>(
                    onNotification: (_) {
                      final page = _pageController.hasClients ? (_pageController.page ?? 0) : 0;
                      if (_hasMore && !_loadingMore && page >= max(0, _items.length - 3)) {
                        _loadMore();
                      }
                      return false;
                    },
                    child: PageView.builder(
                      controller: _pageController,
                      scrollDirection: Axis.vertical,
                      physics: const _SnappyPageScrollPhysics(),
                      itemCount: max(1, _items.length),
                      itemBuilder: (context, index) {
                        if (_items.isEmpty) {
                          return _EmptyExplore(onRefresh: _loadInitial, onOpenBusinessSpace: _openBusinessSpace);
                        }

                        final item = _items[index];
                        final mediaUrl = _productMediaUrl(item);
                        final posterUrl = _posterUrl(item);

                        final isActivePage = index == _currentIndex;

                        // Pré-charger page voisine
                        final preload = (index == _currentIndex) || (index == _currentIndex + 1) || (index == _currentIndex - 1);

                        // IMPORTANT: autoplay seulement si route visible + app resumed
                        final allowAutoplay = _videoAutoplay && isActivePage && _canPlayMediaNow;

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            GestureDetector(
                              onTap: () => context.push('/p/${item.productId}'),
                              child: _MediaBackground(
                                mediaUrl: mediaUrl,
                                posterUrl: posterUrl,
                                mediaType: item.mediaType,
                                autoplay: allowAutoplay,
                                preload: preload && _canPlayMediaNow,
                                muted: _muted,
                                onToggleMute: () => setState(() => _muted = !_muted),
                              ),
                            ),
                            const _BottomGradient(),
                            _OverlayInfo(
                              item: item,
                              onOpenBusiness: () => context.push('/b/${item.businessSlug}'),
                              onOpenProduct: () => context.push('/p/${item.productId}'),
                              onAddToCart: () => _addToCartAndOpen(item, mediaUrl),
                            ),
                            Positioned(
                              top: MediaQuery.of(context).padding.top + 10,
                              left: 16,
                              right: 16,
                              child: Row(
                                children: [
                                  const Text('Explorer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: _openBusinessSpace,
                                    icon: const Icon(Icons.store_mall_directory_outlined),
                                    label: const Text('Espace entreprise'),
                                  ),
                                  _cartIcon(context),

                                  IconButton(
                                    tooltip: _videoAutoplay ? 'Auto-play: ON' : 'Auto-play: OFF',
                                    onPressed: () => setState(() => _videoAutoplay = !_videoAutoplay),
                                    icon: Icon(_videoAutoplay ? Icons.play_circle : Icons.pause_circle),
                                  ),

                                  IconButton(
                                    tooltip: _muted ? 'Son: OFF' : 'Son: ON',
                                    onPressed: () => setState(() => _muted = !_muted),
                                    icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
                                  ),

                                  IconButton(
                                    tooltip: 'Rafraîchir',
                                    onPressed: _loadInitial,
                                    icon: const Icon(Icons.refresh),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}

class _ExploreItem {
  final String productId;
  final String title;
  final String? description;
  final num? priceAmount;
  final String currency;

  final String businessId;
  final String businessName;
  final String businessSlug;
  final String? businessLogoPath;

  final String? mediaType;
  final String? mediaPath;

  _ExploreItem({
    required this.productId,
    required this.title,
    required this.description,
    required this.priceAmount,
    required this.currency,
    required this.businessId,
    required this.businessName,
    required this.businessSlug,
    required this.businessLogoPath,
    required this.mediaType,
    required this.mediaPath,
  });

  static _ExploreItem fromRow(Map<String, dynamic> row) {
    final biz = row['businesses'];
    Map<String, dynamic>? bizMap;
    if (biz is Map) bizMap = Map<String, dynamic>.from(biz);
    if (biz is List && biz.isNotEmpty) bizMap = Map<String, dynamic>.from(biz.first as Map);

    final media = row['product_media'];
    Map<String, dynamic>? m0;
    if (media is List && media.isNotEmpty) m0 = Map<String, dynamic>.from(media.first as Map);
    if (media is Map) m0 = Map<String, dynamic>.from(media);

    return _ExploreItem(
      productId: (row['id'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      description: row['description']?.toString(),
      priceAmount: row['price_amount'] as num?,
      currency: (row['currency'] ?? 'XOF').toString(),
      businessId: (row['business_id'] ?? '').toString(),
      businessName: (bizMap?['name'] ?? '').toString(),
      businessSlug: (bizMap?['slug'] ?? '').toString(),
      businessLogoPath: (bizMap?['logo_path'])?.toString(),
      mediaType: m0?['media_type']?.toString(),
      mediaPath: m0?['storage_path']?.toString(),
    );
  }
}

class _MediaBackground extends StatelessWidget {
  final String? mediaUrl;
  final String? posterUrl;
  final String? mediaType;
  final bool autoplay;
  final bool preload;
  final bool muted;
  final VoidCallback onToggleMute;

  const _MediaBackground({
    required this.mediaUrl,
    required this.posterUrl,
    required this.mediaType,
    required this.autoplay,
    required this.preload,
    required this.muted,
    required this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    if (mediaUrl == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.image_not_supported)),
      );
    }

    final mt = (mediaType ?? '').toLowerCase();

    if (mt == 'video') {
      return _VideoBackground(
        url: mediaUrl!,
        posterUrl: posterUrl,
        autoplay: autoplay,
        preload: preload,
        muted: muted,
        onToggleMute: onToggleMute,
      );
    }

    return _ProImage(url: mediaUrl!);
  }
}

class _ProImage extends StatelessWidget {
  final String url;
  const _ProImage({required this.url});

  @override
  Widget build(BuildContext context) {
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
          child: Container(color: Colors.black.withAlpha(31)),
        ),
        Center(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image)),
          ),
        ),
      ],
    );
  }
}

class _VideoBackground extends StatefulWidget {
  final String url;
  final String? posterUrl;
  final bool autoplay;
  final bool preload;
  final bool muted;
  final VoidCallback onToggleMute;

  const _VideoBackground({
    required this.url,
    required this.posterUrl,
    required this.autoplay,
    required this.preload,
    required this.muted,
    required this.onToggleMute,
  });

  @override
  State<_VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<_VideoBackground> {
  VideoPlayerController? _controller;
  bool _init = false;
  String? _err;

  // IMPORTANT: respecte pause manuelle (autoplay ne relance pas derrière)
  bool _userPaused = false;

  @override
  void initState() {
    super.initState();
    if (widget.preload || widget.autoplay) {
      _setup();
    }
  }

  @override
  void didUpdateWidget(covariant _VideoBackground oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.url != widget.url) {
      _disposeController();
      _err = null;
      _init = false;
      _userPaused = false;
      if (widget.preload || widget.autoplay) {
        _setup();
      }
      return;
    }

    if ((_controller == null || !_init) && (widget.preload || widget.autoplay) && _err == null) {
      _setup();
      return;
    }

    final c = _controller;
    if (!_init || c == null) return;

    // Si la page n’est pas active => pause + silence forcé
    if (!widget.autoplay) {
      // Quand on quitte la page active, on reset la pause manuelle (comportement type TikTok)
      if (oldWidget.autoplay == true && widget.autoplay == false) {
        _userPaused = false;
      }
      _pauseAndSilence(c);
      return;
    }

    // Page active: si l’utilisateur a mis pause, on respecte
    if (_userPaused) {
      _pauseAndSilence(c);
      return;
    }

    // Sinon autoplay normal
    c.setVolume(widget.muted ? 0.0 : 1.0);
    if (!c.value.isPlaying) c.play();
  }

  Future<void> _setup() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _controller = c;

      await c.initialize();
      c.setLooping(true);

      if (!mounted) return;
      setState(() => _init = true);

      if (widget.autoplay && !_userPaused) {
        c.setVolume(widget.muted ? 0.0 : 1.0);
        c.play();
      } else {
        _pauseAndSilence(c);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    }
  }

  void _pauseAndSilence(VideoPlayerController c) {
    // “hard stop” audio
    if (c.value.isPlaying) {
      c.pause();
    }
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

  void _togglePlay() {
    final c = _controller;
    if (!_init || c == null) return;

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
      if ((widget.posterUrl ?? '').isNotEmpty) {
        return Stack(
          fit: StackFit.expand,
          children: [
            _ProImage(url: widget.posterUrl!),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(115),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Vidéo indisponible',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        );
      }
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Text('Vidéo indisponible', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
      );
    }

    if (!_init || _controller == null) {
      if ((widget.posterUrl ?? '').isNotEmpty) {
        return Stack(
          fit: StackFit.expand,
          children: [
            _ProImage(url: widget.posterUrl!),
            const Center(child: Icon(Icons.play_circle_fill, size: 64, color: Colors.white70)),
          ],
        );
      }
      return Container(color: Colors.black, alignment: Alignment.center, child: const CircularProgressIndicator());
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

        Positioned.fill(
          child: Material(color: Colors.transparent, child: InkWell(onTap: _togglePlay)),
        ),

        Align(
          alignment: Alignment.center,
          child: AnimatedOpacity(
            opacity: c.value.isPlaying ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 160),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.black.withAlpha(115), shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 44),
            ),
          ),
        ),

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

class _SnappyPageScrollPhysics extends PageScrollPhysics {
  const _SnappyPageScrollPhysics({super.parent});

  @override
  _SnappyPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _SnappyPageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingDistance => 5.0;

  @override
  double get minFlingVelocity => 180.0;

  @override
  double get dragStartDistanceMotionThreshold => 2.0;
}

class _BottomGradient extends StatelessWidget {
  const _BottomGradient();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 260,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black54, Colors.black87],
          ),
        ),
      ),
    );
  }
}

class _OverlayInfo extends StatelessWidget {
  final _ExploreItem item;
  final VoidCallback onOpenBusiness;
  final VoidCallback onOpenProduct;
  final VoidCallback onAddToCart;

  const _OverlayInfo({
    required this.item,
    required this.onOpenBusiness,
    required this.onOpenProduct,
    required this.onAddToCart,
  });

  String _price() {
    if (item.priceAmount == null) return '';
    return '${item.priceAmount} ${item.currency}';
  }

  @override
  Widget build(BuildContext context) {
    final canOrder = item.priceAmount != null;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: onOpenBusiness,
                  child: Text(
                    '@${item.businessSlug} • ${item.businessName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                ),
                if ((item.description ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(item.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
                ],
                const SizedBox(height: 8),
                if (_price().isNotEmpty) Text(_price(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(onPressed: onOpenProduct, child: const Text('Voir')),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: canOrder ? onAddToCart : null,
                icon: const Icon(Icons.shopping_cart_checkout),
                label: const Text('Commander'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: onOpenBusiness,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Boutique'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}

class _EmptyExplore extends StatelessWidget {
  final VoidCallback onRefresh;
  final VoidCallback onOpenBusinessSpace;

  const _EmptyExplore({required this.onRefresh, required this.onOpenBusinessSpace});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Aucun produit publié pour le moment.'),
            const SizedBox(height: 10),
            FilledButton(onPressed: onRefresh, child: const Text('Rafraîchir')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onOpenBusinessSpace,
              icon: const Icon(Icons.store_mall_directory_outlined),
              label: const Text('Espace entreprise'),
            ),
          ],
        ),
      ),
    );
  }
}
