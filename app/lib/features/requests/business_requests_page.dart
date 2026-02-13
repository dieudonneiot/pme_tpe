import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _requests.map((r) {
                    final est = r['total_estimate'];
                    final cur = r['currency']?.toString() ?? 'XOF';
                    return Card(
                      child: ListTile(
                        title: Text('Statut: ${r['status']} • Type: ${r['type']}'),
                        subtitle: Text(r['address_text']?.toString() ?? ''),
                        trailing: Text(est == null ? '' : '$est $cur'),
                        onTap: () => context.push('/business/${widget.businessId}/requests/${r['id']}'),
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}
