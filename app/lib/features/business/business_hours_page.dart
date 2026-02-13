import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BusinessHoursPage extends StatefulWidget {
  final String businessId;
  const BusinessHoursPage({super.key, required this.businessId});

  @override
  State<BusinessHoursPage> createState() => _BusinessHoursPageState();
}

class _BusinessHoursPageState extends State<BusinessHoursPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final Map<int, bool> _closed = {};
  final Map<int, TimeOfDay> _opens = {};
  final Map<int, TimeOfDay> _closes = {};

  @override
  void initState() {
    super.initState();
    _initDefaults();
    _load();
  }

  void _initDefaults() {
    for (var d = 1; d <= 7; d++) {
      _closed[d] = true;
      _opens[d] = const TimeOfDay(hour: 8, minute: 0);
      _closes[d] = const TimeOfDay(hour: 17, minute: 0);
    }
  }

  String _dayLabel(int d) {
    switch (d) {
      case 1:
        return 'Lundi';
      case 2:
        return 'Mardi';
      case 3:
        return 'Mercredi';
      case 4:
        return 'Jeudi';
      case 5:
        return 'Vendredi';
      case 6:
        return 'Samedi';
      case 7:
        return 'Dimanche';
      default:
        return 'Jour';
    }
  }

  TimeOfDay _parseTime(String s) {
    // attendu: "HH:MM:SS" ou "HH:MM"
    final parts = s.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return TimeOfDay(hour: h, minute: m);
  }

  String _timeToPg(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm:00';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sb = Supabase.instance.client;
      final rows = await sb
          .from('business_hours')
          .select('day_of_week,is_closed,opens_at,closes_at')
          .eq('business_id', widget.businessId);

      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        final d = (m['day_of_week'] as num).toInt();
        _closed[d] = m['is_closed'] == true;

        final opens = m['opens_at']?.toString();
        final closes = m['closes_at']?.toString();
        if (opens != null) _opens[d] = _parseTime(opens);
        if (closes != null) _closes[d] = _parseTime(closes);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickTime(int day, bool isOpen) async {
    final initial = isOpen ? _opens[day]! : _closes[day]!;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;

    setState(() {
      if (isOpen) {
        _opens[day] = picked;
      } else {
        _closes[day] = picked;
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final sb = Supabase.instance.client;

      final payload = <Map<String, dynamic>>[];
      for (var d = 1; d <= 7; d++) {
        final closed = _closed[d] == true;
        payload.add({
          'business_id': widget.businessId,
          'day_of_week': d,
          'is_closed': closed,
          'opens_at': closed ? null : _timeToPg(_opens[d]!),
          'closes_at': closed ? null : _timeToPg(_closes[d]!),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      await sb.from('business_hours').upsert(
            payload,
            onConflict: 'business_id,day_of_week',
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Horaires enregistrés.')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Horaires'),
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
                ...List.generate(7, (i) {
                  final day = i + 1;
                  final closed = _closed[day] == true;
                  final open = _opens[day]!;
                  final close = _closes[day]!;

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _dayLabel(day),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Switch(
                                value: !closed,
                                onChanged: (v) => setState(() => _closed[day] = !v),
                              ),
                              Text(closed ? 'Fermé' : 'Ouvert'),
                            ],
                          ),
                          if (!closed) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _pickTime(day, true),
                                    child: Text('Ouvre: ${open.format(context)}'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _pickTime(day, false),
                                    child: Text('Ferme: ${close.format(context)}'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
