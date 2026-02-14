import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'customer_order_detail_page.dart';
import 'request_detail_page.dart';

/// Deep-link hub for `/requests/:id`.
///
/// DB triggers enqueue notifications with deep_link like `/requests/<uuid>`.
/// This page resolves whether the current user is:
/// - a business member => open the full business request detail UI
/// - the customer => open the customer tracking UI
class RequestHubPage extends StatefulWidget {
  final String requestId;
  const RequestHubPage({super.key, required this.requestId});

  @override
  State<RequestHubPage> createState() => _RequestHubPageState();
}

class _RequestHubPageState extends State<RequestHubPage> {
  bool _loading = true;
  String? _error;

  String? _businessId;
  bool _isBusinessMember = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sb = Supabase.instance.client;
      final user = sb.auth.currentUser;
      if (user == null) throw Exception('Session manquante.');

      final r = await sb
          .from('service_requests')
          .select('id,business_id,customer_user_id')
          .eq('id', widget.requestId)
          .single();

      final req = Map<String, dynamic>.from(r as Map);
      final businessId = req['business_id']?.toString() ?? '';
      if (businessId.isEmpty) throw Exception('Request business_id missing.');

      final member = await sb
          .from('business_members')
          .select('role')
          .eq('business_id', businessId)
          .eq('user_id', user.id)
          .maybeSingle();

      _businessId = businessId;
      _isBusinessMember = member != null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          ),
          title: const Text('Demande'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          ),
          title: const Text('Demande'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        ),
      );
    }

    final bid = _businessId!;
    if (_isBusinessMember) {
      return RequestDetailPage(businessId: bid, requestId: widget.requestId);
    }
    return CustomerOrderDetailPage(requestId: widget.requestId);
  }
}
