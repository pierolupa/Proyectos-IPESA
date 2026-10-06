import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/estado_guia.dart';
import '../models/guia.dart';
import '../state/app_state.dart';
import '../theme.dart';

final _fechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Cuándo se cerró la guía (entregada o rechazada); null si sigue abierta.
DateTime? fechaDeCierre(Guia g) => g.estado.esCerrada
    ? (g.fechaCierre ?? g.fechaActualizacion).toLocal()
    : null;

/// "06/10/2026 10:15", la fecha y hora de cierre; '' si sigue abierta.
String textoFechaCierre(Guia g) {
  final f = fechaDeCierre(g);
  return f == null ? '' : _fechaHora.format(f);
}

/// La sucursal (de las marcadas en el mapa) donde se recogió la guía.
String? sucursalDeRecojo(BuildContext context, Guia g) =>
    context.read<AppState>().sucursalPorNombre(g.origen)?.nombre;

/// La sucursal donde se entregó la guía; null si no se entregó en una.
String? sucursalDeEntrega(BuildContext context, Guia g) => g.estado.esFinal
    ? context.read<AppState>().sucursalPorNombre(g.destino)?.nombre
    : null;

/// Dónde se recogió y dónde se entregó la guía, solo cuando es una de
/// nuestras sucursales. Con [conCierre] agrega además la fecha y hora en
/// que se entregó o rechazó (en una sucursal o no).
class LugaresSucursal extends StatelessWidget {
  const LugaresSucursal({
    super.key,
    required this.guia,
    this.conCierre = false,
  });

  final Guia guia;
  final bool conCierre;

  @override
  Widget build(BuildContext context) {
    final recojo = sucursalDeRecojo(context, guia);
    final entrega = sucursalDeEntrega(context, guia);
    final fecha = conCierre ? textoFechaCierre(guia) : '';
    final rechazada = guia.estado == EstadoGuia.rechazado;

    final filas = <Widget>[
      if (recojo != null)
        _Fila(
          icono: Icons.warehouse_outlined,
          texto: 'Recogida en $recojo',
          color: Ipesa.petroleo,
        ),
      if (entrega != null)
        _Fila(
          icono: Icons.where_to_vote_outlined,
          texto: [
            'Entregada en $entrega',
            if (fecha.isNotEmpty) fecha,
          ].join(' · '),
          color: EstadoGuia.entregado.color,
        )
      else if (fecha.isNotEmpty)
        _Fila(
          icono: rechazada
              ? Icons.block_rounded
              : Icons.event_available_outlined,
          texto: '${rechazada ? 'Rechazada' : 'Entregada'} $fecha',
          color: guia.estado.color,
        ),
    ];
    if (filas.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: filas,
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.icono, required this.texto, required this.color});

  final IconData icono;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icono, size: 15, color: color),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
