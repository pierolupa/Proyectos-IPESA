import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/tipo_entrega.dart';
import '../../services/guias_api.dart';
import '../../services/ocr_service.dart';
import '../../state/app_state.dart';

/// Flujo de "Asignación" (ARCHITECTURE.md, sección 4.1): el transportista
/// fotografía la guía antes de salir y valida duplicados. El GPS debe estar
/// activo para poder subir la foto. La cámara, el GPS y el OCR (Tesseract.js,
/// ver ocr_service.dart) son reales; el patrón exacto del número de guía de
/// IPESA todavía no está definido, así que el número sugerido siempre queda
/// editable — ver ARCHITECTURE.md, sección 8, "Pendientes".
class CaptureFlowScreen extends StatefulWidget {
  const CaptureFlowScreen({super.key});

  @override
  State<CaptureFlowScreen> createState() => _CaptureFlowScreenState();
}

class _CaptureFlowScreenState extends State<CaptureFlowScreen> {
  bool _gpsActivo = false;
  bool _cargandoGps = false;
  bool _tomandoFoto = false;
  bool _leyendoOcr = false;
  Uint8List? _fotoBytes;
  String? _textoOcr;
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
  final _numeroPedidoController = TextEditingController();
  final _numeroEntregaController = TextEditingController();

  bool get _fotoSimulada => _fotoBytes != null;

  @override
  void dispose() {
    _numeroGuiaController.dispose();
    _destinatarioController.dispose();
    _destinoController.dispose();
    _numeroPedidoController.dispose();
    _numeroEntregaController.dispose();
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
      if (!mounted) return;
      setState(() {
        _fotoBytes = bytes;
        _textoOcr = null;
        _numeroGuiaController.clear();
        _numeroPedidoController.clear();
        _numeroEntregaController.clear();
      });
      await _leerDatosDeGuia(bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo abrir la cámara: $e')));
    } finally {
      if (mounted) setState(() => _tomandoFoto = false);
    }
  }

  Future<void> _leerDatosDeGuia(Uint8List bytes) async {
    setState(() => _leyendoOcr = true);
    try {
      final texto = await reconocerTexto(bytes);
      final datos = extraerDatosGuia(texto);
      if (!mounted) return;
      setState(() {
        _textoOcr = texto;
        if (datos.numeroGuia != null) {
          _numeroGuiaController.text = datos.numeroGuia!;
        }
        if (datos.destinatario != null) {
          _destinatarioController.text = datos.destinatario!;
        }
        if (datos.destino != null) {
          _destinoController.text = datos.destino!;
        }
        if (datos.numeroPedido != null) {
          _numeroPedidoController.text = datos.numeroPedido!;
        }
        if (datos.numeroEntrega != null) {
          _numeroEntregaController.text = datos.numeroEntrega!;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo leer los datos automáticamente: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _leyendoOcr = false);
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
        numeroPedido: _numeroPedidoController.text.trim(),
        numeroEntrega: _numeroEntregaController.text.trim(),
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
        !_leyendoOcr &&
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
            Text(
              'Número extraído por OCR',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _numeroGuiaController,
              enabled: !_leyendoOcr,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: _leyendoOcr
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.qr_code_2),
                helperText: _leyendoOcr
                    ? 'Leyendo el número de la foto...'
                    : 'Editable antes de confirmar, por si el OCR se equivocó.',
                errorText: esDuplicado
                    ? 'Este número ya está en ruta o registrado.'
                    : null,
              ),
            ),
            if (!_leyendoOcr &&
                numero.isEmpty &&
                (_textoOcr?.trim().isNotEmpty ?? false)) ...[
              const SizedBox(height: 8),
              Text(
                'No se encontró un número claro. Esto leyó la cámara — '
                'cópialo o escribe el número a mano:\n"${_textoOcr!.trim()}"',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
            const SizedBox(height: 12),
            TextField(
              controller: _numeroPedidoController,
              decoration: const InputDecoration(
                labelText: 'Número de pedido',
                helperText: 'De "Datos adicionales" — opcional.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _numeroEntregaController,
              decoration: const InputDecoration(
                labelText: 'Número de entrega',
                helperText: 'De "Datos adicionales" — opcional.',
              ),
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
