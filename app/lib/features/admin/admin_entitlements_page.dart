import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/app_back_button.dart';

class AdminEntitlementsPage extends StatefulWidget {
  const AdminEntitlementsPage({super.key});

  @override
  State<AdminEntitlementsPage> createState() => _AdminEntitlementsPageState();
}

class _AdminEntitlementsPageState extends State<AdminEntitlementsPage> {
  bool _loading = true;
  String? _error;
  String _query = '';

  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime? _parseDate(Object? v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  bool _hasPaidUntil(Map<String, dynamic> row) => row.containsKey('orders_paid_until');

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sb = Supabase.instance.client;

      // Entitlements rows + business + plan
      List<Map<String, dynamic>> list;
      try {
        final rows = await sb.from('entitlements').select(
              'business_id,plan_id,visibility_multiplier,can_receive_orders,can_run_ads,orders_grant_until,orders_paid_until,updated_at,'
              'plans:plans(code,name),'
              'businesses:businesses(name,slug,is_active)',
            );
        list = (rows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } on PostgrestException catch (e) {
        // Backward-compatible: orders_grant_until / orders_paid_until may not exist yet.
        final m = e.message.toLowerCase();
        if (m.contains('orders_grant_until') || m.contains('orders_paid_until')) {
          final rows = await sb.from('entitlements').select(
                'business_id,plan_id,visibility_multiplier,can_receive_orders,can_run_ads,updated_at,'
                'plans:plans(code,name),'
                'businesses:businesses(name,slug,is_active)',
              );
          list = (rows as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        } else {
          rethrow;
        }
      }

      list.sort((a, b) {
        final an = (a['businesses']?['name'] ?? '').toString().toLowerCase();
        final bn = (b['businesses']?['name'] ?? '').toString().toLowerCase();
        return an.compareTo(bn);
      });

      _rows = list;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _filtered() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((r) {
      final b = r['businesses'] as Map?;
      final name = (b?['name'] ?? '').toString().toLowerCase();
      final slug = (b?['slug'] ?? '').toString().toLowerCase();
      return name.contains(q) || slug.contains(q) || r['business_id'].toString().contains(q);
    }).toList();
  }

  Future<void> _setCanReceiveOrders(String businessId, bool v) async {
    try {
      final sb = Supabase.instance.client;
      await sb.from('entitlements').update({'can_receive_orders': v}).eq('business_id', businessId);
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DB: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _grantOrdersUntil(String businessId, DateTime? until) async {
    try {
      final sb = Supabase.instance.client;
      await sb
          .from('entitlements')
          .update({'orders_grant_until': until?.toUtc().toIso8601String()})
          .eq('business_id', businessId);
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DB: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _pickGrant(String businessId) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
      initialDate: now.add(const Duration(days: 30)),
      helpText: 'Grant commandes jusqu’au…',
    );
    if (d == null) return;
    // Set end-of-day local to be friendly
    final until = DateTime(d.year, d.month, d.day, 23, 59, 59);
    await _grantOrdersUntil(businessId, until);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered();

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Admin · Entitlements'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: TextField(
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Rechercher une entreprise…',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: rows.isEmpty
                          ? const Center(child: Text('Aucune entreprise.'))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              itemCount: rows.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final r = rows[i];
                                final bid = r['business_id'].toString();
                                final b = (r['businesses'] as Map?) ?? {};
                                final plan = (r['plans'] as Map?) ?? {};

                                final name = (b['name'] ?? '').toString();
                                final slug = (b['slug'] ?? '').toString();
                                final isActive = b['is_active'] == true;

                                final canOrdersFlag = r['can_receive_orders'] == true;
                                final paidUntil = _parseDate(r['orders_paid_until']);
                                final grantUntil = _parseDate(r['orders_grant_until']);
                                final now = DateTime.now();

                                final paid = paidUntil != null && paidUntil.isAfter(now);
                                final granted = grantUntil != null && grantUntil.isAfter(now);

                                // New model: plan includes orders AND active by paid_until or grant.
                                // Legacy model: can_receive_orders alone meant "active".
                                final effective = _hasPaidUntil(r)
                                    ? (canOrdersFlag && (paid || granted))
                                    : (canOrdersFlag || granted);

                                final planName = (plan['name'] ?? '').toString();
                                final planCode = (plan['code'] ?? '').toString();

                                return Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                name.isEmpty ? bid : name,
                                                style: const TextStyle(fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: (effective ? Colors.green : Colors.orange).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                effective ? 'ORDERS ON' : 'ORDERS OFF',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: effective ? Colors.green : Colors.orange,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          [
                                            if (slug.isNotEmpty) 'slug: $slug',
                                            'plan: $planName ($planCode)',
                                            'active: ${isActive ? 'yes' : 'no'}',
                                          ].join(' • '),
                                          style: const TextStyle(color: Colors.black54),
                                        ),
                                        const SizedBox(height: 10),
                                        SwitchListTile(
                                          contentPadding: EdgeInsets.zero,
                                          value: canOrdersFlag,
                                          onChanged: (v) => _setCanReceiveOrders(bid, v),
                                          title: const Text('can_receive_orders (subscription)'),
                                          subtitle: const Text('Flag “paid/subscribed” côté serveur.'),
                                        ),
                                        const SizedBox(height: 6),
                                        ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: const Text('Paid until'),
                                          subtitle: Text(
                                            paidUntil == null
                                                ? '—'
                                                : paidUntil.toLocal().toString().replaceFirst(".000", ""),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: const Text('Admin grant'),
                                          subtitle: Text(
                                            grantUntil == null
                                                ? 'Aucun grant'
                                                : 'Jusqu’au ${grantUntil.toLocal().toString().replaceFirst(".000", "")}',
                                          ),
                                          trailing: Wrap(
                                            spacing: 8,
                                            children: [
                                              TextButton(
                                                onPressed: () => _grantOrdersUntil(
                                                  bid,
                                                  DateTime.now().add(const Duration(days: 30)),
                                                ),
                                                child: const Text('+30j'),
                                              ),
                                              TextButton(
                                                onPressed: () => _pickGrant(bid),
                                                child: const Text('Choisir…'),
                                              ),
                                              TextButton(
                                                onPressed: () => _grantOrdersUntil(bid, null),
                                                child: const Text('Retirer'),
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
                  ],
                ),
    );
  }
}
