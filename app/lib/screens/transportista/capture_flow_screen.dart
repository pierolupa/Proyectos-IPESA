import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/tipo_entrega.dart';
import '../../services/guias_api.dart';
import '../../state/app_state.dart';

/// Flujo de "Asignación" (ARCHITECTURE.md, sección 4.1): el transportista
/// fotografía la guía antes de salir y valida duplicados. El GPS debe estar
/// activo para poder subir la foto. La cámara y el GPS son reales (piden
/// permiso al dispositivo); el OCR del número de guía sigue simulado — ver
/// ARCHITECTURE.md, sección 8, "Pendientes".
class CaptureFlowScreen extends StatefulWidget {
  const CaptureFlowScreen({super.key});

  @override
  State<CaptureFlowScreen> createState() => _CaptureFlowScreenState();
}

class _CaptureFlowScreenState extends State<CaptureFlowScreen> {
  bool _gpsActivo = false;
  bool _cargandoGps = false;
  bool _tomandoFoto = false;
  Uint8List? _fotoBytes;
  bool _enviando = false;
  double? _lat;
  double? _lng;
  final _picker = ImagePicker();
  TipoEntrega _tipoEntrega = TipoEntrega.clienteFinal;
  final _numeroGuiaController = TextEditingController();
  final _destinatarioController = TextEditingController(text: 'Cliente Demo');
  final _destinoController = TextEditingController(
    text: 'Av. Principal 123, Lima',
  );

  bool get _fotoSimulada => _fotoBytes != null;

  @override
  void dispose() {
    _numeroGuiaController.dispose();
    _destinatarioController.dispose();
    _destinoController.dispose();
    super.dispose();
  }

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
      // El OCR real todavía no está integrado: se genera un número de
      // ejemplo editable a mano en vez de leerlo de la foto.
      final aleatorio = Random().nextInt(9000) + 1000;
      if (!mounted) return;
      setState(() {
        _fotoBytes = bytes;
        _numeroGuiaController.text = 'IPE-2026-$aleatorio';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo abrir la cámara: $e')));
    } finally {
      if (mounted) setState(() => _tomandoFoto = false);
    }
  }

  Future<void> _confirmar(String numero) async {
    setState(() => _enviando = true);
    try {
      await context.read<AppState>().asignarNuevaGuia(
        numeroGuia: numero,
        tipoEntrega: _tipoEntrega,
        origen: 'Almacén Callao',
        destino: _destinoController.text.trim(),
        destinatario: _destinatarioController.text.trim(),
        lat: _lat!,
        lng: _lng!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Guía $numero asignada · estado: en ruta')),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error de conexión: $e')));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final numero = _numeroGuiaController.text.trim();
    final esDuplicado = numero.isNotEmpty && appState.esDuplicado(numero);
    final puedeConfirmar =
        !_enviando &&
        _gpsActivo &&
        _fotoSimulada &&
        numero.isNotEmpty &&
        !esDuplicado &&
        _destinatarioController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva guía · Asignación')),
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
                    ? 'Ubicación disponible: se adjuntará a la foto.'
                    : 'Obligatorio: sin GPS no se puede subir ningún registro fotográfico.',
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
          OutlinedButton.icon(
            onPressed: _gpsActivo && !_tomandoFoto ? _tomarFoto : null,
            icon: _tomandoFoto
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.camera_alt),
            label: Text(
              _fotoSimulada ? 'Volver a tomar foto' : 'Tomar foto de la guía',
            ),
          ),
          if (!_gpsActivo)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Activa el GPS para habilitar la cámara.',
                style: TextStyle(color: Colors.red, fontSize: 12),
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
            Text(
              'Número extraído por OCR',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _numeroGuiaController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.qr_code_2),
                helperText:
                    'Editable antes de confirmar, por si el OCR se equivocó.',
                errorText: esDuplicado
                    ? 'Este número ya está en ruta o registrado.'
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<TipoEntrega>(
              initialValue: _tipoEntrega,
              decoration: const InputDecoration(labelText: 'Tipo de entrega'),
              items: [
                for (final tipo in TipoEntrega.values)
                  DropdownMenuItem(value: tipo, child: Text(tipo.etiqueta)),
              ],
              onChanged: (tipo) {
                if (tipo != null) setState(() => _tipoEntrega = tipo);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _destinatarioController,
              decoration: const InputDecoration(labelText: 'Destinatario'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _destinoController,
              decoration: const InputDecoration(labelText: 'Destino'),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: puedeConfirmar ? () => _confirmar(numero) : null,
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
            label: Text(_enviando ? 'Enviando...' : 'Confirmar asignación'),
          ),
        ],
      ),
    );
  }
}
