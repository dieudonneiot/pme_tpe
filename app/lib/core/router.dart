import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'router_refresh.dart';
import 'route_observer.dart';

import '../features/auth/auth_callback_page.dart';
import '../features/auth/login_page.dart';
import '../features/admin/admin_categories_page.dart';
import '../features/admin/admin_entitlements_page.dart';
import '../features/business/business_domains_page.dart';
import '../features/business/business_hours_page.dart';
import '../features/business/business_billing_page.dart';
import '../features/business/business_links_page.dart';
import '../features/business/business_members_page.dart';
import '../features/business/business_settings_page.dart';
import '../features/business/create_business_page.dart';
import '../features/business/public_business_page.dart';
import '../features/cart/cart_page.dart';
import '../features/cart/checkout_page.dart';
import '../features/explore/explore_businesses_page.dart';
import '../features/home/home_page.dart';
import '../features/notifications/notifications_page.dart';
import '../features/posts/business_posts_page.dart';
import '../features/products/business_products_page.dart';
import '../features/products/business_inventory_page.dart';
import '../features/products/product_detail_page.dart';
import '../features/products/public_product_page.dart';
import '../features/public/landing_page.dart';
import '../features/requests/business_requests_page.dart';
import '../features/requests/customer_payment_status_page.dart';
import '../features/requests/customer_orders_page.dart';
import '../features/requests/request_hub_page.dart';
import '../features/requests/request_detail_page.dart';

final _authRefresh = GoRouterRefreshStream(
  Supabase.instance.client.auth.onAuthStateChange,
);

final appRouter = GoRouter(
  refreshListenable: _authRefresh,
  observers: [routeObserver],
  initialLocation: '/',
  redirect: (context, state) {
    final path = state.uri.path;

    final session = Supabase.instance.client.auth.currentSession;
    final loggedIn = session != null;

    final isLogin = path == '/login';
    final isCallback = path == '/auth/callback';
    final isHome = path == '/home';

    // Public routes
    final isExplore = path == '/explore';
    final isLanding = path == '/';
    final isPublicBusiness = path.startsWith('/b/');
    final isPublicProduct = path.startsWith('/p/');
    final isCart = path == '/cart';

    if (!loggedIn) {
      // If the user logs out while on the dashboard, prefer returning to the public home.
      if (isHome) return '/';

      if (isLogin ||
          isCallback ||
          isLanding ||
          isExplore ||
          isCart ||
          isPublicBusiness ||
          isPublicProduct) {
        return null;
      }
      final next = Uri.encodeComponent(state.uri.toString());
      return '/login?next=$next';
    }

    if (isLogin || isCallback) {
      final next = state.uri.queryParameters['next']?.trim();
      if (next != null && next.isNotEmpty && next.startsWith('/')) return next;
      return '/home';
    }
    return null;
  },
  routes: [
    // PUBLIC
    GoRoute(path: '/', builder: (_, _) => const LandingPage()),
    GoRoute(
      path: '/explore',
      builder: (_, state) => ExploreBusinessesPage(
        key: ValueKey(state.uri.toString()),
        initialCategoryId: state.uri.queryParameters['category'] ?? '',
        initialQuery: state.uri.queryParameters['q'] ?? '',
        initialRegion: state.uri.queryParameters['region'] ?? '',
      ),
    ),
    GoRoute(
      path: '/b/:slug',
      builder: (_, state) =>
          PublicBusinessPage(slug: state.pathParameters['slug']!),
    ),
    GoRoute(
      path: '/p/:id',
      builder: (_, state) =>
          PublicProductPage(productId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/cart', builder: (_, _) => const CartPage()),

    // AUTH
    GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
    GoRoute(
      path: '/auth/callback',
      builder: (_, _) => const AuthCallbackPage(),
    ),

    // APP (protégé)
    GoRoute(path: '/home', builder: (_, _) => const HomePage()),
    GoRoute(path: '/checkout', builder: (_, _) => const CheckoutPage()),
    GoRoute(path: '/notifications', builder: (_, _) => const NotificationsPage()),
    GoRoute(path: '/my/orders', builder: (_, _) => const CustomerOrdersPage()),
    GoRoute(
      path: '/requests/:rid',
      builder: (_, state) =>
          RequestHubPage(requestId: state.pathParameters['rid']!),
    ),
    GoRoute(
      path: '/requests/:rid/payment',
      builder: (_, state) =>
          CustomerPaymentStatusPage(requestId: state.pathParameters['rid']!),
    ),
    GoRoute(path: '/admin/categories', builder: (_, _) => const AdminCategoriesPage()),
    GoRoute(path: '/admin/entitlements', builder: (_, _) => const AdminEntitlementsPage()),
    GoRoute(
      path: '/business/create',
      builder: (_, _) => const CreateBusinessPage(),
    ),
    GoRoute(
      path: '/business/:id/settings',
      builder: (_, state) =>
          BusinessSettingsPage(businessId: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'billing',
          builder: (_, state) =>
              BusinessBillingPage(businessId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'hours',
          builder: (_, state) =>
              BusinessHoursPage(businessId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'links',
          builder: (_, state) =>
              BusinessLinksPage(businessId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'domains',
          builder: (_, state) =>
              BusinessDomainsPage(businessId: state.pathParameters['id']!),
        ),
      ],
    ),

    // Products
    GoRoute(
      path: '/business/:id/products',
      builder: (_, state) =>
          BusinessProductsPage(businessId: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: ':pid',
          builder: (_, state) => ProductDetailPage(
            businessId: state.pathParameters['id']!,
            productId: state.pathParameters['pid']!,
          ),
        ),
      ],
    ),

    GoRoute(
      path: '/business/:id/inventory',
      builder: (_, state) =>
          BusinessInventoryPage(businessId: state.pathParameters['id']!),
    ),

    GoRoute(
      path: '/business/:id/members',
      builder: (_, state) =>
          BusinessMembersPage(businessId: state.pathParameters['id']!),
    ),

    // Requests
    GoRoute(
      path: '/business/:id/requests',
      builder: (_, state) =>
          BusinessRequestsPage(businessId: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: ':rid',
          builder: (_, state) => RequestDetailPage(
            businessId: state.pathParameters['id']!,
            requestId: state.pathParameters['rid']!,
          ),
        ),
      ],
    ),

    // Posts
    GoRoute(
      path: '/business/:id/posts',
      builder: (_, state) =>
          BusinessPostsPage(businessId: state.pathParameters['id']!),
    ),
  ],
);
