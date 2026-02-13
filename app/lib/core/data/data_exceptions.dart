import 'package:supabase_flutter/supabase_flutter.dart';

class DataException implements Exception {
  final String message;
  final Object? raw;
  DataException(this.message, {this.raw});

  @override
  String toString() => 'DataException(message: $message, raw: $raw)';
}

DataException mapSupabaseError(Object e) {
  if (e is PostgrestException) return DataException(e.message, raw: e);
  if (e is AuthException) return DataException(e.message, raw: e);
  return DataException(e.toString(), raw: e);
}
