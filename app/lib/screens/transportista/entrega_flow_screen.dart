import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../models/tipo_entrega.dart';
import '../../services/guias_api.dart';
import '../../state/app_state.dart';

/// Flujo de "Entrega" y "Entrega entre sucursales" (ARCHITECTURE.md,
/// sección 4.2 y 4.3). El paso concreto depende del tipo de entrega y del
/// estado actual de la guía; el GPS sigue siendo obligatorio. La cámara y
/// el GPS son reales (piden permiso al dispositivo).
class EntregaFlowScreen extends StatefulWidget {
  const EntregaFlowScreen({super.key, required this.guia});

  final Guia guia;

  @override
  State<EntregaFlowScreen> createState() => _EntregaFlowScreenState();
}

class _EntregaFlowScreenState extends State<EntregaFlowScreen> {
  bool _gpsActivo = false;
  bool _cargandoGps = false;
  bool _tomandoFoto = false;
  Uint8List? _fotoBytes;
  bool _firmaCapturada = false;
  bool _comprobanteAdjunto = false;
  bool _dentroDeGeocerca = false;
  bool _enviando = false;
  double? _lat;
  double? _lng;
  final _picker = ImagePicker();

  bool get _fotoSimulada => _fotoBytes != null;

  Future<void> _activarGps() async {
    setState(() => _cargandoGps = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'La ubicación está desactivada en tu dispositivo.';
      }
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        throw 'Debes dar permiso de ubicación para continuar.';
      }
      final posicion = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _gpsActivo = true;
        _lat = posicion.latitude;
        _lng = posicion.longitude;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo activar el GPS: $e')));
    } finally {
      if (mounted) setState(() => _cargandoGps = false);
    }
  }

  void _desactivarGps() {
    setState(() {
      _gpsActivo = false;
      _lat = null;
      _lng = null;
    });
  }

  Future<void> _tomarFoto() async {
    setState(() => _tomandoFoto = true);
    try {
      final archivo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (archivo == null) return;
      final bytes = await archivo.readAsBytes();
      if (!mounted) return;
      setState(() => _fotoBytes = bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo abrir la cámara: $e')));
    } finally {
      if (mounted) setState(() => _tomandoFoto = false);
    }
  }

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

  Future<void> _confirmar(BuildContext context) async {
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

    setState(() => _enviando = true);
    try {
      await appState.actualizarEstado(
        g.numeroGuia,
        nuevoEstado,
        lat: _lat,
        lng: _lng,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensaje)));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error de conexión: $e')));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
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
              onChanged: _cargandoGps
                  ? null
                  : (v) => v ? _activarGps() : _desactivarGps(),
              title: const Text('GPS activo'),
              subtitle: Text(
                _cargandoGps
                    ? 'Solicitando ubicación a tu dispositivo...'
                    : _gpsActivo
                    ? 'Ubicación disponible.'
                    : 'Obligatorio para registrar cualquier evento de esta guía.',
              ),
              secondary: _cargandoGps
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
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
              onPressed: _gpsActivo && _requiereFoto && !_tomandoFoto
                  ? _tomarFoto
                  : null,
              icon: _tomandoFoto
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt),
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_fotoBytes!, fit: BoxFit.cover),
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
            onPressed: _puedeConfirmar && !_enviando
                ? () => _confirmar(context)
                : null,
            icon: _enviando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle),
            label: Text(_enviando ? 'Enviando...' : 'Confirmar'),
          ),
        ],
      ),
    );
  }
}
