import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class PlansPage extends StatefulWidget {
  const PlansPage({super.key});
  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> {
  final sb = Supabase.instance.client;
  List<Map<String, dynamic>> _plans = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    final rows = await sb.from('plans').select().order('monthly_price_amount', ascending: true);
    setState(() {
      _plans = List<Map<String, dynamic>>.from(rows);
      _loading = false;
    });
  }

  Future<void> _subscribe(String code) async {
    final res = await sb.functions.invoke('billing/subscribe', body: {
      'business_id': sb.auth.currentUser!.id,
      'plan_code': code,
    });
    final url = res.data?['payment_url'];
    if (url != null) await launchUrl(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Choisir un plan')),
      body: ListView.builder(
        itemCount: _plans.length,
        itemBuilder: (ctx, i) {
          final p = _plans[i];
          return Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['name'], style: Theme.of(context).textTheme.titleLarge),
                  Text(p['description'] ?? ''),
                  const SizedBox(height: 10),
                  Text('${p['monthly_price_amount'] ?? 0} XOF / mois'),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () => _subscribe(p['code']),
                    child: const Text('Souscrire'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
