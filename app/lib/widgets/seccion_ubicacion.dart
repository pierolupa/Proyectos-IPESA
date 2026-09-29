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
    final formato = DateFormat('dd/MM/yyyy HH:mm');
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

    // Punto de salida: siempre se informa; en el mapa, si se sabe dónde fue.
    final filaSalida = _FilaPunto(
      marca: const _MarcaSalida(),
      etiqueta: 'Salida',
      lugar: guia.origen,
      detalle: [
        formato.format(guia.fechaCreacion.toLocal()),
        salida == null
            ? 'sin ubicación registrada'
            : _coordenadas(salida.latitude, salida.longitude),
      ].join(' · '),
    );

    if (guia.tieneUbicacionCierre) {
      final origen = _distinta(salida, guia.cierreLat!, guia.cierreLng!);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Salida y llegada', style: titulo),
          const SizedBox(height: 8),
          filaSalida,
          const SizedBox(height: 8),
          _FilaPunto(
            marca: const _MarcaLlegada(color: Color(0xFF1D6B41)),
            etiqueta: 'Llegada',
            lugar: guia.destino,
            detalle: [
              if (guia.fechaCierre != null)
                'Cerrada por ${guia.transportista} el '
                    '${formato.format(guia.fechaCierre!.toLocal())}'
              else
                'Cerrada por ${guia.transportista}',
              _coordenadas(guia.cierreLat!, guia.cierreLng!),
            ].join(' · '),
          ),
          ?avisoPerimetro,
          const SizedBox(height: 10),
          MapaUbicacion(
            lat: guia.cierreLat!,
            lng: guia.cierreLng!,
            salida: origen,
            perimetro: perimetro,
          ),
          if (origen != null)
            _Distancia(
              salida: origen,
              lat: guia.cierreLat!,
              lng: guia.cierreLng!,
            ),
        ],
      );
    }

    final estaCerrada = guia.estado.esFinal;
    final rechazada = guia.estado == EstadoGuia.rechazado;
    final tieneUltima = guia.ultimaLat != null && guia.ultimaLng != null;
    final origen = tieneUltima
        ? _distinta(salida, guia.ultimaLat!, guia.ultimaLng!)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Salida y llegada', style: titulo),
        const SizedBox(height: 8),
        filaSalida,
        const SizedBox(height: 8),
        _FilaPunto(
          marca: _MarcaLlegada(color: guia.estado.color),
          etiqueta: estaCerrada
              ? 'Llegada'
              : rechazada
              ? 'Rechazada'
              : 'Última ubicación',
          lugar: estaCerrada ? guia.destino : '',
          detalle: estaCerrada
              ? 'Sin ubicación de cierre: la cerró un administrador a mano o '
                    'se cerró antes de que la app registrara el cierre.'
              : rechazada
              ? (tieneUltima
                    ? 'Última ubicación del transportista · '
                          '${_coordenadas(guia.ultimaLat!, guia.ultimaLng!)}'
                    : 'Sin ubicación registrada.')
              : tieneUltima
              ? 'Aún no llega. Último registro del transportista · '
                    '${_coordenadas(guia.ultimaLat!, guia.ultimaLng!)}'
              : 'Sin ubicación registrada.',
        ),
        ?avisoPerimetro,
        if (!estaCerrada && tieneUltima) ...[
          const SizedBox(height: 10),
          MapaUbicacion(
            lat: guia.ultimaLat!,
            lng: guia.ultimaLng!,
            color: guia.estado.color,
            salida: origen,
            perimetro: perimetro,
          ),
          if (origen != null)
            _Distancia(
              salida: origen,
              lat: guia.ultimaLat!,
              lng: guia.ultimaLng!,
            ),
        ],
      ],
    );
  }

  static String _coordenadas(double lat, double lng) =>
      '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
}

/// Una fila del informe: la marca del mapa, "Salida"/"Llegada", el lugar
/// y debajo la fecha y las coordenadas.
class _FilaPunto extends StatelessWidget {
  const _FilaPunto({
    required this.marca,
    required this.etiqueta,
    required this.lugar,
    required this.detalle,
  });

  final Widget marca;
  final String etiqueta;
  final String lugar;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: Padding(padding: const EdgeInsets.only(top: 2), child: marca),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: etiqueta,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Ipesa.texto,
                      ),
                    ),
                    if (lugar.trim().isNotEmpty)
                      TextSpan(text: ' · ${lugar.trim()}'),
                  ],
                ),
                style: const TextStyle(fontSize: 15, color: Ipesa.etiqueta),
              ),
              Text(
                detalle,
                style: TextStyle(fontSize: 13.5, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MarcaSalida extends StatelessWidget {
  const _MarcaSalida();

  @override
  Widget build(BuildContext context) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white,
      border: Border.all(color: colorSalida, width: 4),
    ),
  );
}

class _MarcaLlegada extends StatelessWidget {
  const _MarcaLlegada({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.location_pin, size: 20, color: color);
}

/// Bajo el mapa: a cuánto quedan los dos puntos en línea recta.
class _Distancia extends StatelessWidget {
  const _Distancia({
    required this.salida,
    required this.lat,
    required this.lng,
  });

  final LatLng salida;
  final double lat;
  final double lng;

  @override
  Widget build(BuildContext context) {
    final metros = distanciaMetros(salida.latitude, salida.longitude, lat, lng);
    final texto = metros < 1000
        ? '${metros.round()} m'
        : '${(metros / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        '$texto en línea recta entre la salida y la llegada',
        style: const TextStyle(fontSize: 13.5, color: Ipesa.textoSuave),
      ),
    );
  }
}
