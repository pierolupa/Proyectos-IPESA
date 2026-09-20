import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../models/tipo_entrega.dart';
import '../../state/app_state.dart';

/// Flujo de "Entrega" y "Entrega entre sucursales" (ARCHITECTURE.md,
/// sección 4.2 y 4.3). El paso concreto depende del tipo de entrega y del
/// estado actual de la guía; el GPS sigue siendo obligatorio.
class EntregaFlowScreen extends StatefulWidget {
  const EntregaFlowScreen({super.key, required this.guia});

  final Guia guia;

  @override
  State<EntregaFlowScreen> createState() => _EntregaFlowScreenState();
}

class _EntregaFlowScreenState extends State<EntregaFlowScreen> {
  bool _gpsActivo = false;
  bool _fotoSimulada = false;
  bool _firmaCapturada = false;
  bool _comprobanteAdjunto = false;
  bool _dentroDeGeocerca = false;

  String get _tituloAccion {
    final g = widget.guia;
    if (g.tipoEntrega == TipoEntrega.entreSucursales) {
      if (g.estado == EstadoGuia.enRuta) return 'Iniciar traslado a sucursal';
      if (g.estado == EstadoGuia.enProcesoTrasbordo) {
        return 'Registrar llegada a sucursal';
      }
      return 'Confirmar recepción en sucursal';
    }
    return g.tipoEntrega == TipoEntrega.agencia
        ? 'Registrar entrega en agencia'
        : 'Registrar entrega a cliente final';
  }

  bool get _requiereFoto =>
      widget.guia.tipoEntrega != TipoEntrega.entreSucursales ||
      widget.guia.estado == EstadoGuia.enRuta;

  bool get _puedeConfirmar {
    if (!_gpsActivo) return false;
    final g = widget.guia;
    if (g.tipoEntrega == TipoEntrega.entreSucursales) {
      if (g.estado == EstadoGuia.enProcesoTrasbordo) return _dentroDeGeocerca;
      return _fotoSimulada;
    }
    if (!_fotoSimulada) return false;
    return g.tipoEntrega == TipoEntrega.agencia
        ? _comprobanteAdjunto
        : _firmaCapturada;
  }

  void _confirmar(BuildContext context) {
    final appState = context.read<AppState>();
    final g = widget.guia;
    EstadoGuia nuevoEstado;
    String mensaje;

    if (g.tipoEntrega == TipoEntrega.entreSucursales) {
      if (g.estado == EstadoGuia.enRuta) {
        nuevoEstado = EstadoGuia.enProcesoTrasbordo;
        mensaje = 'Traslado iniciado hacia ${g.destino}.';
      } else if (g.estado == EstadoGuia.enProcesoTrasbordo) {
        nuevoEstado = EstadoGuia.recepcionSucursal;
        mensaje = 'Geocerca detectó la llegada a ${g.destino}.';
      } else {
        nuevoEstado = EstadoGuia.entregado;
        mensaje = 'Recepción en sucursal confirmada.';
      }
    } else if (g.tipoEntrega == TipoEntrega.agencia) {
      nuevoEstado = EstadoGuia.finalizado;
      mensaje = 'Entrega en agencia registrada con comprobante.';
    } else {
      nuevoEstado = EstadoGuia.entregado;
      mensaje = 'Entrega a cliente final registrada con firma.';
    }

    appState.actualizarEstado(g.numeroGuia, nuevoEstado);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.guia;
    final esPasoGeocerca =
        g.tipoEntrega == TipoEntrega.entreSucursales &&
        g.estado == EstadoGuia.enProcesoTrasbordo;

    return Scaffold(
      appBar: AppBar(title: Text(_tituloAccion)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: _gpsActivo ? Colors.green[50] : Colors.red[50],
            child: SwitchListTile(
              value: _gpsActivo,
              onChanged: (v) => setState(() => _gpsActivo = v),
              title: const Text('GPS activo'),
              subtitle: Text(
                _gpsActivo
                    ? 'Ubicación disponible.'
                    : 'Obligatorio para registrar cualquier evento de esta guía.',
              ),
              secondary: Icon(
                _gpsActivo ? Icons.gps_fixed : Icons.gps_off,
                color: _gpsActivo ? Colors.green : Colors.red,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (esPasoGeocerca) ...[
            Card(
              color: _dentroDeGeocerca ? Colors.purple[50] : null,
              child: SwitchListTile(
                value: _dentroDeGeocerca,
                onChanged: _gpsActivo
                    ? (v) => setState(() => _dentroDeGeocerca = v)
                    : null,
                title: const Text('Dentro del área de la sucursal'),
                subtitle: Text(
                  'Simula el geofencing de ${g.destino}: al entrar al radio '
                  'designado, el estado cambia automáticamente.',
                ),
                secondary: const Icon(Icons.location_on, color: Colors.purple),
              ),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: _gpsActivo && _requiereFoto
                  ? () => setState(() => _fotoSimulada = true)
                  : null,
              icon: const Icon(Icons.camera_alt),
              label: Text(
                _fotoSimulada
                    ? 'Foto de la guía firmada capturada'
                    : 'Tomar foto de la guía firmada',
              ),
            ),
            if (_fotoSimulada) ...[
              const SizedBox(height: 16),
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.fact_check,
                      size: 64,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (g.tipoEntrega == TipoEntrega.agencia)
                CheckboxListTile(
                  value: _comprobanteAdjunto,
                  onChanged: (v) =>
                      setState(() => _comprobanteAdjunto = v ?? false),
                  title: const Text('Comprobante de agencia adjunto'),
                )
              else if (g.tipoEntrega == TipoEntrega.clienteFinal)
                CheckboxListTile(
                  value: _firmaCapturada,
                  onChanged: (v) =>
                      setState(() => _firmaCapturada = v ?? false),
                  title: const Text('Firma del cliente capturada'),
                ),
            ],
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _puedeConfirmar ? () => _confirmar(context) : null,
            icon: const Icon(Icons.check_circle),
            label: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }
}
