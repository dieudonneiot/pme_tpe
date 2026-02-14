import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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

  static const _contactPlatforms = <String>['website', 'whatsapp'];
  static const _socialPlatforms = <String>[
    'facebook',
    'instagram',
    'tiktok',
    'x',
    'youtube',
  ];

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

  bool get _hasAnyValue => _platforms.any((p) => _ctrl[p]!.text.trim().isNotEmpty);

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
      for (final p in _platforms) {
        _ctrl[p]!.text = '';
      }

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

  String _normalizeUrl(String platform, String raw) {
    var v = raw.trim();
    if (v.isEmpty) return '';

    // Allow already-valid URIs.
    final hasScheme = v.contains('://');

    String ensureHttps(String s) {
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
      return 'https://$s';
    }

    switch (platform) {
      case 'website':
        if (!hasScheme) v = ensureHttps(v);
        return v;

      case 'whatsapp':
        // Accept +228... or digits and convert to wa.me.
        if (!hasScheme && (v.startsWith('+') || RegExp(r'^[0-9 ]+$').hasMatch(v))) {
          final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
          if (digits.isEmpty) return '';
          return 'https://wa.me/$digits';
        }
        if (!hasScheme && v.startsWith('wa.me/')) return ensureHttps(v);
        return hasScheme ? v : ensureHttps(v);

      case 'instagram':
        if (!hasScheme) {
          if (v.startsWith('@')) v = v.substring(1);
          if (!v.contains('/') && !v.contains('.')) return 'https://instagram.com/$v';
          return ensureHttps(v);
        }
        return v;

      case 'facebook':
        if (!hasScheme) {
          if (!v.contains('/') && !v.contains('.')) return 'https://facebook.com/$v';
          return ensureHttps(v);
        }
        return v;

      case 'tiktok':
        if (!hasScheme) {
          if (v.startsWith('@')) v = v.substring(1);
          if (!v.contains('/') && !v.contains('.')) return 'https://www.tiktok.com/@$v';
          return ensureHttps(v);
        }
        return v;

      case 'x':
        if (!hasScheme) {
          if (v.startsWith('@')) v = v.substring(1);
          if (!v.contains('/') && !v.contains('.')) return 'https://x.com/$v';
          return ensureHttps(v);
        }
        return v;

      case 'youtube':
        if (!hasScheme) {
          // Allow handles like @mychannel
          if (v.startsWith('@')) return 'https://youtube.com/$v';
          if (!v.contains('/') && !v.contains('.')) return 'https://youtube.com/@$v';
          return ensureHttps(v);
        }
        return v;

      default:
        return hasScheme ? v : ensureHttps(v);
    }
  }

  Uri? _tryParseUri(String platform, String raw) {
    final normalized = _normalizeUrl(platform, raw);
    if (normalized.isEmpty) return null;
    return Uri.tryParse(normalized);
  }

  Future<void> _copy(String text, {String okMsg = 'Copié'}) async {
    final v = text.trim();
    if (v.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: v));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okMsg)));
  }

  Future<void> _openLink(String platform, String raw) async {
    final uri = _tryParseUri(platform, raw);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir le lien.')),
      );
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
        final raw = _ctrl[p]!.text.trim();
        final url = _normalizeUrl(p, raw);
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

      // Delete empty (single call)
      final empties = <String>[];
      for (final p in _platforms) {
        final raw = _ctrl[p]!.text.trim();
        final url = _normalizeUrl(p, raw);
        if (url.isEmpty) empties.add(p);
      }
      if (empties.isNotEmpty) {
        await sb
            .from('business_social_links')
            .delete()
            .eq('business_id', widget.businessId)
            .inFilter('platform', empties);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Liens enregistrés.')),
      );
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

  IconData _icon(String p) {
    switch (p) {
      case 'website':
        return Icons.language_outlined;
      case 'whatsapp':
        return Icons.chat_outlined;
      case 'facebook':
        return Icons.facebook_outlined;
      case 'instagram':
        return Icons.camera_alt_outlined;
      case 'tiktok':
        return Icons.movie_outlined;
      case 'x':
        return Icons.alternate_email;
      case 'youtube':
        return Icons.play_circle_outline;
      default:
        return Icons.link;
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

  String _hint(String p) {
    switch (p) {
      case 'website':
        return 'ex: https://monsite.com';
      case 'whatsapp':
        return 'ex: +228... ou wa.me/...';
      case 'facebook':
        return 'ex: facebook.com/ma-page ou ma-page';
      case 'instagram':
        return 'ex: instagram.com/moncompte ou @moncompte';
      case 'tiktok':
        return 'ex: tiktok.com/@moncompte ou moncompte';
      case 'x':
        return 'ex: x.com/moncompte ou @moncompte';
      case 'youtube':
        return 'ex: youtube.com/@moncompte ou @moncompte';
      default:
        return 'https://...';
    }
  }

  TextInputType _keyboard(String p) {
    if (p == 'whatsapp') return TextInputType.phone;
    return TextInputType.url;
  }

  Widget _headerCard() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withAlpha(20),
              scheme.tertiary.withAlpha(18),
              scheme.surfaceContainerHighest,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Icon(Icons.hub_outlined, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ajoute tes liens',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ils seront visibles sur la boutique publique et améliorent la confiance (contact, réseaux, etc.).',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          label: const Text('Auto-formatage'),
                          side: BorderSide(color: scheme.outlineVariant),
                          backgroundColor: scheme.surface,
                        ),
                        Chip(
                          label: const Text('Ouvrir / Copier'),
                          side: BorderSide(color: scheme.outlineVariant),
                          backgroundColor: scheme.surface,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String platform) {
    final raw = _ctrl[platform]!.text.trim();
    final canAct = raw.isNotEmpty;
    final normalized = canAct ? _normalizeUrl(platform, raw) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _ctrl[platform],
        keyboardType: _keyboard(platform),
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: _label(platform),
          hintText: _hint(platform),
          prefixIcon: Icon(_icon(platform)),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canAct)
                IconButton(
                  tooltip: 'Copier',
                  onPressed: () => _copy(normalized.isEmpty ? raw : normalized),
                  icon: const Icon(Icons.copy_outlined),
                ),
              if (canAct)
                IconButton(
                  tooltip: 'Ouvrir',
                  onPressed: () => _openLink(platform, raw),
                  icon: const Icon(Icons.open_in_new),
                ),
              if (canAct)
                IconButton(
                  tooltip: 'Effacer',
                  onPressed: () => setState(() => _ctrl[platform]!.clear()),
                  icon: const Icon(Icons.clear),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liens & réseaux'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Enregistrer'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null) ...[
                      Text(_error!, style: TextStyle(color: scheme.error)),
                      const SizedBox(height: 10),
                    ],

                    _headerCard(),
                    const SizedBox(height: 16),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Contact',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            for (final p in _contactPlatforms) _field(p),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Réseaux sociaux',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            for (final p in _socialPlatforms) _field(p),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 90),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _saving || !_hasAnyValue ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Enregistrer'),
            ),
          ),
        ),
      ),
    );
  }
}
