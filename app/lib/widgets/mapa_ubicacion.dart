import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/sucursal.dart';

const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _userAgent = 'pe.ipesa.tracking_distribucion';

/// Capas base de OpenStreetMap (gratis, sin API key) + atribución.
List<Widget> capasBaseMapa() => [
  TileLayer(urlTemplate: _tileUrl, userAgentPackageName: _userAgent),
];

const atribucionMapa = RichAttributionWidget(
  attributions: [TextSourceAttribution('OpenStreetMap contributors')],
);

CircleLayer capaPerimetro(Sucursal sucursal) => CircleLayer(
  circles: [
    CircleMarker(
      point: LatLng(sucursal.lat, sucursal.lng),
      radius: sucursal.radioM,
      useRadiusInMeter: true,
      color: Colors.purple.withValues(alpha: 0.15),
      borderColor: Colors.purple,
      borderStrokeWidth: 2,
    ),
  ],
);

Marker marcador(LatLng punto, Color color) => Marker(
  point: punto,
  width: 40,
  height: 40,
  alignment: Alignment.topCenter,
  child: Icon(Icons.location_pin, color: color, size: 40),
);

/// Mapa con un marcador y, opcionalmente, el perímetro de una sucursal.
class MapaUbicacion extends StatelessWidget {
  const MapaUbicacion({
    super.key,
    required this.lat,
    required this.lng,
    this.color = Colors.red,
    this.perimetro,
    this.altura = 260,
  });

  final double lat;
  final double lng;
  final Color color;
  final Sucursal? perimetro;
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
            ...capasBaseMapa(),
            if (perimetro != null) capaPerimetro(perimetro!),
            MarkerLayer(markers: [marcador(punto, color)]),
            atribucionMapa,
          ],
        ),
      ),
    );
  }
}
