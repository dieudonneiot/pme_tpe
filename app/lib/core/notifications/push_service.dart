import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';
import '../router.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// Handler background: doit être top-level / static.
  @pragma('vm:entry-point')
  static Future<void> firebaseMessagingBackgroundHandler(
    RemoteMessage message,
  ) async {
    await Firebase.initializeApp();
  }

  static Future<void> init() async {
    // 1) Local notifications init
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        // Optional payload handling
      },
    );

    // 2) Background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 3) iOS: show notifications while app is in foreground.
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

    // 4) Listeners runtime
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // 5) Cold start: app opened from a notification
    final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMsg != null) {
      _handleDeepLinkFromMessage(initialMsg);
    }

    // 6) Token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      await upsertCurrentUserToken(token: token);
    });
  }

  static Future<void> requestPermissionAndSyncToken() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    String? token;
    if (kIsWeb) {
      if (Env.fcmVapidKey.isEmpty) {
        debugPrint(
          'FCM_VAPID_KEY manquante (Web). Lance avec --dart-define=FCM_VAPID_KEY=...',
        );
        return;
      }
      token = await FirebaseMessaging.instance.getToken(
        vapidKey: Env.fcmVapidKey,
      );
    } else {
      token = await FirebaseMessaging.instance.getToken();
    }

    if (token != null) {
      await upsertCurrentUserToken(token: token);
    }
  }

  static Future<void> upsertCurrentUserToken({required String token}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final platform = _platformString();
    final pkg = await PackageInfo.fromPlatform();
    final deviceId = await _deviceIdSafe();

    await Supabase.instance.client.from('device_tokens').upsert(
      {
        'user_id': user.id,
        'token': token,
        'platform': platform,
        'app_id': pkg.packageName,
        'app_version': pkg.version,
        'device_id': deviceId,
        'last_seen_at': DateTime.now().toIso8601String(),
        'revoked_at': null,
      },
      // Requires UNIQUE(token) on DB side
      onConflict: 'token',
    );
  }

  static Future<void> revokeCurrentToken() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    if (kIsWeb && Env.fcmVapidKey.isEmpty) return;

    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb ? Env.fcmVapidKey : null,
    );

    if (token == null) return;

    await Supabase.instance.client
        .from('device_tokens')
        .update({'revoked_at': DateTime.now().toIso8601String()})
        .eq('user_id', user.id)
        .eq('token', token);
  }

  static Future<void> _onForegroundMessage(RemoteMessage msg) async {
    // In foreground, Android does not always show system notifications.
    final title = msg.notification?.title ?? 'Notification';
    final body = msg.notification?.body ?? '';

    const androidDetails = AndroidNotificationDetails(
      'default_channel',
      'General',
      importance: Importance.max,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: msg.data['deep_link'] as String?,
    );
  }

  static Future<void> _onMessageOpenedApp(RemoteMessage msg) async {
    _handleDeepLinkFromMessage(msg);
  }

  static void _handleDeepLinkFromMessage(RemoteMessage msg) {
    final deepLink = msg.data['deep_link']?.toString();
    if (deepLink == null || deepLink.isEmpty) return;

    final location = _locationFromDeepLink(deepLink);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        appRouter.go(location);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Deep link navigation failed: $deepLink -> $location');
          debugPrint(e.toString());
        }
      }
    });
  }

  static String _locationFromDeepLink(String input) {
    final s = input.trim();
    if (s.isEmpty) return '/';

    try {
      final uri = Uri.parse(s);
      if (uri.hasScheme) {
        final q = uri.hasQuery ? '?${uri.query}' : '';
        final f = uri.hasFragment ? '#${uri.fragment}' : '';
        final path = uri.path.isEmpty ? '/' : uri.path;
        return '$path$q$f';
      }
    } catch (_) {
      // ignore and fall back to raw input
    }

    return s.startsWith('/') ? s : '/$s';
  }

  static String _platformString() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'web';
  }

  static Future<String?> _deviceIdSafe() async {
    try {
      final di = DeviceInfoPlugin();
      if (kIsWeb) {
        final web = await di.webBrowserInfo;
        return '${web.vendor}-${web.userAgent}';
      }
      if (Platform.isAndroid) {
        final a = await di.androidInfo;
        return a.id;
      }
      if (Platform.isIOS) {
        final i = await di.iosInfo;
        return i.identifierForVendor;
      }
      if (Platform.isWindows) {
        final w = await di.windowsInfo;
        return w.deviceId;
      }
      if (Platform.isMacOS) {
        final m = await di.macOsInfo;
        return m.systemGUID;
      }
      if (Platform.isLinux) {
        final l = await di.linuxInfo;
        return l.machineId;
      }
    } catch (_) {}
    return null;
  }
}
