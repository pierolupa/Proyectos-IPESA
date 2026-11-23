import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/sucursal.dart';
import '../theme.dart';

const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _userAgent = 'pe.ipesa.tracking_distribucion';

/// Fondo del mapa mientras cargan los cuadros (oscuro, como el mapa).
const fondoMapa = Color(0xFF1E2327);

/// Capas base de OpenStreetMap (gratis, sin API key) en modo oscuro: los
/// mismos cuadros de siempre con los colores invertidos en el celular.
/// El filtro va sobre toda la capa (uno solo), no sobre cada cuadro.
List<Widget> capasBaseMapa() => [
  Builder(
    builder: (context) => darkModeTilesContainerBuilder(
      context,
      TileLayer(urlTemplate: _tileUrl, userAgentPackageName: _userAgent),
    ),
  ),
];

/// Pin del mapa con un halo claro para que se vea sobre el fondo oscuro.
Widget pinMapa(Color color) => Icon(
  Icons.location_pin,
  color: color,
  size: 40,
  shadows: const [Shadow(color: Colors.white, blurRadius: 6)],
);

const atribucionMapa = RichAttributionWidget(
  attributions: [TextSourceAttribution('OpenStreetMap contributors')],
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

/// Color del punto donde se cargó la tarea (azul, como "En ruta").
const colorCarga = Color(0xFF2459A8);

/// Se ve sobre el mapa oscuro.
const colorTrayecto = Color(0xFF7FD1C7);

/// Dónde se cargó una tarea: un anillo con una caja, para no confundirlo
/// con el pin de la entrega.
class PuntoCarga extends StatelessWidget {
  const PuntoCarga({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: colorCarga, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
      ),
      child: const Icon(Icons.inventory_2_rounded, size: 11, color: colorCarga),
    );
  }
}

/// Mapa con un marcador y, opcionalmente, el perímetro de una sucursal.
/// Con [carga], también dónde se cargó la tarea y una línea hasta el
/// marcador (dónde se entregó), con los dos a la vista.
class MapaUbicacion extends StatelessWidget {
  const MapaUbicacion({
    super.key,
    required this.lat,
    required this.lng,
    this.color = const Color(0xFF1D6B41),
    this.perimetro,
    this.carga,
    this.altura = 260,
  });

  final double lat;
  final double lng;
  final Color color;
  final Sucursal? perimetro;
  final LatLng? carga;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final punto = LatLng(lat, lng);
    final origen = carga;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: altura,
        child: FlutterMap(
          options: origen == null
              ? MapOptions(
                  initialCenter: punto,
                  initialZoom: 16,
                  backgroundColor: fondoMapa,
                )
              : MapOptions(
                  initialCameraFit: CameraFit.coordinates(
                    coordinates: [origen, punto],
                    padding: const EdgeInsets.fromLTRB(48, 56, 48, 40),
                    maxZoom: 16,
                  ),
                  backgroundColor: fondoMapa,
                ),
          children: [
            ...capasBaseMapa(),
            if (perimetro != null) capaPerimetro(perimetro!),
            if (origen != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [origen, punto],
                    strokeWidth: 3,
                    color: colorTrayecto,
                    pattern: StrokePattern.dashed(segments: const [10, 7]),
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
                    child: const Tooltip(
                      message: 'Dónde se cargó',
                      child: PuntoCarga(),
                    ),
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
