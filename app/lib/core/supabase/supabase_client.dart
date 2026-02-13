import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseX {
  static SupabaseClient get client => Supabase.instance.client;

  static String? get userId => client.auth.currentUser?.id;
  static bool get isAuthenticated => userId != null;
}
