import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/tipo_entrega.dart';
import '../../services/guias_api.dart';
import '../../state/app_state.dart';

/// Flujo de "Asignación" (ARCHITECTURE.md, sección 4.1): el transportista
/// fotografía la guía antes de salir, el sistema simula el OCR del número
/// y valida duplicados. El GPS debe estar activo para poder subir la foto.
class CaptureFlowScreen extends StatefulWidget {
  const CaptureFlowScreen({super.key});

  @override
  State<CaptureFlowScreen> createState() => _CaptureFlowScreenState();
}

class _CaptureFlowScreenState extends State<CaptureFlowScreen> {
  bool _gpsActivo = false;
  bool _fotoSimulada = false;
  bool _enviando = false;
  double? _lat;
  double? _lng;
  TipoEntrega _tipoEntrega = TipoEntrega.clienteFinal;
  final _numeroGuiaController = TextEditingController();
  final _destinatarioController = TextEditingController(text: 'Cliente Demo');
  final _destinoController = TextEditingController(
    text: 'Av. Principal 123, Lima',
  );

  @override
  void dispose() {
    _numeroGuiaController.dispose();
    _destinatarioController.dispose();
    _destinoController.dispose();
    super.dispose();
  }

  void _toggleGps(bool activo) {
    setState(() {
      _gpsActivo = activo;
      if (activo) {
        // Simula una posición dentro de Lima: la geolocalización real
        // todavía no está integrada (ver ARCHITECTURE.md, sección 8).
        final rnd = Random();
        _lat = -12.0464 + (rnd.nextDouble() - 0.5) * 0.05;
        _lng = -77.0428 + (rnd.nextDouble() - 0.5) * 0.05;
      } else {
        _lat = null;
        _lng = null;
      }
    });
  }

  void _simularFoto() {
    final aleatorio = Random().nextInt(9000) + 1000;
    setState(() {
      _fotoSimulada = true;
      _numeroGuiaController.text = 'IPE-2026-$aleatorio';
    });
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
              onChanged: _toggleGps,
              title: const Text('GPS activo'),
              subtitle: Text(
                _gpsActivo
                    ? 'Ubicación disponible: se adjuntará a la foto.'
                    : 'Obligatorio: sin GPS no se puede subir ningún registro fotográfico.',
              ),
              secondary: Icon(
                _gpsActivo ? Icons.gps_fixed : Icons.gps_off,
                color: _gpsActivo ? Colors.green : Colors.red,
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _gpsActivo ? _simularFoto : null,
            icon: const Icon(Icons.camera_alt),
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
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(
                    Icons.receipt_long,
                    size: 64,
                    color: Colors.grey,
                  ),
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
