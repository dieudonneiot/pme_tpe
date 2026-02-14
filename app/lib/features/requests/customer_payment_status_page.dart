import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'request_status_ui.dart';

class CustomerPaymentStatusPage extends StatefulWidget {
  final String requestId;
  const CustomerPaymentStatusPage({super.key, required this.requestId});

  @override
  State<CustomerPaymentStatusPage> createState() => _CustomerPaymentStatusPageState();
}

class _CustomerPaymentStatusPageState extends State<CustomerPaymentStatusPage> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _request;
  List<Map<String, dynamic>> _intents = [];

  bool _creating = false;

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
      final r = await sb
          .from('service_requests')
          .select('id,status,total_estimate,currency,created_at,businesses(name)')
          .eq('id', widget.requestId)
          .single();
      _request = Map<String, dynamic>.from(r as Map);

      final pi = await sb
          .from('payment_intents')
          .select('id,status,provider,amount,currency,external_ref,created_at,updated_at')
          .eq('request_id', widget.requestId)
          .order('created_at', ascending: false)
          .limit(20);
      _intents = (pi as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on PostgrestException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? get _latest => _intents.isEmpty ? null : _intents.first;

  (String label, Color bg, Color fg, IconData icon) _piStyle(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'paid':
        return ('Payé', Colors.green.withValues(alpha: 0.12), Colors.green, Icons.verified);
      case 'initiated':
        return ('Lien généré', scheme.secondaryContainer, scheme.onSecondaryContainer, Icons.link);
      case 'pending':
        return ('En attente', scheme.surfaceContainerHighest, scheme.onSurface, Icons.hourglass_empty);
      case 'failed':
        return ('Échec', Colors.red.withValues(alpha: 0.12), Colors.red, Icons.error_outline);
      case 'cancelled':
        return ('Annulé', Colors.red.withValues(alpha: 0.12), Colors.red, Icons.cancel_outlined);
      default:
        return (status, scheme.surfaceContainerHighest, scheme.onSurface, Icons.info_outline);
    }
  }

  Widget _piChip(BuildContext context, String status) {
    final s = _piStyle(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: s.$2, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.$4, size: 18, color: s.$3),
          const SizedBox(width: 6),
          Text(s.$1, style: TextStyle(fontWeight: FontWeight.w900, color: s.$3)),
        ],
      ),
    );
  }

  String _fmtDate(Object? v) {
    final dt = DateTime.tryParse((v ?? '').toString());
    if (dt == null) return (v ?? '').toString();
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  Future<void> _openUrl(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir le lien.")));
    }
  }

  Future<void> _retryPaydunya() async {
    if (_creating) return;
    setState(() => _creating = true);

    try {
      final sb = Supabase.instance.client;
      final res = await sb.functions.invoke(
        'create_payment_intent',
        body: {'request_id': widget.requestId, 'provider': 'PAYDUNYA'},
      );

      final raw = res.data;
      final data = raw is String ? jsonDecode(raw) : raw;
      final url = (data is Map) ? data['payment_url']?.toString() : null;
      if (url == null || url.trim().isEmpty) {
        throw Exception('payment_url manquant.');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Redirection vers paiement...')));
      await _openUrl(url);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DB: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      if (mounted) setState(() => _creating = false);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final latest = _latest;
    final latestStatus = (latest?['status'] ?? '').toString();
    final latestProvider = (latest?['provider'] ?? '').toString();
    final latestUrl = (latest?['external_ref'] ?? '').toString();
    final canOpen = latestUrl.startsWith('http');
    final isPaid = latestStatus == 'paid';
    final isFailed = latestStatus == 'failed' || latestStatus == 'cancelled';
    final isInProgress = latestStatus == 'initiated' || latestStatus == 'pending';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/requests/${widget.requestId}'),
        ),
        title: const Text('Paiement'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_request != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RequestProgressBar(status: _request?['status']?.toString() ?? 'new'),
                          const SizedBox(height: 10),
                          Text(
                            'Total: ${_request?['total_estimate'] ?? '-'} ${_request?['currency'] ?? 'XOF'}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          Text('Créée: ${_fmtDate(_request?['created_at'])}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Statut paiement', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        if (latest == null) ...[
                          const Text('Aucun paiement initié.'),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _creating ? null : _retryPaydunya,
                            icon: _creating
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.payments_outlined),
                            label: const Text('Payer (PayDunya)'),
                          ),
                        ] else ...[
                          Row(
                            children: [
                              _piChip(context, latestStatus),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  latestProvider.isEmpty ? '—' : latestProvider,
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text('Dernière mise à jour: ${_fmtDate(latest['updated_at'] ?? latest['created_at'])}'),
                          if (isPaid) ...[
                            const SizedBox(height: 10),
                            const Text('Paiement confirmé.', style: TextStyle(fontWeight: FontWeight.w900)),
                          ] else if (isInProgress) ...[
                            const SizedBox(height: 10),
                            const Text("Paiement en cours. Si tu n'as pas terminé, ouvre le lien ci-dessous."),
                          ] else if (isFailed) ...[
                            const SizedBox(height: 10),
                            const Text("Le paiement a échoué ou a été annulé. Tu peux réessayer.", style: TextStyle(fontWeight: FontWeight.w700)),
                          ],
                          if (canOpen) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () => _openUrl(latestUrl),
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Ouvrir le lien de paiement'),
                            ),
                          ],
                          if (!isPaid) ...[
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: _creating ? null : _retryPaydunya,
                              icon: _creating
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.refresh),
                              label: const Text('Réessayer (PayDunya)'),
                            ),
                          ],
                        ],
                        const SizedBox(height: 10),
                        const Text(
                          "Après paiement, reviens ici et clique sur Rafraîchir.",
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                const Text('Historique des paiements', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (_intents.isEmpty)
                  const Text('—')
                else
                  ..._intents.map((p) {
                    final status = (p['status'] ?? '').toString();
                    final provider = (p['provider'] ?? '').toString();
                    final amount = p['amount'];
                    final cur = (p['currency'] ?? 'XOF').toString();
                    final url = (p['external_ref'] ?? '').toString();

                    return Card(
                      child: ListTile(
                        title: Row(
                          children: [
                            _piChip(context, status),
                            const SizedBox(width: 10),
                            Expanded(child: Text(provider.isEmpty ? '—' : provider, style: const TextStyle(fontWeight: FontWeight.w900))),
                          ],
                        ),
                        subtitle: Text('${_fmtDate(p['created_at'])} • $amount $cur'),
                        trailing: url.startsWith('http') ? const Icon(Icons.open_in_new) : null,
                        onTap: url.startsWith('http') ? () => _openUrl(url) : null,
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
