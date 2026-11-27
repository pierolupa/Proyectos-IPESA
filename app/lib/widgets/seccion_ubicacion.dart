import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/estado_guia.dart';
import '../models/guia.dart';
import '../models/sucursal.dart';
import '../models/tipo_entrega.dart';
import 'mapa_ubicacion.dart';

/// Dónde se cargó una tarea ya cerrada: geo_* (que al entregar ya no se
/// pisa). En las cerradas antes de eso geo_* es el mismo punto de la
/// entrega; si salió de una de nuestras sucursales ([origen]), se usa esa.
/// Si no se sabe, null (no se inventa).
LatLng? puntoDeCarga(Guia g, Sucursal? origen) {
  if (!g.tieneUbicacionCierre) return null;
  final lat = g.ultimaLat, lng = g.ultimaLng;
  final mismoQueCierre =
      lat != null &&
      lng != null &&
      (lat - g.cierreLat!).abs() < 0.0002 &&
      (lng - g.cierreLng!).abs() < 0.0002;
  if (lat != null && lng != null && !mismoQueCierre) return LatLng(lat, lng);
  return origen == null ? null : LatLng(origen.lat, origen.lng);
}

/// Dónde se cargó y dónde se cerró la tarea (o la última ubicación, si
/// sigue abierta), en un mapa, con el perímetro de la sucursal destino si
/// es un traslado. La usan el detalle del administrador y el rastreo del
/// equipo comercial.
class SeccionUbicacion extends StatelessWidget {
  const SeccionUbicacion({
    super.key,
    required this.guia,
    this.perimetro,
    this.sucursalOrigen,
  });

  final Guia guia;
  final Sucursal? perimetro;

  /// La sucursal de donde salió, si es una de las nuestras: el punto de
  /// carga de las tareas cerradas antes de que se guardara aparte.
  final Sucursal? sucursalOrigen;

  @override
  Widget build(BuildContext context) {
    final titulo = Theme.of(context).textTheme.labelLarge;
    final gris = TextStyle(color: Colors.grey[700]);
    final avisoPerimetro = guia.tipoEntrega != TipoEntrega.entreSucursales
        ? null
        : perimetro == null
        ? Text(
            'La sucursal "${guia.destino}" no tiene perímetro marcado: la '
            'llegada no se podrá registrar. Márcalo en la pestaña Sucursales.',
            style: const TextStyle(color: Colors.red),
          )
        : Text(
            'Perímetro de ${perimetro!.nombre}: ${perimetro!.radioM.round()} m '
            '(círculo turquesa).',
            style: gris,
          );

    if (guia.tieneUbicacionCierre) {
      final fecha = guia.fechaCierre == null
          ? ''
          : ' el ${DateFormat('dd/MM/yyyy HH:mm').format(guia.fechaCierre!.toLocal())}';
      final carga = puntoDeCarga(guia, sucursalOrigen);
      final cargada = DateFormat('dd/MM/yyyy HH:mm')
          .format(guia.fechaCreacion.toLocal());
      final enSucursal =
          carga != null &&
          sucursalOrigen != null &&
          carga.latitude == sucursalOrigen!.lat &&
          carga.longitude == sucursalOrigen!.lng;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            carga == null
                ? 'Dónde se cerró la tarea'
                : 'Dónde se cargó y dónde se cerró',
            style: titulo,
          ),
          const SizedBox(height: 4),
          if (carga != null)
            _Punto(
              icono: const SizedBox(width: 16, height: 16, child: PuntoCarga()),
              texto:
                  'Cargada el $cargada · '
                  '${enSucursal ? 'en ${sucursalOrigen!.nombre}' : _coordenadas(carga.latitude, carga.longitude)}',
            ),
          _Punto(
            icono: const Icon(
              Icons.location_pin,
              size: 18,
              color: Color(0xFF1D6B41),
            ),
            texto:
                'Cerrada por ${guia.transportista}$fecha · '
                '${_coordenadas(guia.cierreLat!, guia.cierreLng!)}',
          ),
          if (carga != null)
            Text(
              'Distancia en línea recta: '
              '${_km(carga, LatLng(guia.cierreLat!, guia.cierreLng!))}',
              style: gris,
            ),
          ?avisoPerimetro,
          const SizedBox(height: 8),
          MapaUbicacion(
            lat: guia.cierreLat!,
            lng: guia.cierreLng!,
            perimetro: perimetro,
            carga: carga,
          ),
        ],
      );
    }

    final estaCerrada = guia.estado.esFinal;
    final rechazada = guia.estado == EstadoGuia.rechazado;
    final tieneUltima = guia.ultimaLat != null && guia.ultimaLng != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          estaCerrada
              ? 'Dónde se cerró la tarea'
              : rechazada
              ? 'Dónde se rechazó'
              : 'Última ubicación registrada',
          style: titulo,
        ),
        const SizedBox(height: 4),
        Text(
          estaCerrada
              ? 'Sin ubicación de cierre: la cerró un administrador a mano o '
                    'se cerró antes de que la app registrara el cierre.'
              : rechazada
              ? (tieneUltima
                    ? 'Última ubicación del transportista · '
                          '${_coordenadas(guia.ultimaLat!, guia.ultimaLng!)}'
                    : 'Sin ubicación registrada.')
              : tieneUltima
              ? 'Aún no se cierra. Último registro del transportista · '
                    '${_coordenadas(guia.ultimaLat!, guia.ultimaLng!)}'
              : 'Sin ubicación registrada.',
          style: gris,
        ),
        ?avisoPerimetro,
        if (!estaCerrada && tieneUltima) ...[
          const SizedBox(height: 8),
          MapaUbicacion(
            lat: guia.ultimaLat!,
            lng: guia.ultimaLng!,
            color: guia.estado.color,
            perimetro: perimetro,
          ),
        ],
      ],
    );
  }

  static String _coordenadas(double lat, double lng) =>
      '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';

  static String _km(LatLng a, LatLng b) {
    final metros = const Distance().as(LengthUnit.Meter, a, b);
    return metros < 1000
        ? '${metros.round()} m'
        : '${(metros / 1000).toStringAsFixed(1)} km';
  }
}

/// Una línea con su ícono: dónde se cargó o dónde se cerró.
class _Punto extends StatelessWidget {
  const _Punto({required this.icono, required this.texto});

  final Widget icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 20, child: Center(child: icono)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(texto, style: TextStyle(color: Colors.grey[700])),
          ),
        ],
      ),
    );
  }
}
