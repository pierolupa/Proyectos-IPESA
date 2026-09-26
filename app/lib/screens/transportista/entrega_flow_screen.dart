import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../models/sucursal.dart';
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
  bool _verificandoPerimetro = false;
  String? _resultadoPerimetro;
  bool _enviando = false;
  double? _lat;
  double? _lng;
  final _picker = ImagePicker();

  bool get _fotoSimulada => _fotoBytes != null;

  Future<Position> _leerPosicion() async {
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
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _activarGps() async {
    setState(() => _cargandoGps = true);
    try {
      final posicion = await _leerPosicion();
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

  Future<void> _verificarPerimetro(Sucursal sucursal) async {
    setState(() => _verificandoPerimetro = true);
    try {
      final posicion = await _leerPosicion();
      final distancia = Geolocator.distanceBetween(
        posicion.latitude,
        posicion.longitude,
        sucursal.lat,
        sucursal.lng,
      );
      if (!mounted) return;
      final dentro = distancia <= sucursal.radioM;
      setState(() {
        _lat = posicion.latitude;
        _lng = posicion.longitude;
        _dentroDeGeocerca = dentro;
        _resultadoPerimetro = dentro
            ? 'Estás dentro del perímetro de ${sucursal.nombre}.'
            : 'Estás a ${distancia.round()} m de ${sucursal.nombre}; '
                  'acércate a menos de ${sucursal.radioM.round()} m.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dentroDeGeocerca = false;
        _resultadoPerimetro = 'No se pudo leer tu ubicación: $e';
      });
    } finally {
      if (mounted) setState(() => _verificandoPerimetro = false);
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
        mensaje = 'Llegada a ${g.destino} registrada dentro del perímetro.';
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
      // Se vuelve a leer el GPS al confirmar para registrar dónde se marcó
      // realmente, no dónde se encendió el GPS.
      final Position posicion;
      try {
        posicion = await _leerPosicion();
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo leer tu ubicación: $e')),
        );
        return;
      }
      _lat = posicion.latitude;
      _lng = posicion.longitude;
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
      // Entregada: vuelve directo a "Mis tareas" (cierra también el detalle),
      // donde la guía ya no aparece.
      final navigator = Navigator.of(context)..pop();
      if (nuevoEstado.esFinal) navigator.pop();
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
    final sucursal = context.watch<AppState>().sucursalPorNombre(g.destino);

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
            _TarjetaPerimetro(
              sucursal: sucursal,
              destino: g.destino,
              gpsActivo: _gpsActivo,
              verificando: _verificandoPerimetro,
              dentro: _dentroDeGeocerca,
              resultado: _resultadoPerimetro,
              onVerificar: sucursal == null
                  ? null
                  : () => _verificarPerimetro(sucursal),
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
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: Image.memory(
                    _fotoBytes!,
                    fit: BoxFit.contain,
                    width: double.infinity,
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

class _TarjetaPerimetro extends StatelessWidget {
  const _TarjetaPerimetro({
    required this.sucursal,
    required this.destino,
    required this.gpsActivo,
    required this.verificando,
    required this.dentro,
    required this.resultado,
    required this.onVerificar,
  });

  final Sucursal? sucursal;
  final String destino;
  final bool gpsActivo;
  final bool verificando;
  final bool dentro;
  final String? resultado;
  final VoidCallback? onVerificar;

  @override
  Widget build(BuildContext context) {
    if (sucursal == null) {
      return Card(
        color: Colors.red[50],
        child: ListTile(
          leading: const Icon(Icons.location_off, color: Colors.red),
          title: Text('$destino no tiene perímetro'),
          subtitle: const Text(
            'Pide al administrador que marque la sucursal en el mapa para '
            'poder registrar la llegada.',
          ),
        ),
      );
    }
    return Card(
      color: dentro ? Colors.purple[50] : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.purple),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Llegada a ${sucursal!.nombre} '
                    '(perímetro de ${sucursal!.radioM.round()} m)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: gpsActivo && !verificando ? onVerificar : null,
              icon: verificando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: const Text('Verificar que estoy en la sucursal'),
            ),
            if (resultado != null) ...[
              const SizedBox(height: 8),
              Text(
                resultado!,
                style: TextStyle(color: dentro ? Colors.green[800] : Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
