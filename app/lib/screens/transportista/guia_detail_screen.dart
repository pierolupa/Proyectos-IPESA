import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/tipo_entrega.dart';
import '../../state/app_state.dart';
import '../../widgets/acciones_tarea.dart';
import '../../widgets/aviso_rechazo.dart';
import '../../widgets/estado_badge.dart';
import 'entrega_flow_screen.dart';
import 'rechazo_sheet.dart';

class GuiaDetailScreen extends StatelessWidget {
  const GuiaDetailScreen({super.key, required this.numeroGuia});

  final String numeroGuia;

  String? _tituloSiguientePaso(EstadoGuia estado, TipoEntrega tipo) {
    if (estado.esCerrada) return null;
    if (tipo == TipoEntrega.entreSucursales) {
      if (estado == EstadoGuia.enRuta) return 'Iniciar traslado';
      if (estado == EstadoGuia.enProcesoTrasbordo) {
        return 'Registrar llegada (geocerca)';
      }
      return 'Confirmar recepción';
    }
    return tipo == TipoEntrega.agencia
        ? 'Registrar entrega en agencia'
        : 'Registrar entrega a cliente';
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final guia = appState.buscarPorNumero(numeroGuia);

    if (guia == null) {
      return const Scaffold(body: Center(child: Text('Guía no encontrada.')));
    }

    final siguientePaso = _tituloSiguientePaso(guia.estado, guia.tipoEntrega);

    return Scaffold(
      appBar: AppBar(title: Text(guia.numeroGuia)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              EstadoBadge(estado: guia.estado),
              const SizedBox(width: 8),
              if (guia.corregidoPorAdmin)
                const Chip(
                  label: Text('Corregido por admin'),
                  avatar: Icon(Icons.edit, size: 16),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _DetailRow(
            label: 'Tipo de entrega',
            value: guia.tipoEntrega.etiqueta,
            accion: guia.esEditablePorTransportista
                ? TextButton(
                    onPressed: () async {
                      final ok = await mostrarCambioTipo(context, guia);
                      if (ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Tipo de entrega actualizado.'),
                          ),
                        );
                      }
                    },
                    child: const Text('Cambiar'),
                  )
                : null,
          ),
          _DetailRow(label: 'Destinatario', value: guia.destinatario),
          _DetailRow(label: 'Punto de partida', value: guia.origen),
          _DetailRow(label: 'Destino', value: guia.destino),
          _DetailRow(label: 'Transportista', value: guia.transportista),
          if (guia.numeroPedido.isNotEmpty)
            _DetailRow(label: 'N° de pedido', value: guia.numeroPedido),
          if (guia.numeroEntrega.isNotEmpty)
            _DetailRow(label: 'N° de entrega', value: guia.numeroEntrega),
          _DetailRow(
            label: 'Última actualización',
            value: guia.fechaActualizacion.toString().substring(0, 16),
          ),
          const SizedBox(height: 24),
          if (guia.eliminacionPendiente || guia.eliminacionRechazada) ...[
            AvisoEliminacion(guia: guia),
            const SizedBox(height: 16),
          ],
          if (siguientePaso != null) ...[
            FilledButton.icon(
              icon: const Icon(Icons.arrow_forward),
              label: Text(siguientePaso),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EntregaFlowScreen(guia: guia),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.block),
              label: const Text('Rechazar tarea'),
              style: OutlinedButton.styleFrom(
                foregroundColor: EstadoGuia.rechazado.color,
                side: BorderSide(color: EstadoGuia.rechazado.color),
              ),
              onPressed: () async {
                final rechazada = await mostrarRechazo(context, guia);
                if (!rechazada || !context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Guía ${guia.numeroGuia} rechazada. '
                      'Se avisó al administrador.',
                    ),
                  ),
                );
                // Vuelve a "Mis tareas", donde ya no aparece.
                Navigator.of(context).pop();
              },
            ),
            // Borrar la tarea (por ejemplo, si se registró por error):
            // solo en ruta y con la aprobación del administrador.
            if (guia.esEditablePorTransportista &&
                !guia.eliminacionPendiente) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Eliminar tarea'),
                style: TextButton.styleFrom(
                  foregroundColor: EstadoGuia.rechazado.color,
                ),
                onPressed: () async {
                  final enviado = await mostrarPedidoEliminacion(context, guia);
                  if (!enviado || !context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Pedido enviado. El administrador debe aprobarlo.',
                      ),
                    ),
                  );
                },
              ),
            ],
          ] else if (guia.estado == EstadoGuia.rechazado)
            AvisoRechazo(guia: guia)
          else
            const Card(
              color: Color(0xFFE8F5E9),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 12),
                    Expanded(child: Text('Esta guía ya completó su ciclo.')),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.accion});

  final String label;
  final String value;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
          ?accion,
        ],
      ),
    );
  }
}
