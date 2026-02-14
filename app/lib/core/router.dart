import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'router_refresh.dart';

import '../features/auth/auth_callback_page.dart';
import '../features/auth/login_page.dart';
import '../features/admin/admin_categories_page.dart';
import '../features/business/business_domains_page.dart';
import '../features/business/business_hours_page.dart';
import '../features/business/business_links_page.dart';
import '../features/business/business_settings_page.dart';
import '../features/business/create_business_page.dart';
import '../features/business/public_business_page.dart';
import '../features/explore/explore_businesses_page.dart';
import '../features/home/home_page.dart';
import '../features/posts/business_posts_page.dart';
import '../features/products/business_products_page.dart';
import '../features/products/product_detail_page.dart';
import '../features/public/landing_page.dart';
import '../features/requests/business_requests_page.dart';
import '../features/requests/request_detail_page.dart';

final _authRefresh = GoRouterRefreshStream(
  Supabase.instance.client.auth.onAuthStateChange,
);

final appRouter = GoRouter(
  refreshListenable: _authRefresh,
  initialLocation: '/',
  redirect: (context, state) {
    final path = state.uri.path;

    final session = Supabase.instance.client.auth.currentSession;
    final loggedIn = session != null;

    final isLogin = path == '/login';
    final isCallback = path == '/auth/callback';

    // Public routes
    final isExplore = path == '/explore';
    final isLanding = path == '/';
    final isPublicBusiness = path.startsWith('/b/');

    if (!loggedIn) {
      if (isLogin || isCallback || isLanding || isExplore || isPublicBusiness) {
        return null;
      }
      return '/login';
    }

    if (isLogin || isCallback) return '/home';
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

    // AUTH
    GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
    GoRoute(
      path: '/auth/callback',
      builder: (_, _) => const AuthCallbackPage(),
    ),

    // APP (protégé)
    GoRoute(path: '/home', builder: (_, _) => const HomePage()),
    GoRoute(path: '/admin/categories', builder: (_, _) => const AdminCategoriesPage()),
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
