class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Web only (Firebase Messaging): public VAPID key.
  static const fcmVapidKey = String.fromEnvironment(
    'FCM_VAPID_KEY',
    defaultValue: '',
  );

  static void validate() {
    if (supabaseUrl.isEmpty || !supabaseUrl.startsWith('http')) {
      throw StateError(
        'SUPABASE_URL manquant ou invalide. Lance avec --dart-define=SUPABASE_URL=...',
      );
    }
    if (supabaseAnonKey.isEmpty) {
      throw StateError(
        'SUPABASE_ANON_KEY manquant. Lance avec --dart-define=SUPABASE_ANON_KEY=...',
      );
    }
  }
}
