import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/estado_guia.dart';
import '../models/guia.dart';
import '../models/sucursal.dart';
import '../models/tipo_entrega.dart';
import 'mapa_ubicacion.dart';

/// Dónde se cerró la tarea (o la última ubicación, si sigue abierta), en
/// un mapa, con el perímetro de la sucursal destino si es un traslado.
/// La usan el detalle del administrador y el rastreo del equipo comercial.
class SeccionUbicacion extends StatelessWidget {
  const SeccionUbicacion({super.key, required this.guia, this.perimetro});

  final Guia guia;
  final Sucursal? perimetro;

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
          MapaUbicacion(
            lat: guia.cierreLat!,
            lng: guia.cierreLng!,
            perimetro: perimetro,
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
}
