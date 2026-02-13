import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BusinessLinksPage extends StatefulWidget {
  final String businessId;
  const BusinessLinksPage({super.key, required this.businessId});

  @override
  State<BusinessLinksPage> createState() => _BusinessLinksPageState();
}

class _BusinessLinksPageState extends State<BusinessLinksPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _platforms = <String>[
    'website',
    'whatsapp',
    'facebook',
    'instagram',
    'tiktok',
    'x',
    'youtube',
  ];

  final Map<String, TextEditingController> _ctrl = {
    for (final p in _platforms) p: TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
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
          .from('business_social_links')
          .select('platform,url')
          .eq('business_id', widget.businessId);

      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        final p = (m['platform'] ?? '').toString();
        final u = (m['url'] ?? '').toString();
        if (_ctrl.containsKey(p)) _ctrl[p]!.text = u;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final sb = Supabase.instance.client;

      // Upsert non-empty
      final upserts = <Map<String, dynamic>>[];
      for (final p in _platforms) {
        final url = _ctrl[p]!.text.trim();
        if (url.isEmpty) continue;

        upserts.add({
          'business_id': widget.businessId,
          'platform': p,
          'url': url,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      if (upserts.isNotEmpty) {
        await sb.from('business_social_links').upsert(
              upserts,
              onConflict: 'business_id,platform',
            );
      }

      // Delete empty
      for (final p in _platforms) {
        final url = _ctrl[p]!.text.trim();
        if (url.isNotEmpty) continue;

        await sb
            .from('business_social_links')
            .delete()
            .eq('business_id', widget.businessId)
            .eq('platform', p);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Liens enregistrés.')),
      );
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

  String _label(String p) {
    switch (p) {
      case 'website':
        return 'Site web';
      case 'whatsapp':
        return 'WhatsApp';
      case 'facebook':
        return 'Facebook';
      case 'instagram':
        return 'Instagram';
      case 'tiktok':
        return 'TikTok';
      case 'x':
        return 'X';
      case 'youtube':
        return 'YouTube';
      default:
        return p;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liens & réseaux'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '...' : 'Enregistrer'),
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
                ..._platforms.map((p) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: _ctrl[p],
                      decoration: InputDecoration(
                        labelText: _label(p),
                        hintText: 'https://...',
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
