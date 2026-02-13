import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BusinessPostsPage extends StatefulWidget {
  final String businessId;
  const BusinessPostsPage({super.key, required this.businessId});

  @override
  State<BusinessPostsPage> createState() => _BusinessPostsPageState();
}

class _BusinessPostsPageState extends State<BusinessPostsPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _posts = [];

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
      final resp = await _sb
          .from('posts')
          .select('id,title,content,created_at,is_published')
          .eq('business_id', widget.businessId)
          .order('created_at', ascending: false);

      setState(() {
        _posts = (resp as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.push('/home'),
        ),
        title: const Text('Posts'),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Colors.red))))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _posts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final p = _posts[i];
                    final id = (p['id'] ?? '').toString();
                    final title = (p['title'] ?? 'Sans titre').toString();
                    final published = p['is_published'] == true;

                    return Card(
                      child: ListTile(
                        title: Text(title),
                        subtitle: Text(published ? 'Publié' : 'Brouillon'),
                        onTap: () => context.push('/business/${widget.businessId}/posts/$id'),
                      ),
                    );
                  },
                ),
    );
  }
}
