import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'request_status_ui.dart';

class BusinessRequestsPage extends StatefulWidget {
  final String businessId;
  const BusinessRequestsPage({super.key, required this.businessId});

  @override
  State<BusinessRequestsPage> createState() => _BusinessRequestsPageState();
}

class _BusinessRequestsPageState extends State<BusinessRequestsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _requests = [];

  String _fmtDate(Object? raw) {
    final dt = raw == null ? null : DateTime.tryParse(raw.toString());
    if (dt == null) return '';
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

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
      final rows = await sb
          .from('service_requests')
          .select('id,status,type,created_at,address_text,total_estimate,currency,customer_user_id')
          .eq('business_id', widget.businessId)
          .order('created_at', ascending: false);

      _requests = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Demandes (B3)'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _requests.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.inbox_outlined, size: 42),
                            const SizedBox(height: 10),
                            const Text('Aucune demande pour le moment.', style: TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            Text('Les nouvelles commandes apparaîtront ici.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Actualiser'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: _requests.map((r) {
                        final est = r['total_estimate'];
                        final cur = r['currency']?.toString() ?? 'XOF';
                        final status = (r['status'] ?? 'new').toString();
                        final type = (r['type'] ?? '').toString();
                        final when = _fmtDate(r['created_at']);
                        return Card(
                          child: ListTile(
                            leading: RequestStatusChip(status: status, dense: true),
                            title: Text(type.isEmpty ? 'Demande' : type, style: const TextStyle(fontWeight: FontWeight.w900)),
                            subtitle: Text(
                              [
                                r['address_text']?.toString() ?? '',
                                if (when.isNotEmpty) when,
                              ].where((s) => s.trim().isNotEmpty).join(' • '),
                            ),
                            trailing: est == null ? null : Text('$est $cur', style: const TextStyle(fontWeight: FontWeight.w900)),
                            onTap: () => context.push('/business/${widget.businessId}/requests/${r['id']}'),
                          ),
                        );
                      }).toList(),
                    ),
    );
  }
}
