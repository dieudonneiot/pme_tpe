import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/app_back_button.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
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
          .from('notifications')
          .select('id,title,body,deep_link,read_at,created_at')
          .eq('user_id', user.id)
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

  Future<void> _markRead(String id) async {
    try {
      final sb = Supabase.instance.client;
      await sb
          .from('notifications')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('id', id);
    } catch (_) {
      // ignore: UX best-effort
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Notifications'),
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
                  ? const Center(child: Text('Aucune notification.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final n = _rows[i];
                          final id = n['id']?.toString() ?? '';
                          final title = (n['title'] ?? '').toString();
                          final body = (n['body'] ?? '').toString();
                          final link = (n['deep_link'] ?? '').toString();
                          final readAt = (n['read_at'] ?? '').toString();
                          final unread = readAt.isEmpty;

                          return Card(
                            child: ListTile(
                              leading: Icon(unread ? Icons.notifications_active : Icons.notifications_none),
                              title: Text(title),
                              subtitle: Text('${_fmtDate(n['created_at'])}\n$body'),
                              isThreeLine: true,
                              onTap: () async {
                                if (id.isEmpty) return;
                                // Fire-and-forget: avoid using BuildContext across async gaps.
                                _markRead(id);

                                if (link.isNotEmpty) {
                                  context.push(link.startsWith('/') ? link : '/$link');
                                }

                                await _load();
                              },
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
