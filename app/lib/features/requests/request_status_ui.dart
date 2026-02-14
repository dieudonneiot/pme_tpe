import 'package:flutter/material.dart';

class RequestStatusUi {
  static const flow = <String>[
    'new',
    'accepted',
    'in_progress',
    'delivered',
    'closed',
  ];

  static String label(String status) {
    switch (status) {
      case 'new':
        return 'En attente';
      case 'accepted':
        return 'Acceptée';
      case 'rejected':
        return 'Refusée';
      case 'in_progress':
        return 'En cours';
      case 'delivered':
        return 'Livrée';
      case 'closed':
        return 'Terminée';
      case 'cancelled':
        return 'Annulée';
      default:
        return status;
    }
  }

  static (Color bg, Color fg, IconData icon) style(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;

    switch (status) {
      case 'new':
        return (scheme.secondaryContainer, scheme.onSecondaryContainer, Icons.schedule);
      case 'accepted':
        return (scheme.primaryContainer, scheme.onPrimaryContainer, Icons.check_circle);
      case 'in_progress':
        return (scheme.tertiaryContainer, scheme.onTertiaryContainer, Icons.local_shipping_outlined);
      case 'delivered':
        return (Colors.green.withValues(alpha: 0.12), Colors.green, Icons.inventory_2_outlined);
      case 'closed':
        return (Colors.green.withValues(alpha: 0.12), Colors.green, Icons.verified);
      case 'rejected':
        return (Colors.red.withValues(alpha: 0.12), Colors.red, Icons.block);
      case 'cancelled':
        return (Colors.red.withValues(alpha: 0.12), Colors.red, Icons.cancel);
      default:
        return (scheme.surfaceContainerHighest, scheme.onSurface, Icons.info_outline);
    }
  }
}

class RequestStatusChip extends StatelessWidget {
  final String status;
  final bool dense;
  const RequestStatusChip({super.key, required this.status, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final s = RequestStatusUi.style(context, status);
    final pad = dense ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4) : const EdgeInsets.symmetric(horizontal: 12, vertical: 6);

    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: s.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.$3, size: dense ? 16 : 18, color: s.$2),
          const SizedBox(width: 6),
          Text(
            RequestStatusUi.label(status),
            style: TextStyle(fontWeight: FontWeight.w800, color: s.$2),
          ),
        ],
      ),
    );
  }
}

class RequestProgressBar extends StatelessWidget {
  final String status;
  const RequestProgressBar({super.key, required this.status});

  int _index(String s) => RequestStatusUi.flow.indexOf(s);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (status == 'cancelled' || status == 'rejected') {
      return Row(
        children: [
          RequestStatusChip(status: status),
          const Spacer(),
          Text('Terminé', style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      );
    }

    final i = _index(status);
    final steps = RequestStatusUi.flow;
    final current = i < 0 ? 0 : i;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            RequestStatusChip(status: status),
            const Spacer(),
            Text(
              '${current + 1}/${steps.length}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(steps.length, (idx) {
            final active = idx <= current;
            final isLast = idx == steps.length - 1;
            final color = active ? scheme.primary : scheme.surfaceContainerHighest;
            final dotFg = active ? scheme.onPrimary : scheme.onSurfaceVariant;

            return Expanded(
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${idx + 1}',
                      style: TextStyle(color: dotFg, fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: idx < current ? scheme.primary : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: steps.map((s) {
            final idx = _index(s);
            final done = idx <= current;
            return Text(
              RequestStatusUi.label(s),
              style: TextStyle(
                fontWeight: done ? FontWeight.w800 : FontWeight.w600,
                color: done ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class RequestTimeline extends StatelessWidget {
  final DateTime createdAt;
  final List<Map<String, dynamic>> history; // expects created_at + to_status
  const RequestTimeline({super.key, required this.createdAt, required this.history});

  String _fmt(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    final l = dt.toLocal();
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final events = <(String title, String subtitle, Color color)>[];
    events.add(('Créée', _fmt(createdAt), scheme.primary));

    final sorted = history
        .map((h) => Map<String, dynamic>.from(h))
        .where((h) => h['created_at'] != null)
        .toList()
      ..sort((a, b) => a['created_at'].toString().compareTo(b['created_at'].toString()));

    String? lastStatus;
    for (final h in sorted) {
      final to = (h['to_status'] ?? '').toString();
      if (to.isEmpty) continue;
      // avoid duplicates when both trigger+rpc log the same status change
      if (lastStatus == to) continue;
      lastStatus = to;

      final dt = DateTime.tryParse(h['created_at'].toString());
      final when = dt == null ? h['created_at'].toString() : _fmt(dt);
      final style = RequestStatusUi.style(context, to);

      events.add((RequestStatusUi.label(to), when, style.$2));
    }

    return Column(
      children: List.generate(events.length, (i) {
        final e = events[i];
        final isLast = i == events.length - 1;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: e.$3, shape: BoxShape.circle),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 34,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: scheme.outlineVariant,
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.$1, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(e.$2, style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

