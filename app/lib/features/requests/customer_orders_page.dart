import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'request_status_ui.dart';

class CustomerOrdersPage extends StatefulWidget {
  const CustomerOrdersPage({super.key});

  @override
  State<CustomerOrdersPage> createState() => _CustomerOrdersPageState();
}

class _CustomerOrdersPageState extends State<CustomerOrdersPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sb = Supabase.instance.client;
      final user = sb.auth.currentUser;
      if (user == null) throw Exception('Session manquante.');

      final rows = await sb
          .from('service_requests')
          .select('id,status,type,created_at,total_estimate,currency,businesses(name,slug)')
          .eq('customer_user_id', user.id)
          .order('created_at', ascending: false)
          .limit(200);

      _rows = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDate(Object? v) {
    final dt = DateTime.tryParse((v ?? '').toString());
    if (dt == null) return (v ?? '').toString();
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('Mes commandes'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
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
              : (_rows.isEmpty)
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Aucune commande pour le moment.'),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: () => context.go('/explore'),
                              icon: const Icon(Icons.explore),
                              label: const Text('Explorer les entreprises'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final r = _rows[i];
                          final id = r['id']?.toString() ?? '';
                          final status = r['status']?.toString() ?? '';
                          final biz = (r['businesses'] as Map?) ?? {};
                          final bizName = (biz['name'] ?? '').toString();
                          final total = r['total_estimate'];
                          final cur = (r['currency'] ?? 'XOF').toString();

                          return Card(
                            child: ListTile(
                              title: Text(bizName.isEmpty ? 'Commande' : bizName),
                              subtitle: Text(_fmtDate(r['created_at'])),
                              leading: RequestStatusChip(status: status, dense: true),
                              trailing: Text(total == null ? '' : '$total $cur'),
                              onTap: id.isEmpty ? null : () => context.push('/requests/$id'),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
