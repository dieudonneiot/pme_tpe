import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BusinessMembersPage extends StatefulWidget {
  final String businessId;
  const BusinessMembersPage({super.key, required this.businessId});

  @override
  State<BusinessMembersPage> createState() => _BusinessMembersPageState();
}

class _BusinessMembersPageState extends State<BusinessMembersPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  bool _busy = false;
  String? _error;

  String _myRole = 'staff';
  String _query = '';

  final List<_MemberVm> _members = [];

  bool get _isAdmin => _myRole == 'owner' || _myRole == 'admin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  // -----------------------------
  // Helpers
  // -----------------------------

  String _roleLabel(String r) {
    switch (r) {
      case 'owner':
        return 'Owner';
      case 'admin':
        return 'Admin';
      default:
        return 'Staff';
    }
  }

  String _safeErr(Object e) {
    if (e is PostgrestException) return e.message;
    if (e is AuthException) return e.message;
    if (e is StorageException) return e.message;
    return e.toString();
  }

  bool _isValidEmail(String s) {
    final v = s.trim();
    if (v.isEmpty) return false;
    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return re.hasMatch(v);
  }

  static String _shortUserId(String id) {
    if (id.length <= 8) return id;
    return '${id.substring(0, 4)}…${id.substring(id.length - 4)}';
  }

  static String _fmtDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  // -----------------------------
  // Load
  // -----------------------------

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _members.clear();
    });

    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) throw Exception('Session manquante.');

      // 1) Mon rôle
      final me = await _sb
          .from('business_members')
          .select('role')
          .eq('business_id', widget.businessId)
          .eq('user_id', uid)
          .maybeSingle();

      _myRole = (me?['role'] ?? 'staff').toString();

      // 2) Membres + profils : on tente d'abord le join PostgREST,
      // puis fallback si la relation n'est pas détectée/cachée.
      List<Map<String, dynamic>> rows;
      try {
        final resp = await _sb
            .from('business_members')
            .select('user_id, role, created_at, profiles(full_name, display_name, email, photo_url)')
            .eq('business_id', widget.businessId)
            .order('created_at', ascending: true);

        rows = (resp as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } on PostgrestException {
        final resp = await _sb
            .from('business_members')
            .select('user_id, role, created_at')
            .eq('business_id', widget.businessId)
            .order('created_at', ascending: true);

        final base = (resp as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        final userIds = base
            .map((m) => (m['user_id'] ?? '').toString())
            .where((x) => x.isNotEmpty)
            .toSet()
            .toList();

        Map<String, Map<String, dynamic>> profByUid = {};
        if (userIds.isNotEmpty) {
          // NOTE: construit une clause in('id1','id2'...)
          final inClause = '(${userIds.map((id) => "'$id'").join(',')})';

          final profResp = await _sb
              .from('profiles')
              .select('user_id, full_name, display_name, email, photo_url')
              .filter('user_id', 'in', inClause);

          final profList = (profResp as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

          profByUid = {
            for (final p in profList) (p['user_id'] ?? '').toString(): p,
          };
        }

        rows = base.map((m) {
          final id = (m['user_id'] ?? '').toString();
          return {
            ...m,
            'profiles': profByUid[id],
          };
        }).toList();
      }

      final vms = rows.map((m) {
        final userId = (m['user_id'] ?? '').toString();
        final role = (m['role'] ?? 'staff').toString();
        final createdAt = m['created_at']?.toString();

        Map<String, dynamic>? prof;
        final raw = m['profiles'];
        if (raw is Map) prof = Map<String, dynamic>.from(raw);

        final fullName = (prof?['full_name'] ?? '').toString().trim();
        final displayName = (prof?['display_name'] ?? '').toString().trim();
        final email = (prof?['email'] ?? '').toString().trim();
        final photoUrl = (prof?['photo_url'] ?? '').toString().trim();

        final name = fullName.isNotEmpty
            ? fullName
            : (displayName.isNotEmpty
                ? displayName
                : (email.isNotEmpty ? email.split('@').first : _shortUserId(userId)));

        return _MemberVm(
          userId: userId,
          role: role,
          name: name,
          email: email.isNotEmpty ? email : '—',
          photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
          createdAtIso: createdAt,
          isMe: userId == uid,
        );
      }).toList();

      if (!mounted) return;
      setState(() => _members.addAll(vms));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _safeErr(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // -----------------------------
  // Actions
  // -----------------------------

  Future<void> _addMemberFlow() async {
    if (!_isAdmin || _busy || _loading) return;

    final input = await showModalBottomSheet<_MemberInput>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _AddMemberSheet(),
    );

    if (input == null) return;

    // on ferme le clavier/focus proprement
    FocusManager.instance.primaryFocus?.unfocus();

    if (!_isValidEmail(input.email)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email invalide.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await _sb.rpc('add_business_member_by_email', params: {
        'bid': widget.businessId,
        'member_email': input.email.trim(),
        'new_role': input.role, // string: 'staff'|'admin' (cast enum côté PG)
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Membre ajouté : ${input.email}')),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: ${_safeErr(e)}')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _changeRoleFlow(_MemberVm m) async {
    if (!_isAdmin || _busy || _loading) return;
    if (m.role == 'owner' || m.isMe) return;

    final newRole = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ChangeRoleSheet(currentRole: m.role),
    );

    if (newRole == null || newRole == m.role) return;

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _busy = true);
    try {
      await _sb.rpc('update_business_member_role', params: {
        'bid': widget.businessId,
        'member_user_id': m.userId,
        'new_role': newRole, // cast enum côté PG
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rôle mis à jour: ${m.name} → ${_roleLabel(newRole)}')),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: ${_safeErr(e)}')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _removeMemberFlow(_MemberVm m) async {
    if (!_isAdmin || _busy || _loading) return;

    if (m.role == 'owner') return;
    if (m.isMe) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tu ne peux pas te retirer toi-même.')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Retirer ${m.name} ?'),
        content: const Text('Il perdra l’accès à cette entreprise.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Retirer')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _sb.rpc('remove_business_member', params: {
        'bid': widget.businessId,
        'member_user_id': m.userId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Membre retiré: ${m.name}')),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: ${_safeErr(e)}')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  // -----------------------------
  // UI
  // -----------------------------

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = _members.where((m) {
      if (q.isEmpty) return true;
      return m.name.toLowerCase().contains(q) || m.email.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Membres'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Rafraîchir',
            icon: const Icon(Icons.refresh),
          ),
          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: (_busy || _loading) ? null : _addMemberFlow,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Ajouter'),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? _ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _TopCard(
                        myRole: _roleLabel(_myRole),
                        total: _members.length,
                        adminMode: _isAdmin,
                        busy: _busy,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Rechercher par nom ou email…',
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 28),
                          child: Center(child: Text('Aucun membre trouvé.')),
                        )
                      else
                        ...filtered.map((m) {
                          final canEdit = _isAdmin && m.role != 'owner' && !m.isMe;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: (m.photoUrl != null) ? NetworkImage(m.photoUrl!) : null,
                                child: (m.photoUrl != null)
                                    ? null
                                    : Text(
                                        m.initial,
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      m.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _RolePill(role: m.role, isMe: m.isMe),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text('Ajouté: ${_fmtDate(m.createdAtIso)}'),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: canEdit
                                  ? PopupMenuButton<String>(
                                      onSelected: (v) {
                                        if (v == 'role') _changeRoleFlow(m);
                                        if (v == 'remove') _removeMemberFlow(m);
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(value: 'role', child: Text('Changer rôle')),
                                        PopupMenuItem(value: 'remove', child: Text('Retirer')),
                                      ],
                                    )
                                  : null,
                            ),
                          );
                        }),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
    );
  }
}

class _MemberVm {
  final String userId;
  final String role;
  final String name;
  final String email;
  final String? photoUrl;
  final String? createdAtIso;
  final bool isMe;

  _MemberVm({
    required this.userId,
    required this.role,
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.createdAtIso,
    required this.isMe,
  });

  String get initial {
    final t = name.trim();
    if (t.isEmpty || t == '—') return '?';
    final rune = t.runes.isEmpty ? null : t.runes.first;
    if (rune == null) return '?';
    return String.fromCharCode(rune).toUpperCase();
  }
}

class _TopCard extends StatelessWidget {
  final String myRole;
  final int total;
  final bool adminMode;
  final bool busy;

  const _TopCard({
    required this.myRole,
    required this.total,
    required this.adminMode,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total membres: $total', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Mon rôle: $myRole'),
                  const SizedBox(height: 6),
                  Text(adminMode ? 'Mode admin: ON' : 'Mode admin: OFF'),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  final String role;
  final bool isMe;

  const _RolePill({required this.role, required this.isMe});

  String _label() {
    switch (role) {
      case 'owner':
        return 'OWNER';
      case 'admin':
        return 'ADMIN';
      default:
        return 'STAFF';
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = isMe ? '${_label()} • MOI' : _label();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------
// Bottom sheets (sans Dropdown overlay)
// -----------------------------

class _MemberInput {
  final String email;
  final String role; // 'staff' or 'admin'
  const _MemberInput({required this.email, required this.role});
}

class _AddMemberSheet extends StatefulWidget {
  const _AddMemberSheet();

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _emailCtrl = TextEditingController();
  String _role = 'staff';
  String? _err;

  bool _isValidEmail(String s) {
    final v = s.trim();
    if (v.isEmpty) return false;
    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return re.hasMatch(v);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _emailCtrl.text.trim();
    if (!_isValidEmail(email)) {
      setState(() => _err = 'Email invalide.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(_MemberInput(email: email, role: _role));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: bottom + 16, top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ajouter un membre', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email du membre',
              hintText: 'ex: nom@gmail.com',
              errorText: _err,
            ),
            onChanged: (_) {
              if (_err != null) setState(() => _err = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          const Text('Rôle', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Staff'),
                selected: _role == 'staff',
                onSelected: (_) => setState(() => _role = 'staff'),
              ),
              ChoiceChip(
                label: const Text('Admin'),
                selected: _role == 'admin',
                onSelected: (_) => setState(() => _role = 'admin'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChangeRoleSheet extends StatefulWidget {
  final String currentRole;
  const _ChangeRoleSheet({required this.currentRole});

  @override
  State<_ChangeRoleSheet> createState() => _ChangeRoleSheetState();
}

class _ChangeRoleSheetState extends State<_ChangeRoleSheet> {
  late String _role;

  @override
  void initState() {
    super.initState();
    _role = widget.currentRole;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: bottom + 16, top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Changer le rôle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          const Text('Sélection', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Staff'),
                selected: _role == 'staff',
                onSelected: (_) => setState(() => _role = 'staff'),
              ),
              ChoiceChip(
                label: const Text('Admin'),
                selected: _role == 'admin',
                onSelected: (_) => setState(() => _role = 'admin'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.of(context).pop(_role);
                  },
                  child: const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
