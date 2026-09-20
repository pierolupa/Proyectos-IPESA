import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  void _simularFoto() {
    final aleatorio = Random().nextInt(9000) + 1000;
    setState(() {
      _fotoSimulada = true;
      _numeroGuiaController.text = 'IPE-2026-$aleatorio';
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final numero = _numeroGuiaController.text.trim();
    final esDuplicado = numero.isNotEmpty && appState.esDuplicado(numero);
    final puedeConfirmar =
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
              onChanged: (v) => setState(() => _gpsActivo = v),
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
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.qr_code_2),
                helperText:
                    'Editable antes de confirmar, por si el OCR se equivocó.',
                errorText: esDuplicado
                    ? 'Este número ya está en ruta o registrado.'
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _destinatarioController,
              decoration: const InputDecoration(
                labelText: 'Destinatario',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _destinoController,
              decoration: const InputDecoration(
                labelText: 'Destino',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: puedeConfirmar
                ? () {
                    context.read<AppState>().asignarNuevaGuia(
                      numeroGuia: numero,
                      destino: _destinoController.text.trim(),
                      destinatario: _destinatarioController.text.trim(),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Guía $numero asignada · estado: en ruta'),
                      ),
                    );
                    Navigator.of(context).pop();
                  }
                : null,
            icon: const Icon(Icons.check_circle),
            label: const Text('Confirmar asignación'),
          ),
        ],
      ),
    );
  }
}
