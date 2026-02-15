import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'app_back_button.dart';

class PickedLocation {
  final double lat;
  final double lng;

  const PickedLocation({required this.lat, required this.lng});

  String toWktSrid4326() {
    String f(double v) => v.toStringAsFixed(6);
    // PostGIS expects POINT(lon lat) when using WKT.
    return 'SRID=4326;POINT(${f(lng)} ${f(lat)})';
  }

  LatLng toLatLng() => LatLng(lat, lng);
}

class LocationPickerPage extends StatefulWidget {
  final PickedLocation? initial;
  const LocationPickerPage({super.key, this.initial});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  late final MapController _controller;
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    _controller = MapController();
    _picked = widget.initial?.toLatLng();
  }

  void _pick(LatLng p) => setState(() => _picked = p);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final initial = _picked ?? const LatLng(6.1319, 1.2228); // Lomé (Togo)

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Choisir une position'),
        actions: [
          TextButton.icon(
            onPressed: _picked == null
                ? null
                : () {
                    final p = _picked!;
                    Navigator.of(
                      context,
                    ).pop(PickedLocation(lat: p.latitude, lng: p.longitude));
                  },
            icon: const Icon(Icons.check),
            label: const Text('Valider'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: initial,
                initialZoom: 12,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
                onTap: (tapPosition, point) => _pick(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'pme_tpe.flutter_application_1',
                ),
                MarkerLayer(
                  markers: [
                    if (_picked != null)
                      Marker(
                        point: _picked!,
                        width: 60,
                        height: 60,
                        child: Icon(
                          Icons.location_pin,
                          size: 44,
                          color: scheme.primary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _picked == null
                        ? 'Clique sur la carte pour choisir la position de livraison.'
                        : 'Position: ${_picked!.latitude.toStringAsFixed(6)}, ${_picked!.longitude.toStringAsFixed(6)}',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_picked != null)
                  IconButton(
                    tooltip: 'Effacer',
                    onPressed: () => setState(() => _picked = null),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
