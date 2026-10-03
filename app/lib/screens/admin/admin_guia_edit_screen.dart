import 'package:flutter/material.dart';

import '../../theme.dart';

import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../models/tipo_entrega.dart';
import '../../services/guias_api.dart';
import '../../state/app_state.dart';
import '../../widgets/acciones_tarea.dart';
import '../../widgets/aviso_rechazo.dart';
import '../../widgets/estado_badge.dart';
import '../../widgets/foto_entrega.dart';
import '../../widgets/seccion_ubicacion.dart';

/// Corrección manual de datos (ARCHITECTURE.md, sección 6): el
/// administrador tiene acceso total para cambiar el estado de cualquier
/// tarea y corregir el número de guía cuando el OCR falló.
class AdminGuiaEditScreen extends StatefulWidget {
  const AdminGuiaEditScreen({super.key, required this.numeroGuia});

  final String numeroGuia;

  @override
  State<AdminGuiaEditScreen> createState() => _AdminGuiaEditScreenState();
}

class _AdminGuiaEditScreenState extends State<AdminGuiaEditScreen> {
  late final TextEditingController _numeroController;
  bool _guardandoNumero = false;
  bool _guardandoEstado = false;

  @override
  void initState() {
    super.initState();
    _numeroController = TextEditingController(text: widget.numeroGuia);
  }

  @override
  void dispose() {
    _numeroController.dispose();
    super.dispose();
  }

  void _mostrarError(Object e) {
    if (!mounted) return;
    final mensaje = e is ApiException ? e.mensaje : 'Error de conexión: $e';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _guardarNumero(String actual) async {
    final nuevo = _numeroController.text.trim();
    setState(() => _guardandoNumero = true);
    try {
      await context.read<AppState>().corregirNumeroGuia(actual, nuevo);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Número corregido.')));
    } catch (e) {
      _numeroController.text = actual;
      _mostrarError(e);
    } finally {
      if (mounted) setState(() => _guardandoNumero = false);
    }
  }

  Future<void> _cambiarEstado(Guia guia, EstadoGuia nuevoEstado) async {
    setState(() => _guardandoEstado = true);
    try {
      await context.read<AppState>().actualizarEstado(
        guia.numeroGuia,
        nuevoEstado,
        porAdmin: true,
        fechaCreacion: guia.fechaCreacion,
      );
    } catch (e) {
      _mostrarError(e);
    } finally {
      if (mounted) setState(() => _guardandoEstado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final guia = appState.buscarPorNumero(widget.numeroGuia);

    if (guia == null) {
      return const Scaffold(body: Center(child: Text('Guía no encontrada.')));
    }

    return Scaffold(
      appBar: AppBar(title: Text('Editar · ${guia.numeroGuia}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (guia.eliminacionPendiente) ...[
            SolicitudEliminacionAdmin(
              guia: guia,
              onEliminada: () {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.of(context).pop();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'Tarea ${guia.numeroGuia} eliminada de la base de datos.',
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
          ],
          EstadoBadge(estado: guia.estado),
          const SizedBox(height: 24),
          Text('Número de guía', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _numeroController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    helperText:
                        'Corrección manual cuando el OCR no leyó bien la guía.',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed:
                    _guardandoNumero ||
                        _numeroController.text.trim() == guia.numeroGuia
                    ? null
                    : () => _guardarNumero(guia.numeroGuia),
                child: _guardandoNumero
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Estado', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          DropdownButtonFormField<EstadoGuia>(
            initialValue: guia.estado,
            decoration: const InputDecoration(),
            items: [
              for (final estado in EstadoGuia.values)
                DropdownMenuItem(value: estado, child: Text(estado.etiqueta)),
            ],
            onChanged: _guardandoEstado
                ? null
                : (nuevoEstado) {
                    if (nuevoEstado == null) return;
                    _cambiarEstado(guia, nuevoEstado);
                  },
          ),
          const SizedBox(height: 24),
          Text(
            'Tipo de entrega',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: Text(guia.tipoEntrega.etiqueta)),
              TextButton(
                onPressed: () =>
                    mostrarCambioTipo(context, guia, porAdmin: true),
                child: const Text('Cambiar'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Destinatario: ${guia.destinatario}\n'
            'Punto de partida: ${guia.origen}\n'
            'Destino: ${guia.destino}\n'
            'Transportista: ${guia.transportista}'
            '${guia.resumenTransbordo.isNotEmpty ? '\n${guia.resumenTransbordo}' : ''}'
            '${guia.numeroPedido.isNotEmpty ? '\nN° de pedido: ${guia.numeroPedido}' : ''}'
            '${guia.numeroEntrega.isNotEmpty ? '\nN° de entrega: ${guia.numeroEntrega}' : ''}',
            style: TextStyle(color: Colors.grey[700]),
          ),
          if (guia.tieneComprobanteAgencia) ...[
            const SizedBox(height: 16),
            Text('Comprobante de agencia', style: Ipesa.titulo(15)),
            const SizedBox(height: 4),
            Text(
              [
                if (guia.agenciaRazonSocial.isNotEmpty)
                  'Razón social: ${guia.agenciaRazonSocial}',
                if (guia.agenciaComprobante.isNotEmpty)
                  'N° de comprobante: ${guia.agenciaComprobante}',
                if (guia.agenciaRuc.isNotEmpty) 'RUC: ${guia.agenciaRuc}',
                if (guia.agenciaMonto case final m?)
                  'Monto pagado: S/ ${m.toStringAsFixed(2)}',
              ].join('\n'),
              style: TextStyle(color: Colors.grey[700]),
            ),
          ],
          if (guia.estado == EstadoGuia.rechazado) ...[
            const SizedBox(height: 24),
            AvisoRechazo(guia: guia),
          ],
          const SizedBox(height: 24),
          FotoEntrega(
            key: ValueKey('${guia.numeroGuia}|${guia.fotoEntregaUrl}'),
            guia: guia,
          ),
          BotonEliminarFoto(guia: guia),
          const SizedBox(height: 24),
          SeccionUbicacion(
            guia: guia,
            perimetro: guia.tipoEntrega == TipoEntrega.entreSucursales
                ? appState.sucursalPorNombre(guia.destino)
                : null,
          ),
        ],
      ),
    );
  }
}
