import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'request_status_ui.dart';

class CustomerOrderDetailPage extends StatefulWidget {
  final String requestId;
  const CustomerOrderDetailPage({super.key, required this.requestId});

  @override
  State<CustomerOrderDetailPage> createState() => _CustomerOrderDetailPageState();
}

class _CustomerOrderDetailPageState extends State<CustomerOrderDetailPage> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _request;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _paymentIntents = [];

  final _msgCtrl = TextEditingController();
  bool _sending = false;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sb = Supabase.instance.client;

      final r = await sb
          .from('service_requests')
          .select(
            'id,business_id,status,type,address_text,notes,total_estimate,currency,created_at,updated_at,'
            'businesses(name,slug)',
          )
          .eq('id', widget.requestId)
          .single();
      _request = Map<String, dynamic>.from(r as Map);

      // items (variant_id optional)
      try {
        final items = await sb
            .from('service_request_items')
            .select('id,product_id,variant_id,title_snapshot,qty,unit_price_snapshot,created_at')
            .eq('request_id', widget.requestId)
            .order('created_at', ascending: true);
        _items = (items as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } on PostgrestException catch (e) {
        if (e.message.toLowerCase().contains('variant_id')) {
          final items = await sb
              .from('service_request_items')
              .select('id,product_id,title_snapshot,qty,unit_price_snapshot,created_at')
              .eq('request_id', widget.requestId)
              .order('created_at', ascending: true);
          _items = (items as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } else {
          rethrow;
        }
      }

      final hist = await sb
          .from('service_request_status_history')
          .select('id,from_status,to_status,actor_user_id,note,created_at')
          .eq('request_id', widget.requestId)
          .order('created_at', ascending: false);
      _history = (hist as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final msgs = await sb
          .from('service_request_messages')
          .select('id,sender_user_id,message,created_at')
          .eq('request_id', widget.requestId)
          .order('created_at', ascending: true);
      _messages = (msgs as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      try {
        final pi = await sb
            .from('payment_intents')
            .select('id,status,provider,amount,currency,external_ref,created_at,updated_at')
            .eq('request_id', widget.requestId)
            .order('created_at', ascending: false)
            .limit(10);
        _paymentIntents = (pi as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {
        _paymentIntents = [];
      }
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

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      final sb = Supabase.instance.client;
      final user = sb.auth.currentUser;
      if (user == null) throw Exception('Session manquante.');

      await sb.from('service_request_messages').insert({
        'request_id': widget.requestId,
        'sender_user_id': user.id,
        'message': text,
      });

      _msgCtrl.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _cancelIfAllowed() async {
    final status = _request?['status']?.toString() ?? '';
    if (status != 'new' || _cancelling) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Annuler la commande ?'),
        content: const Text("Vous pouvez annuler uniquement tant qu'elle n'est pas acceptée."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Retour')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Annuler')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _cancelling = true);
    try {
      final sb = Supabase.instance.client;
      await sb.rpc('customer_cancel_request', params: {'p_request_id': widget.requestId});
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DB: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go('/my/orders'),
          ),
          title: const Text('Commande'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        ),
      );
    }

    final r = _request!;
    final status = r['status']?.toString() ?? '';
    final biz = (r['businesses'] as Map?) ?? {};
    final bizName = (biz['name'] ?? '').toString();
    final total = r['total_estimate'];
    final cur = (r['currency'] ?? 'XOF').toString();
    final createdAt = DateTime.tryParse((r['created_at'] ?? '').toString()) ?? DateTime.now();
    final latestPi = _paymentIntents.isEmpty ? null : _paymentIntents.first;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/my/orders'),
        ),
        title: Text(bizName.isEmpty ? 'Commande' : bizName),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RequestProgressBar(status: status),
                  const SizedBox(height: 10),
                  Text('Créée: ${_fmtDate(r['created_at'])}'),
                  if (total != null) ...[
                    const SizedBox(height: 6),
                    Text('Total estimé: $total $cur', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/requests/${widget.requestId}/payment'),
                          icon: const Icon(Icons.payments_outlined),
                          label: Text(
                            latestPi == null ? 'Paiement' : 'Paiement: ${latestPi['status'] ?? ''}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (status == 'new' && !_cancelling) ? _cancelIfAllowed : null,
                          icon: _cancelling
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.cancel),
                          label: const Text('Annuler'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Timeline', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: RequestTimeline(createdAt: createdAt, history: _history),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Articles', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            const Text('Aucun article.')
          else
            ..._items.map((it) {
              final title = (it['title_snapshot'] ?? '').toString();
              final qty = (it['qty'] as num?)?.toInt() ?? 0;
              final up = it['unit_price_snapshot'];
              return Card(
                child: ListTile(
                  title: Text(title.isEmpty ? it['product_id'].toString() : title),
                  subtitle: Text('x$qty'),
                  trailing: up == null ? null : Text('$up $cur'),
                ),
              );
            }),
          const SizedBox(height: 12),
          const Text('Messages', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (_messages.isEmpty)
            const Text('Aucun message.')
          else
            ..._messages.map((m) {
              final msg = (m['message'] ?? '').toString();
              final when = _fmtDate(m['created_at']);
              final me = Supabase.instance.client.auth.currentUser?.id == (m['sender_user_id']?.toString() ?? '');
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${me ? 'Vous' : 'Boutique'} • $when',
                        style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(msg),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msgCtrl,
                  decoration: const InputDecoration(hintText: 'Écrire un message...'),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _sending ? null : _sendMessage,
                child: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Envoyer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
