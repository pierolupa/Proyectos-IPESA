import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/estado_guia.dart';
import '../models/guia.dart';
import '../models/sucursal.dart';
import '../models/tipo_entrega.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'mapa_ubicacion.dart';

/// Dónde se cerró la tarea (o la última ubicación, si sigue abierta), en
/// un mapa, junto al punto de salida y con el perímetro de la sucursal
/// destino si es un traslado.
/// La usan el detalle del administrador y el rastreo del equipo comercial.
class SeccionUbicacion extends StatelessWidget {
  const SeccionUbicacion({super.key, required this.guia, this.perimetro});

  final Guia guia;
  final Sucursal? perimetro;

  /// Dónde salió: lo guardado al registrar la guía o, en las anteriores a
  /// ese dato, la sucursal que figura como punto de partida.
  LatLng? _salida(List<Sucursal> sucursales) {
    if (guia.tieneSalida) return LatLng(guia.salidaLat!, guia.salidaLng!);
    final nombre = guia.origen.trim().toLowerCase();
    for (final s in sucursales) {
      if (s.nombre.trim().toLowerCase() == nombre) return LatLng(s.lat, s.lng);
    }
    return null;
  }

  /// Solo se dibuja la salida si queda lejos del otro punto; si no, sería
  /// un círculo debajo del pin.
  static LatLng? _distinta(LatLng? salida, double lat, double lng) {
    if (salida == null) return null;
    final metros = distanciaMetros(salida.latitude, salida.longitude, lat, lng);
    return metros < 30 ? null : salida;
  }

  @override
  Widget build(BuildContext context) {
    final salida = _salida(context.read<AppState>().sucursales);
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dónde se cerró la tarea', style: titulo),
          const SizedBox(height: 4),
          Text(
            'Cerrada por ${guia.transportista}$fecha · '
            '${_coordenadas(guia.cierreLat!, guia.cierreLng!)}',
            style: gris,
          ),
          ?avisoPerimetro,
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final origen = _distinta(
                salida,
                guia.cierreLat!,
                guia.cierreLng!,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MapaUbicacion(
                    lat: guia.cierreLat!,
                    lng: guia.cierreLng!,
                    salida: origen,
                    perimetro: perimetro,
                  ),
                  if (origen != null)
                    _LeyendaRecorrido(
                      salida: origen,
                      nombreSalida: guia.origen,
                      lat: guia.cierreLat!,
                      lng: guia.cierreLng!,
                      etiquetaLlegada: 'Llegada',
                      nombreLlegada: guia.destino,
                      colorLlegada: const Color(0xFF1D6B41),
                    ),
                ],
              );
            },
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
          Builder(
            builder: (context) {
              final origen = _distinta(
                salida,
                guia.ultimaLat!,
                guia.ultimaLng!,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MapaUbicacion(
                    lat: guia.ultimaLat!,
                    lng: guia.ultimaLng!,
                    color: guia.estado.color,
                    salida: origen,
                    perimetro: perimetro,
                  ),
                  if (origen != null)
                    _LeyendaRecorrido(
                      salida: origen,
                      nombreSalida: guia.origen,
                      lat: guia.ultimaLat!,
                      lng: guia.ultimaLng!,
                      etiquetaLlegada: rechazada
                          ? 'Rechazada aquí'
                          : 'Última ubicación',
                      nombreLlegada: '',
                      colorLlegada: guia.estado.color,
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  static String _coordenadas(double lat, double lng) =>
      '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
}

/// Bajo el mapa: qué es cada punto y a cuánto quedan en línea recta.
class _LeyendaRecorrido extends StatelessWidget {
  const _LeyendaRecorrido({
    required this.salida,
    required this.nombreSalida,
    required this.lat,
    required this.lng,
    required this.etiquetaLlegada,
    required this.nombreLlegada,
    required this.colorLlegada,
  });

  final LatLng salida;
  final String nombreSalida;
  final double lat;
  final double lng;
  final String etiquetaLlegada;
  final String nombreLlegada;
  final Color colorLlegada;

  static String _distancia(double metros) => metros < 1000
      ? '${metros.round()} m'
      : '${(metros / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

  @override
  Widget build(BuildContext context) {
    final metros = distanciaMetros(salida.latitude, salida.longitude, lat, lng);
    Widget punto(Widget marca, String etiqueta, String nombre) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        marca,
        const SizedBox(width: 8),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$etiqueta  ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Ipesa.texto,
                  ),
                ),
                if (nombre.trim().isNotEmpty) TextSpan(text: nombre),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, color: Ipesa.etiqueta),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 22,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          punto(
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: colorSalida, width: 3.5),
              ),
            ),
            'Salida',
            nombreSalida,
          ),
          punto(
            Icon(Icons.location_pin, size: 18, color: colorLlegada),
            etiquetaLlegada,
            nombreLlegada,
          ),
          Text(
            '${_distancia(metros)} en línea recta',
            style: const TextStyle(fontSize: 13.5, color: Ipesa.textoSuave),
          ),
        ],
      ),
    );
  }
}
