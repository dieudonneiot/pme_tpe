import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RequestDetailPage extends StatefulWidget {
  final String businessId;
  final String requestId;

  const RequestDetailPage({
    super.key,
    required this.businessId,
    required this.requestId,
  });

  @override
  State<RequestDetailPage> createState() => _RequestDetailPageState();
}

class _RequestDetailPageState extends State<RequestDetailPage> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _request;
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _quotes = [];
  List<Map<String, dynamic>> _invoices = [];
  List<Map<String, dynamic>> _paymentIntents = [];

  final _msgCtrl = TextEditingController();

  static const _statuses = <String>[
    'new',
    'accepted',
    'rejected',
    'in_progress',
    'delivered',
    'closed',
    'cancelled',
  ];

  static const _providers = <String>[
    'google_play',
    'cinetpay',
    'fedapay',
    'manual',
  ];

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
          .select('id,business_id,customer_user_id,status,type,address_text,notes,total_estimate,currency,created_at,updated_at')
          .eq('id', widget.requestId)
          .single();

      _request = Map<String, dynamic>.from(r as Map);

      final msgs = await sb
          .from('service_request_messages')
          .select('id,sender_user_id,message,created_at')
          .eq('request_id', widget.requestId)
          .order('created_at', ascending: true);

      _messages = (msgs as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final hist = await sb
          .from('service_request_status_history')
          .select('id,from_status,to_status,actor_user_id,note,created_at')
          .eq('request_id', widget.requestId)
          .order('created_at', ascending: false);

      _history = (hist as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final asg = await sb
          .from('service_request_assignments')
          .select('id,staff_user_id,assigned_by_user_id,role,assigned_at,unassigned_at')
          .eq('request_id', widget.requestId)
          .order('assigned_at', ascending: false);

      _assignments = (asg as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final q = await sb
          .from('quotes')
          .select('id,status,total,currency,created_at,updated_at')
          .eq('request_id', widget.requestId)
          .order('created_at', ascending: false);

      _quotes = (q as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final inv = await sb
          .from('invoices')
          .select('id,status,total,currency,issued_at,paid_at,created_at,updated_at')
          .eq('request_id', widget.requestId)
          .order('created_at', ascending: false);

      _invoices = (inv as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final pi = await sb
          .from('payment_intents')
          .select('id,status,provider,amount,currency,external_ref,created_at,updated_at,invoice_id,request_id')
          .eq('request_id', widget.requestId)
          .order('created_at', ascending: false);

      _paymentIntents = (pi as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

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
    }
  }

  Future<void> _changeStatus(String next) async {
    final current = _request?['status']?.toString();
    if (current == null || current == next) return;

    try {
      final sb = Supabase.instance.client;
      final user = sb.auth.currentUser;
      if (user == null) throw Exception('Session manquante.');

      await sb.from('service_requests').update({'status': next}).eq('id', widget.requestId);

      await sb.from('service_request_status_history').insert({
        'request_id': widget.requestId,
        'from_status': current,
        'to_status': next,
        'actor_user_id': user.id,
        'note': null,
      });

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _assignStaff() async {
    try {
      final sb = Supabase.instance.client;
      final user = sb.auth.currentUser;
      if (user == null) throw Exception('Session manquante.');

      final members = await sb
          .from('business_members')
          .select('user_id,role,created_at')
          .eq('business_id', widget.businessId)
          .order('created_at');

      final list = (members as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (list.isEmpty) return;

      if (!mounted) return;
      String selected = list.first['user_id'].toString();

      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Affecter un staff'),
          content: DropdownButton<String>(
            isExpanded: true,
            value: selected,
            items: list.map((m) {
              final uid = m['user_id'].toString();
              final role = m['role']?.toString() ?? 'staff';
              return DropdownMenuItem(
                value: uid,
                child: Text('$uid • $role', overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (v) {
              if (v == null) return;
              selected = v;
              (context as Element).markNeedsBuild();
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Affecter')),
          ],
        ),
      );

      if (ok != true) return;

      await sb.from('service_request_assignments').insert({
        'request_id': widget.requestId,
        'staff_user_id': selected,
        'assigned_by_user_id': user.id,
        'role': 'primary',
      });

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _unassign(String assignmentId) async {
    try {
      final sb = Supabase.instance.client;
      await sb.from('service_request_assignments').update({
        'unassigned_at': DateTime.now().toIso8601String(),
      }).eq('id', assignmentId);

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _createQuote() async {
    try {
      final sb = Supabase.instance.client;
      final user = sb.auth.currentUser;
      if (user == null) throw Exception('Session manquante.');
      final r = _request;
      if (r == null) return;

      await sb.from('quotes').insert({
        'request_id': widget.requestId,
        'business_id': widget.businessId,
        'customer_user_id': r['customer_user_id'],
        'status': 'draft',
        'currency': r['currency'] ?? 'XOF',
        'subtotal': 0,
        'tax': 0,
        'total': 0,
        'created_by': user.id,
      });

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _createInvoice() async {
    try {
      final sb = Supabase.instance.client;
      final user = sb.auth.currentUser;
      if (user == null) throw Exception('Session manquante.');
      final r = _request;
      if (r == null) return;

      await sb.from('invoices').insert({
        'request_id': widget.requestId,
        'business_id': widget.businessId,
        'customer_user_id': r['customer_user_id'],
        'status': 'draft',
        'currency': r['currency'] ?? 'XOF',
        'subtotal': 0,
        'tax': 0,
        'total': 0,
        'created_by': user.id,
      });

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _createPaymentIntent() async {
    if (_invoices.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Crée une facture d’abord.')));
      return;
    }

    try {
      final sb = Supabase.instance.client;
      final user = sb.auth.currentUser;
      if (user == null) throw Exception('Session manquante.');

      final invoice = _invoices.first;
      final invoiceId = invoice['id'].toString();
      final amount = (invoice['total'] as num?)?.toDouble() ?? 0.0;
      final currency = invoice['currency']?.toString() ?? 'XOF';

      String provider = _providers.first;

      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Créer un payment_intent'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                isExpanded: true,
                value: provider,
                items: _providers
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  provider = v;
                  (context as Element).markNeedsBuild();
                },
              ),
              const SizedBox(height: 8),
              Text('Facture: $invoiceId'),
              Text('Montant: $amount $currency'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Créer')),
          ],
        ),
      );

      if (ok != true) return;

      await sb.from('payment_intents').insert({
        'business_id': widget.businessId,
        'request_id': widget.requestId,
        'invoice_id': invoiceId,
        'provider': provider,
        'amount': amount,
        'currency': currency,
        'status': 'pending',
        'created_by': user.id,
      });

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _request;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail demande'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : r == null
                  ? const Center(child: Text('Demande introuvable'))
                  : DefaultTabController(
                      length: 5,
                      child: Column(
                        children: [
                          Card(
                            margin: const EdgeInsets.all(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Statut: ${r['status']} • Type: ${r['type']}',
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 6),
                                  Text(r['address_text']?.toString() ?? ''),
                                  const SizedBox(height: 6),
                                  Text('Notes: ${r['notes'] ?? ''}'),
                                ],
                              ),
                            ),
                          ),
                          const TabBar(
                            tabs: [
                              Tab(text: 'Chat'),
                              Tab(text: 'Statut'),
                              Tab(text: 'Staff'),
                              Tab(text: 'Devis/Factures'),
                              Tab(text: 'Paiement'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                // Chat
                                Column(
                                  children: [
                                    Expanded(
                                      child: ListView(
                                        padding: const EdgeInsets.all(12),
                                        children: _messages.map((m) {
                                          return Card(
                                            child: ListTile(
                                              title: Text(m['message']?.toString() ?? ''),
                                              subtitle: Text('from: ${m['sender_user_id']}'),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _msgCtrl,
                                              decoration: const InputDecoration(
                                                labelText: 'Message',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            onPressed: _sendMessage,
                                            child: const Text('Envoyer'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                // Statut
                                ListView(
                                  padding: const EdgeInsets.all(12),
                                  children: [
                                    DropdownButtonFormField<String>(
                                      initialValue: r['status']?.toString(),
                                      items: _statuses
                                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                          .toList(),
                                      onChanged: (v) {
                                        if (v == null) return;
                                        _changeStatus(v);
                                      },
                                      decoration: const InputDecoration(labelText: 'Changer statut'),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text('Historique', style: TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 8),
                                    ..._history.map((h) => Card(
                                          child: ListTile(
                                            title: Text('${h['from_status'] ?? '-'} -> ${h['to_status']}'),
                                            subtitle: Text('by ${h['actor_user_id']}'),
                                          ),
                                        )),
                                  ],
                                ),

                                // Staff
                                ListView(
                                  padding: const EdgeInsets.all(12),
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: _assignStaff,
                                      icon: const Icon(Icons.person_add),
                                      label: const Text('Affecter un staff'),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text('Affectations', style: TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 8),
                                    if (_assignments.isEmpty)
                                      const Text('Aucune affectation.')
                                    else
                                      ..._assignments.map((a) {
                                        final unassigned = a['unassigned_at'] != null;
                                        return Card(
                                          child: ListTile(
                                            title: Text('staff: ${a['staff_user_id']} • role: ${a['role']}'),
                                            subtitle: Text(unassigned ? 'Unassigned' : 'Active'),
                                            trailing: unassigned
                                                ? null
                                                : IconButton(
                                                    tooltip: 'Unassign',
                                                    onPressed: () => _unassign(a['id'].toString()),
                                                    icon: const Icon(Icons.remove_circle),
                                                  ),
                                          ),
                                        );
                                      }),
                                  ],
                                ),

                                // Quotes / Invoices
                                ListView(
                                  padding: const EdgeInsets.all(12),
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: _createQuote,
                                            child: const Text('Créer devis'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: _createInvoice,
                                            child: const Text('Créer facture'),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    const Text('Devis', style: TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 8),
                                    if (_quotes.isEmpty)
                                      const Text('Aucun devis.')
                                    else
                                      ..._quotes.map((q) => Card(
                                            child: ListTile(
                                              title: Text('status=${q['status']} • total=${q['total']} ${q['currency']}'),
                                              subtitle: Text('id=${q['id']}'),
                                            ),
                                          )),
                                    const SizedBox(height: 12),
                                    const Text('Factures', style: TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 8),
                                    if (_invoices.isEmpty)
                                      const Text('Aucune facture.')
                                    else
                                      ..._invoices.map((i) => Card(
                                            child: ListTile(
                                              title: Text('status=${i['status']} • total=${i['total']} ${i['currency']}'),
                                              subtitle: Text('id=${i['id']}'),
                                            ),
                                          )),
                                  ],
                                ),

                                // Paiement
                                ListView(
                                  padding: const EdgeInsets.all(12),
                                  children: [
                                    ElevatedButton(
                                      onPressed: _createPaymentIntent,
                                      child: const Text('Créer payment_intent (sur dernière facture)'),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text('Payment intents', style: TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 8),
                                    if (_paymentIntents.isEmpty)
                                      const Text('Aucun payment_intent.')
                                    else
                                      ..._paymentIntents.map((p) => Card(
                                            child: ListTile(
                                              title: Text('status=${p['status']} • provider=${p['provider']}'),
                                              subtitle: Text('amount=${p['amount']} ${p['currency']} • id=${p['id']}'),
                                            ),
                                          )),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }
}
