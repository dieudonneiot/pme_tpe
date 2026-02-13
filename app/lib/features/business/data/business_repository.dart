import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/data_exceptions.dart';
import '../../../core/supabase/supabase_client.dart';

class BusinessRepository {
  BusinessRepository({SupabaseClient? client}) : _client = client ?? SupabaseX.client;
  final SupabaseClient _client;

  // ---------------- B1: business_hours ----------------
  Future<List<Map<String, dynamic>>> fetchBusinessHours(String businessId) async {
    try {
      final res = await _client
          .from('business_hours')
          .select()
          .eq('business_id', businessId)
          .order('day_of_week', ascending: true);
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Remplace toutes les lignes (simple et robuste).
  Future<void> replaceBusinessHours(String businessId, List<Map<String, dynamic>> rows) async {
    try {
      await _client.from('business_hours').delete().eq('business_id', businessId);
      if (rows.isEmpty) return;

      final payload = rows.map((r) => {...r, 'business_id': businessId}).toList();
      await _client.from('business_hours').insert(payload);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  // ---------------- B1: business_social_links ----------------
  Future<List<Map<String, dynamic>>> fetchSocialLinks(String businessId) async {
    try {
      final res = await _client
          .from('business_social_links')
          .select()
          .eq('business_id', businessId)
          .order('sort_order', ascending: true);
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> upsertSocialLinks(String businessId, List<Map<String, dynamic>> rows) async {
    try {
      if (rows.isEmpty) return;
      final payload = rows.map((r) => {...r, 'business_id': businessId}).toList();

      // OnConflict correspondra à la contrainte UNIQUE (business_id, platform)
      await _client.from('business_social_links').upsert(payload, onConflict: 'business_id,platform');
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  // ---------------- B1: business_domains ----------------
  Future<List<Map<String, dynamic>>> fetchDomains(String businessId) async {
    try {
      final res = await _client
          .from('business_domains')
          .select()
          .eq('business_id', businessId)
          .order('created_at', ascending: false);
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Map<String, dynamic>> createDomain({required String businessId, required String domain}) async {
    try {
      final res = await _client
          .from('business_domains')
          .insert({
            'business_id': businessId,
            'domain': domain.trim().toLowerCase(),
          })
          .select()
          .single();
      return (res as Map).cast<String, dynamic>();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> deleteDomain({required String businessId, required String domainId}) async {
    try {
      await _client.from('business_domains').delete().eq('business_id', businessId).eq('id', domainId);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}
