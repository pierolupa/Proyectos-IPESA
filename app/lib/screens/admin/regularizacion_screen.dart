import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../services/guias_api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';

/// Regularización: sube una entrega que un transportista de la lista no
/// registró. Dos pasos, en orden: la foto de la guía (la IA llena los datos)
/// y la foto de la entrega. Sin GPS ni otras restricciones: la guía queda
/// como entregada a nombre del transportista elegido.
/// Opción fija para entregas hechas por un taxi externo (no es un usuario).
const _taxiExterno = 'Taxi externo';

class RegularizacionScreen extends StatefulWidget {
  const RegularizacionScreen({super.key});

  @override
  State<RegularizacionScreen> createState() => _RegularizacionScreenState();
}

class _RegularizacionScreenState extends State<RegularizacionScreen> {
  final _picker = ImagePicker();
  final _guia = TextEditingController();
  final _origen = TextEditingController();
  final _destino = TextEditingController();
  final _destinatario = TextEditingController();
  final _pedido = TextEditingController();
  final _entrega = TextEditingController();

  List<String>? _transportistas;
  String? _transportista;
  Uint8List? _fotoGuia;
  Uint8List? _fotoEntrega;
  bool _leyendo = false;
  bool _enviando = false;
  String? _aviso;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarTransportistas();
  }

  @override
  void dispose() {
    for (final c in [
      _guia,
      _origen,
      _destino,
      _destinatario,
      _pedido,
      _entrega,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarTransportistas() async {
    try {
      final lista = await context.read<AppState>().listarTransportistas();
      // Un taxi que no es de la lista de transportistas.
      if (mounted) {
        setState(() => _transportistas = [...lista, _taxiExterno]);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo cargar la lista: $e');
    }
  }

  /// Toma la foto con la cámara o la elige de la galería.
  Future<Uint8List?> _foto(ImageSource origen) async {
    final archivo = await _picker.pickImage(
      source: origen,
      maxWidth: 1600,
      imageQuality: 90,
    );
    return archivo?.readAsBytes();
  }

  Future<void> _elegirFotoGuia(ImageSource origen) async {
    final bytes = await _foto(origen);
    if (bytes == null || !mounted) return;
    setState(() {
      _fotoGuia = bytes;
      _leyendo = true;
      _aviso = null;
      _error = null;
    });
    try {
      final datos = await context.read<AppState>().leerGuiaConIA(bytes);
      if (!mounted) return;
      setState(() {
        _guia.text = datos.numeroGuia ?? '';
        _origen.text = datos.origen ?? '';
        _destino.text = datos.destino ?? '';
        _destinatario.text = datos.destinatario ?? '';
        _pedido.text = datos.numeroPedido ?? '';
        _entrega.text = datos.numeroEntrega ?? '';
        _aviso = 'Revisa los datos que leyó la IA antes de guardar.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _aviso = 'No se pudo leer la foto: completa los datos a mano.',
        );
      }
    } finally {
      if (mounted) setState(() => _leyendo = false);
    }
  }

  Future<void> _elegirFotoEntrega(ImageSource origen) async {
    final bytes = await _foto(origen);
    if (bytes == null || !mounted) return;
    setState(() => _fotoEntrega = bytes);
  }

  bool get _listo =>
      _transportista != null &&
      _guia.text.trim().isNotEmpty &&
      _origen.text.trim().isNotEmpty &&
      _destino.text.trim().isNotEmpty &&
      _destinatario.text.trim().isNotEmpty &&
      _fotoGuia != null &&
      _fotoEntrega != null &&
      !_enviando;

  Future<void> _regularizar() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final (guia, aviso) = await context.read<AppState>().regularizarGuia(
        transportista: _transportista!,
        numeroGuia: _guia.text.trim(),
        origen: _origen.text.trim(),
        destino: _destino.text.trim(),
        destinatario: _destinatario.text.trim(),
        numeroPedido: _pedido.text.trim(),
        numeroEntrega: _entrega.text.trim(),
        foto: _fotoEntrega!,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Guía ${guia.numeroGuia} regularizada a nombre de '
            '$_transportista.${aviso == null ? '' : ' $aviso'}',
          ),
        ),
      );
      // Lista para la siguiente entrega; el transportista se queda elegido.
      setState(() {
        for (final c in [
          _guia,
          _origen,
          _destino,
          _destinatario,
          _pedido,
          _entrega,
        ]) {
          c.clear();
        }
        _fotoGuia = null;
        _fotoEntrega = null;
        _aviso = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (e) {
      if (mounted) setState(() => _error = 'Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ipesa.fondo,
      appBar: AppBar(title: const Text('Regularización')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Para una entrega que el transportista no registró. Primero '
                  'la foto de la guía (la IA llena los datos) y luego la foto '
                  'de la entrega. No pide ubicación.',
                  style: TextStyle(fontSize: 15, color: Ipesa.textoSuave),
                ),
                const SizedBox(height: 16),
                _tarjeta(
                  titulo: 'Transportista',
                  hijo: _selectorTransportista(),
                ),
                const SizedBox(height: 12),
                _tarjeta(titulo: '1 · Foto de la guía', hijo: _pasoGuia()),
                const SizedBox(height: 12),
                _tarjeta(
                  titulo: '2 · Foto de la entrega',
                  hijo: _pasoEntrega(),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _listo ? _regularizar : null,
                  icon: _enviando
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text(_enviando ? 'Guardando…' : 'Regularizar entrega'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tarjeta({required String titulo, required Widget hijo}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titulo, style: Ipesa.titulo(16)),
            const SizedBox(height: 12),
            hijo,
          ],
        ),
      ),
    );
  }

  Widget _selectorTransportista() {
    final lista = _transportistas;
    if (lista == null) {
      return const LinearProgressIndicator(minHeight: 3);
    }
    return DropdownButtonFormField<String>(
      initialValue: _transportista,
      decoration: const InputDecoration(labelText: 'Transportista'),
      items: [
        for (final nombre in lista)
          DropdownMenuItem(value: nombre, child: Text(nombre)),
      ],
      onChanged: _enviando ? null : (v) => setState(() => _transportista = v),
    );
  }

  Widget _pasoGuia() {
    final ocupado = _leyendo || _enviando;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _botonesFoto(
          ocupado: ocupado,
          tieneFoto: _fotoGuia != null,
          alTomar: _elegirFotoGuia,
        ),
        if (_fotoGuia != null) ...[
          const SizedBox(height: 10),
          _miniatura(_fotoGuia!),
        ],
        if (_leyendo) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(minHeight: 3),
        ],
        if (_aviso != null) ...[
          const SizedBox(height: 10),
          Text(_aviso!, style: const TextStyle(color: Ipesa.textoSuave)),
        ],
        const SizedBox(height: 12),
        _campo(_guia, 'N° de guía', ocupado),
        _campo(_origen, 'Origen (dónde se recogió)', ocupado),
        _campo(_destino, 'Destino (dónde se entregó)', ocupado),
        _campo(_destinatario, 'Cliente', ocupado),
        _campo(_pedido, 'N° pedido', ocupado),
        _campo(_entrega, 'N° entrega', ocupado),
      ],
    );
  }

  Widget _pasoEntrega() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _botonesFoto(
          ocupado: _enviando,
          tieneFoto: _fotoEntrega != null,
          alTomar: _elegirFotoEntrega,
        ),
        if (_fotoEntrega != null) ...[
          const SizedBox(height: 10),
          _miniatura(_fotoEntrega!),
        ],
      ],
    );
  }

  Widget _botonesFoto({
    required bool ocupado,
    required bool tieneFoto,
    required Future<void> Function(ImageSource) alTomar,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: ocupado ? null : () => alTomar(ImageSource.camera),
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(tieneFoto ? 'Tomar otra foto' : 'Tomar foto'),
        ),
        OutlinedButton.icon(
          onPressed: ocupado ? null : () => alTomar(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Elegir de galería'),
        ),
      ],
    );
  }

  Widget _miniatura(Uint8List bytes) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Ipesa.radioCampo),
      child: Image.memory(bytes, height: 160, fit: BoxFit.cover),
    );
  }

  Widget _campo(TextEditingController c, String etiqueta, bool deshabilitado) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        enabled: !deshabilitado,
        decoration: InputDecoration(labelText: etiqueta),
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}
