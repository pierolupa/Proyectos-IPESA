import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/tipo_entrega.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/estado_badge.dart';
import '../../widgets/foto_entrega.dart';
import '../../widgets/seccion_ubicacion.dart';

final _fechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Detalle de una guía para el equipo comercial (solo lectura): datos,
/// fechas, foto de la entrega y dónde se entregó.
class RastreoDetalleScreen extends StatelessWidget {
  const RastreoDetalleScreen({super.key, required this.numeroGuia});

  final String numeroGuia;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final guia = appState.buscarPorNumero(numeroGuia);
    if (guia == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Guía no encontrada.')),
      );
    }

    final entregada =
        guia.fechaCierre ??
        (guia.estado.esFinal ? guia.fechaActualizacion : null);

    return Scaffold(
      appBar: AppBar(title: Text('Guía ${guia.numeroGuia}')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              EstadoBadge(estado: guia.estado),
              const SizedBox(height: 16),
              _Tarjeta(
                filas: [
                  ('Cliente', guia.destinatario),
                  ('Destino', guia.destino),
                  ('Tipo de entrega', guia.tipoEntrega.etiqueta),
                  ('N° de pedido', guia.numeroPedido),
                  ('N° de entrega', guia.numeroEntrega),
                  ('Transportista', guia.transportista),
                  ('Salida', _fechaHora.format(guia.fechaCreacion.toLocal())),
                  (
                    'Entregada',
                    entregada == null
                        ? 'Pendiente'
                        : _fechaHora.format(entregada.toLocal()),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FotoEntrega(
                key: ValueKey('${guia.numeroGuia}|${guia.fotoEntregaUrl}'),
                guia: guia,
              ),
              const SizedBox(height: 24),
              SeccionUbicacion(
                guia: guia,
                perimetro: guia.tipoEntrega == TipoEntrega.entreSucursales
                    ? appState.sucursalPorNombre(guia.destino)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.filas});

  final List<(String, String)> filas;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Ipesa.radio),
        border: Border.all(color: Ipesa.borde),
      ),
      child: Column(
        children: [
          for (final (i, (etiqueta, valor)) in filas.indexed) ...[
            if (i > 0) const Divider(height: 1, color: Ipesa.segmento),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      etiqueta,
                      style: const TextStyle(
                        color: Ipesa.textoSuave,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      valor.isEmpty ? '—' : valor,
                      style: const TextStyle(color: Ipesa.texto),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
