import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/app_back_button.dart';
import '../../core/widgets/location_picker_page.dart';
import 'cart_scope.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _LocationChip extends StatelessWidget {
  final PickedLocation location;
  const _LocationChip({required this.location});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.my_location, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            '${location.lat.toStringAsFixed(5)}, ${location.lng.toStringAsFixed(5)}',
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutPageState extends State<CheckoutPage> {
  final sb = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  bool _loading = false;
  String? _errorText;
  PickedLocation? _pickedLocation;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _redirectToLogin(GoRouter router) {
    // Conserve l'historique : push, pas go.
    router.push('/login?next=/checkout');
  }

  void _setError(String? message) {
    if (!mounted) return;
    setState(() => _errorText = message);
  }

  String _friendlyFunctionError(FunctionException e) {
    final status = e.status;
    final details = e.details;

    String? msg;
    if (details is Map && details['error'] is String) {
      msg = details['error'] as String;
    } else if (details is String) {
      msg = details;
    }

    if (status == 401) return "Session expirée. Reconnecte-toi et réessaie.";
    if (status == 403) return "Action non autorisée.";
    if (status == 400) {
      return msg?.isNotEmpty == true
          ? msg!
          : "Paiement indisponible. Réessaie.";
    }
    if (status >= 500) {
      if (msg?.isNotEmpty == true) return msg!;
      return "Erreur serveur pendant le paiement. Réessaie dans un instant.";
    }
    return msg?.isNotEmpty == true ? msg! : "Erreur de paiement. Réessaie.";
  }

  Future<void> _pickOnMap() async {
    final res = await Navigator.of(context).push<PickedLocation?>(
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(initial: _pickedLocation),
      ),
    );
    if (res == null) return;
    setState(() => _pickedLocation = res);
  }

  Future<void> _pay() async {
    // Capture avant async gaps => pas de use_build_context_synchronously.
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final cart = CartScope.of(context);
    _setError(null);

    if (cart.isEmpty) {
      _setError('Ton panier est vide.');
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final user = sb.auth.currentUser;
    if (user == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Connecte-toi d'abord pour payer.")),
      );
      _redirectToLogin(router);
      return;
    }

    setState(() => _loading = true);

    try {
      final businessId = cart.businessId!;
      final total = cart.subtotal;

      // 1) Créer service_request.
      final loc = _pickedLocation;
      final reqRow = await sb
          .from('service_requests')
          .insert({
            'business_id': businessId,
            'customer_user_id': user.id,
            'type': 'catalog',
            'status': 'new',
            'total_estimate': total,
            'currency': cart.currency,
            'address_text': _addressCtrl.text.trim(),
            if (loc != null) 'location': loc.toWktSrid4326(),
            'notes':
                'Commande depuis mini-site • Nom=${_nameCtrl.text.trim()} • Tel=${_phoneCtrl.text.trim()}',
          })
          .select('id')
          .single();

      final requestId = reqRow['id'] as String;

      // 2) Créer service_request_items.
      final itemsPayload = cart.items.map((it) {
        final parts = it.productId.split('::');
        final productId = parts.first;
        final variantId = parts.length > 1 ? parts[1] : null;
        return {
          'request_id': requestId,
          'product_id': productId,
          'variant_id': (variantId == null || variantId.isEmpty)
              ? null
              : variantId,
          'title_snapshot': it.title,
          'qty': it.qty,
          'unit_price_snapshot': it.unitPrice,
        };
      }).toList();

      try {
        await sb.from('service_request_items').insert(itemsPayload);
      } on PostgrestException catch (e) {
        // Backward-compatible: variant_id column might not exist yet.
        if (e.message.toLowerCase().contains('variant_id')) {
          for (final r in itemsPayload) {
            r.remove('variant_id');
          }
          await sb.from('service_request_items').insert(itemsPayload);
        } else {
          rethrow;
        }
      }

      // 3) Appeler Edge Function paiement (nom = dossier de la function).
      final res = await sb.functions.invoke(
        'create_payment_intent',
        body: {'request_id': requestId, 'provider': 'PAYDUNYA'},
      );

      final data = res.data;
      final url = (data is Map) ? (data['payment_url'] as String?) : null;
      if (url == null || url.isEmpty) {
        throw Exception('Aucune URL de paiement retournée.');
      }

      messenger.showSnackBar(
        const SnackBar(content: Text('Redirection vers paiement...')),
      );

      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        throw Exception("Impossible d'ouvrir l'URL de paiement.");
      }

      cart.clear();

      if (!mounted) return;
      router.go('/requests/$requestId'); // suivi commande
    } on FunctionException catch (e) {
      _setError(_friendlyFunctionError(e));
    } on PostgrestException catch (e) {
      final m = e.message.toLowerCase();
      final isRls =
          m.contains('row-level security') ||
          m.contains('rls') ||
          e.code == '42501';
      final isEntitlement =
          m.contains('not allowed to receive orders') ||
          m.contains('entitlements') ||
          m.contains('requests_insert_customer');

      if (isRls && isEntitlement) {
        _setError(
          "Cette boutique n'est pas autorisée à recevoir des commandes (abonnement ou autorisation admin requise).",
        );
      } else {
        _setError('Erreur commande: ${e.message}');
      }
    } catch (e) {
      _setError('Erreur: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _summaryCard(BuildContext context) {
    final cart = CartScope.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Récapitulatif',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${cart.subtotal} ${cart.currency}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (cart.items.isEmpty)
              Text(
                'Aucun article.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              ...cart.items.map((it) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 44,
                          height: 44,
                          color: scheme.surfaceContainerHighest,
                          child: (it.mediaUrl == null || it.mediaUrl!.isEmpty)
                              ? Icon(
                                  Icons.image_outlined,
                                  color: scheme.onSurfaceVariant,
                                )
                              : Image.network(
                                  it.mediaUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Icon(
                                        Icons.broken_image_outlined,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${it.qty} x ${it.unitPrice} ${it.currency}',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${it.lineTotal} ${it.currency}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _customerCard(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_outline),
                const SizedBox(width: 10),
                Text(
                  'Tes infos',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nom complet',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Téléphone',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Téléphone requis' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(
                labelText: 'Adresse complète',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              maxLines: 2,
              textInputAction: TextInputAction.done,
              validator: (v) {
                final hasText = v != null && v.trim().isNotEmpty;
                final hasPoint = _pickedLocation != null;
                if (hasText || hasPoint) return null;
                return 'Adresse ou position requise';
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickOnMap,
                  icon: const Icon(Icons.map_outlined),
                  label: Text(
                    _pickedLocation == null
                        ? 'Choisir sur la carte'
                        : 'Modifier la position',
                  ),
                ),
                if (_pickedLocation != null)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _pickedLocation = null),
                    icon: const Icon(Icons.close),
                    label: const Text('Retirer'),
                  ),
                if (_pickedLocation != null)
                  _LocationChip(location: _pickedLocation!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Fermer',
            onPressed: () => _setError(null),
            icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = CartScope.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackPath: '/cart'),
        title: const Text('Finaliser la commande'),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 980;

            final summary = _summaryCard(context);
            final customer = _customerCard(context);

            final content = isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: summary),
                      const SizedBox(width: 16),
                      Expanded(child: customer),
                    ],
                  )
                : Column(
                    children: [summary, const SizedBox(height: 12), customer],
                  );

            return Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: content,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_errorText != null) ...[
                            _errorCard(context, _errorText!),
                            const SizedBox(height: 12),
                          ],
                          FilledButton.icon(
                            onPressed: _loading ? null : _pay,
                            icon: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.payment),
                            label: Text(
                              _loading
                                  ? 'Traitement...'
                                  : 'Procéder au paiement',
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Note : si la boutique n'a pas l'autorisation de recevoir des commandes (entitlements), la création de commande peut être bloquée par RLS.",
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          if (!cart.isEmpty)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  'Total : ',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text(
                                  '${cart.subtotal} ${cart.currency}',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
