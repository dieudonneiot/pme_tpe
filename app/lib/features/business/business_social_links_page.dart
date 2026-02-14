import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/app_back_button.dart';

class BusinessSocialLinksPage extends StatefulWidget {
  final String businessId;
  const BusinessSocialLinksPage({super.key, required this.businessId});

  @override
  State<BusinessSocialLinksPage> createState() => _BusinessSocialLinksPageState();
}

class _BusinessSocialLinksPageState extends State<BusinessSocialLinksPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  final _controllers = <String, TextEditingController>{
    'website': TextEditingController(),
    'whatsapp': TextEditingController(),
    'facebook': TextEditingController(),
    'instagram': TextEditingController(),
    'tiktok': TextEditingController(),
    'x': TextEditingController(),
    'youtube': TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
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
      final rows = await _sb
          .from('business_social_links')
          .select('platform,url')
          .eq('business_id', widget.businessId);

      for (final r in rows) {
        final platform = r['platform'] as String;
        final url = r['url'] as String? ?? '';
        if (_controllers.containsKey(platform)) {
          _controllers[platform]!.text = url;
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final payload = <Map<String, dynamic>>[];

      _controllers.forEach((platform, controller) {
        final url = controller.text.trim();
        if (url.isEmpty) return;
        payload.add({
          'business_id': widget.businessId,
          'platform': platform,
          'url': url,
          'updated_at': DateTime.now().toIso8601String(),
        });
      });

      if (payload.isNotEmpty) {
        await _sb.from('business_social_links').upsert(
              payload,
              onConflict: 'business_id,platform',
            );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Liens enregistrés.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _field(String label, String key, {String? hint}) {
    return TextField(
      controller: _controllers[key],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Liens & Réseaux'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _field('Site web', 'website', hint: 'https://...'),
                    const SizedBox(height: 12),
                    _field('WhatsApp', 'whatsapp', hint: '+228... ou lien wa.me'),
                    const SizedBox(height: 12),
                    _field('Facebook', 'facebook'),
                    const SizedBox(height: 12),
                    _field('Instagram', 'instagram'),
                    const SizedBox(height: 12),
                    _field('TikTok', 'tiktok'),
                    const SizedBox(height: 12),
                    _field('X (Twitter)', 'x'),
                    const SizedBox(height: 12),
                    _field('YouTube', 'youtube'),
                  ],
                ),
    );
  }
}
