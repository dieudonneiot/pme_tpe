import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BusinessDomainsPage extends StatefulWidget {
  final String businessId;
  const BusinessDomainsPage({super.key, required this.businessId});

  @override
  State<BusinessDomainsPage> createState() => _BusinessDomainsPageState();
}

class _BusinessDomainsPageState extends State<BusinessDomainsPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _domainCtrl = TextEditingController();
  List<Map<String, dynamic>> _domains = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _domainCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sb = Supabase.instance.client;
      final rows = await sb
          .from('business_domains')
          .select('id,domain,status,ssl_status,verification_token,created_at,updated_at')
          .eq('business_id', widget.businessId)
          .order('created_at', ascending: false);

      _domains = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _addDomain() async {
    final d = _domainCtrl.text.trim().toLowerCase();
    if (d.isEmpty) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final sb = Supabase.instance.client;
      await sb.from('business_domains').insert({
        'business_id': widget.businessId,
        'domain': d,
        'updated_at': DateTime.now().toIso8601String(),
      });

      _domainCtrl.clear();
      await _load();
    } on PostgrestException catch (e) {
      _error = 'DB error: ${e.message}';
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteDomain(String id) async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final sb = Supabase.instance.client;
      await sb.from('business_domains').delete().eq('id', id);
      await _load();
    } on PostgrestException catch (e) {
      _error = 'DB error: ${e.message}';
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Domaines'),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 10),
                ],

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Ajouter un domaine', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _domainCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Domaine',
                            hintText: 'ex: boutique.monsite.com',
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _addDomain,
                            child: Text(_saving ? '...' : 'Ajouter'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                const Text('Domaines existants', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),

                if (_domains.isEmpty)
                  const Text('Aucun domaine.')
                else
                  ..._domains.map((d) {
                    return Card(
                      child: ListTile(
                        title: Text(d['domain']?.toString() ?? ''),
                        subtitle: Text(
                          'status=${d['status']} • ssl=${d['ssl_status']}\n'
                          'token=${d['verification_token']}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: 'Supprimer',
                          onPressed: _saving ? null : () => _deleteDomain(d['id'].toString()),
                          icon: const Icon(Icons.delete),
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
