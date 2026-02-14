import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class BusinessBillingPage extends StatefulWidget {
  final String businessId;
  const BusinessBillingPage({super.key, required this.businessId});

  @override
  State<BusinessBillingPage> createState() => _BusinessBillingPageState();
}

class _BusinessBillingPageState extends State<BusinessBillingPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  bool _subscribing = false;
  String? _error;

  Map<String, dynamic>? _entitlements;
  List<Map<String, dynamic>> _plans = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      dynamic ent;
      try {
        ent = await _sb
            .from('entitlements')
            .select(
              'can_receive_orders, can_run_ads, visibility_multiplier, orders_grant_until, orders_paid_until, plans:plans(code,name)',
            )
            .eq('business_id', widget.businessId)
            .single();
      } on PostgrestException catch (e) {
        final m = e.message.toLowerCase();
        if (m.contains('orders_grant_until') || m.contains('orders_paid_until')) {
          ent = await _sb
              .from('entitlements')
              .select(
                'can_receive_orders, can_run_ads, visibility_multiplier, plans:plans(code,name)',
              )
              .eq('business_id', widget.businessId)
              .single();
        } else {
          rethrow;
        }
      }

      _entitlements = Map<String, dynamic>.from(ent as Map);

      final rows = await _sb
          .from('plans')
          .select('id,code,name,description,monthly_price_amount,currency,created_at')
          .order('monthly_price_amount', ascending: true);
      _plans = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtMoney(Object? amount, String currency) {
    if (amount == null) return '—';
    final n = (amount is num) ? amount : num.tryParse(amount.toString());
    if (n == null) return '—';
    final s = n.toStringAsFixed(n == n.roundToDouble() ? 0 : 2);
    return '$s $currency';
  }

  Future<void> _subscribe(String planCode, {required String provider}) async {
    if (_subscribing) return;
    setState(() => _subscribing = true);

    try {
      final res = await _sb.functions.invoke(
        'billing_subscribe',
        body: {
          'business_id': widget.businessId,
          'plan_code': planCode,
          'provider': provider,
        },
      );

      final data = res.data;
      final url = (data is Map) ? (data['payment_url'] as String?) : null;
      if (url == null || url.trim().isEmpty) {
        throw Exception('No payment_url returned.');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Redirecting to payment...')),
      );

      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) throw Exception("Can't open payment URL.");

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("After payment, come back and hit Refresh.")),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DB: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _subscribing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ent = _entitlements;
    final planCode = ent?['plans']?['code']?.toString() ?? 'free';
    final planName = ent?['plans']?['name']?.toString() ?? 'Free';

    final now = DateTime.now();
    final hasPaidUntil = ent?.containsKey('orders_paid_until') == true;
    final paidUntil = DateTime.tryParse((ent?['orders_paid_until'] ?? '').toString());
    final grantUntil = DateTime.tryParse((ent?['orders_grant_until'] ?? '').toString());

    final paid = paidUntil != null && paidUntil.isAfter(now);
    final granted = grantUntil != null && grantUntil.isAfter(now);

    final canOrdersFlag = ent?['can_receive_orders'] == true;
    final canOrders = hasPaidUntil ? (canOrdersFlag && (paid || granted)) : (canOrdersFlag || granted);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monetisation'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: ListView(
                    children: [
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.workspace_premium),
                          title: Text('Current plan: $planName'),
                          subtitle: Text('Code: $planCode'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: ListTile(
                          leading: Icon(canOrders ? Icons.check_circle : Icons.lock),
                          title: const Text('Receive orders'),
                          subtitle: Text(
                            canOrders
                                ? (paid ? 'Active (paid)' : 'Active (admin grant)')
                                : 'Inactive (subscription required)',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.schedule),
                          title: const Text('Validity'),
                          subtitle: Text([
                            if (hasPaidUntil) 'paid_until: ${paidUntil?.toLocal().toString().replaceFirst(".000", "") ?? "—"}',
                            'grant_until: ${grantUntil?.toLocal().toString().replaceFirst(".000", "") ?? "—"}',
                          ].join('  •  ')),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Choose a plan', style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      ..._plans.map((p) {
                        final code = (p['code'] ?? '').toString();
                        final name = (p['name'] ?? '').toString();
                        final desc = (p['description'] ?? '').toString();
                        final currency = (p['currency'] ?? 'XOF').toString();
                        final price = _fmtMoney(p['monthly_price_amount'], currency);
                        final isCurrent = code == planCode;

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
                                        name.isEmpty ? code : name,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                      ),
                                    ),
                                    if (isCurrent)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: const Text('CURRENT', style: TextStyle(fontWeight: FontWeight.w800)),
                                      ),
                                  ],
                                ),
                                if (desc.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(desc, style: const TextStyle(color: Colors.black54)),
                                ],
                                const SizedBox(height: 10),
                                Text('$price / month', style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: (code == 'free' || _subscribing)
                                            ? null
                                            : () => _subscribe(code, provider: 'paydunya'),
                                        icon: const Icon(Icons.phone_iphone),
                                        label: const Text('Mobile Money'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: (code == 'free' || _subscribing)
                                            ? null
                                            : () => _subscribe(code, provider: 'stripe'),
                                        icon: const Icon(Icons.credit_card),
                                        label: const Text('Card (Stripe)'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}

