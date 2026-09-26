import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Mapa de OpenStreetMap (gratis, sin API key) con un solo marcador.
class MapaUbicacion extends StatelessWidget {
  const MapaUbicacion({
    super.key,
    required this.lat,
    required this.lng,
    this.color = Colors.red,
    this.altura = 260,
  });

  final double lat;
  final double lng;
  final Color color;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final punto = LatLng(lat, lng);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: altura,
        child: FlutterMap(
          options: MapOptions(initialCenter: punto, initialZoom: 16),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'pe.ipesa.tracking_distribucion',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: punto,
                  width: 40,
                  height: 40,
                  alignment: Alignment.topCenter,
                  child: Icon(Icons.location_pin, color: color, size: 40),
                ),
              ],
            ),
            const RichAttributionWidget(
              attributions: [TextSourceAttribution('OpenStreetMap contributors')],
            ),
          ],
        ),
      ),
    );
  }
}
