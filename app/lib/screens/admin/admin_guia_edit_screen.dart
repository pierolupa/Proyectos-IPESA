import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../models/sucursal.dart';
import '../../models/tipo_entrega.dart';
import '../../services/guias_api.dart';
import '../../state/app_state.dart';
import '../../widgets/estado_badge.dart';
import '../../widgets/mapa_ubicacion.dart';

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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _guardarNumero(String actual) async {
    final nuevo = _numeroController.text.trim();
    setState(() => _guardandoNumero = true);
    try {
      await context.read<AppState>().corregirNumeroGuia(actual, nuevo);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Número corregido.')));
    } catch (e) {
      _numeroController.text = actual;
      _mostrarError(e);
    } finally {
      if (mounted) setState(() => _guardandoNumero = false);
    }
  }

  Future<void> _cambiarEstado(String numeroGuia, EstadoGuia nuevoEstado) async {
    setState(() => _guardandoEstado = true);
    try {
      await context.read<AppState>().actualizarEstado(
        numeroGuia,
        nuevoEstado,
        porAdmin: true,
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
          EstadoBadge(estado: guia.estado),
          const SizedBox(height: 24),
          Text(
            'Número de guía',
            style: Theme.of(context).textTheme.labelLarge,
          ),
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
                    _cambiarEstado(guia.numeroGuia, nuevoEstado);
                  },
          ),
          const SizedBox(height: 24),
          Text(
            'Destinatario: ${guia.destinatario}\n'
            'Origen: ${guia.origen}\n'
            'Destino: ${guia.destino}\n'
            'Transportista: ${guia.transportista}'
            '${guia.numeroPedido.isNotEmpty ? '\nN° de pedido: ${guia.numeroPedido}' : ''}'
            '${guia.numeroEntrega.isNotEmpty ? '\nN° de entrega: ${guia.numeroEntrega}' : ''}',
            style: TextStyle(color: Colors.grey[700]),
          ),
          const SizedBox(height: 24),
          _SeccionUbicacion(
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

class _SeccionUbicacion extends StatelessWidget {
  const _SeccionUbicacion({required this.guia, this.perimetro});

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
            '(círculo morado).',
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
    final tieneUltima = guia.ultimaLat != null && guia.ultimaLng != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          estaCerrada ? 'Dónde se cerró la tarea' : 'Última ubicación registrada',
          style: titulo,
        ),
        const SizedBox(height: 4),
        Text(
          estaCerrada
              ? 'Sin ubicación de cierre: la cerró un administrador a mano o '
                    'se cerró antes de que la app registrara el cierre.'
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
            color: Colors.blue,
            perimetro: perimetro,
          ),
        ],
      ],
    );
  }

  static String _coordenadas(double lat, double lng) =>
      '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
}
