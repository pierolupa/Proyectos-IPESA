import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/sucursal.dart';
import '../theme.dart';

const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _userAgent = 'pe.ipesa.tracking_distribucion';

/// Fondo del mapa mientras cargan los cuadros (el gris pizarra del mapa).
const fondoMapa = Color(0xFF191B1F);

/// Modo oscuro de los cuadros de OpenStreetMap (gratis, sin API key): se
/// invierten los colores (el texto queda claro), se gira el tono para que
/// el agua siga azul, y se apagan los colores hacia un gris pizarra:
/// suelo casi negro, agua azulada, parques verdes apagados y calles
/// tenues, sin los morados y naranjas fuertes de la inversión pura.
const _matrizOscura = <double>[
  0.021, -0.855, -0.086, 0, 244.6, //R
  -0.255, -0.579, -0.086, 0, 247.6, //G
  -0.255, -0.855, 0.190, 0, 253.6, //B
  0, 0, 0, 1, 0, //A
];

/// Capas base del mapa en modo oscuro. El filtro va sobre toda la capa
/// (uno solo), no sobre cada cuadro.
List<Widget> capasBaseMapa() => [
  ColorFiltered(
    colorFilter: const ColorFilter.matrix(_matrizOscura),
    child: TileLayer(urlTemplate: _tileUrl, userAgentPackageName: _userAgent),
  ),
];

/// Pin del mapa con un halo claro para que se vea sobre el fondo oscuro.
Widget pinMapa(Color color) => Icon(
  Icons.location_pin,
  color: color,
  size: 40,
  shadows: const [Shadow(color: Colors.white, blurRadius: 6)],
);

/// Punto de salida: un círculo con centro, distinto del pin de llegada.
Widget puntoSalidaMapa(Color color) => Container(
  width: 26,
  height: 26,
  decoration: BoxDecoration(
    color: Colors.white,
    shape: BoxShape.circle,
    border: Border.all(color: color, width: 4),
    boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 6)],
  ),
  child: Center(
    child: Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  ),
);

/// Atribución de OpenStreetMap, con el botón claro para verse sobre el
/// fondo oscuro.
final atribucionMapa = RichAttributionWidget(
  attributions: const [TextSourceAttribution('OpenStreetMap contributors')],
  openButton: (context, open) => IconButton(
    onPressed: open,
    tooltip: 'Atribuciones',
    icon: const Icon(Icons.info_outlined, color: Colors.white70, size: 20),
  ),
  closeButton: (context, close) => IconButton(
    onPressed: close,
    icon: const Icon(Icons.cancel_outlined, color: Colors.white70, size: 20),
  ),
);

CircleLayer capaPerimetro(Sucursal sucursal) => CircleLayer(
  circles: [
    CircleMarker(
      point: LatLng(sucursal.lat, sucursal.lng),
      radius: sucursal.radioM,
      useRadiusInMeter: true,
      color: Ipesa.turquesa.withValues(alpha: 0.15),
      borderColor: Ipesa.turquesa,
      borderStrokeWidth: 2,
    ),
  ],
);

Marker marcador(LatLng punto, Color color) => Marker(
  point: punto,
  width: 40,
  height: 40,
  alignment: Alignment.topCenter,
  child: pinMapa(color),
);

/// Color del punto de salida.
const colorSalida = Color(0xFF2459A8);

/// Mapa con un marcador (la llegada o la última ubicación) y, opcionalmente,
/// el punto de salida (con una línea recta hasta el marcador) y el perímetro
/// de una sucursal. Con dos puntos, el mapa se encuadra para verlos juntos.
class MapaUbicacion extends StatelessWidget {
  const MapaUbicacion({
    super.key,
    required this.lat,
    required this.lng,
    this.color = const Color(0xFF1D6B41),
    this.salida,
    this.perimetro,
    this.altura = 260,
  });

  final double lat;
  final double lng;
  final Color color;

  /// Dónde salió (se ve como un círculo azul).
  final LatLng? salida;
  final Sucursal? perimetro;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final punto = LatLng(lat, lng);
    final origen = salida;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: altura,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: punto,
            initialZoom: 16,
            backgroundColor: fondoMapa,
            initialCameraFit: origen == null
                ? null
                : CameraFit.coordinates(
                    coordinates: [origen, punto],
                    padding: const EdgeInsets.fromLTRB(56, 64, 56, 56),
                    maxZoom: 17,
                  ),
          ),
          children: [
            ...capasBaseMapa(),
            if (perimetro != null) capaPerimetro(perimetro!),
            if (origen != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [origen, punto],
                    color: Colors.white.withValues(alpha: 0.7),
                    strokeWidth: 2,
                    pattern: StrokePattern.dashed(segments: const [6, 6]),
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (origen != null)
                  Marker(
                    point: origen,
                    width: 26,
                    height: 26,
                    child: puntoSalidaMapa(colorSalida),
                  ),
                marcador(punto, color),
              ],
            ),
            atribucionMapa,
          ],
        ),
      ),
    );
  }
}
