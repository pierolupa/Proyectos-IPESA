import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../services/guias_api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';

/// Motivos frecuentes; "Otro" obliga a escribir el detalle.
const motivosRechazo = [
  'Cliente ausente',
  'Dirección incorrecta',
  'Cliente no acepta la mercadería',
  'Mercadería dañada o incompleta',
  'Problema con el vehículo',
  'Otro',
];

/// Abre la hoja para rechazar [guia]. Devuelve true si se rechazó.
Future<bool> mostrarRechazo(BuildContext context, Guia guia) async {
  final rechazada = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => HojaRechazo(guia: guia),
  );
  return rechazada ?? false;
}

/// La ubicación se guarda si se puede leer rápido; si no hay señal o
/// permiso, se rechaza igual.
Future<Position?> _ubicacionGps() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied ||
        permiso == LocationPermission.deniedForever) {
      return null;
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 8),
      ),
    );
  } catch (_) {
    return null;
  }
}

class HojaRechazo extends StatefulWidget {
  const HojaRechazo({super.key, required this.guia});

  final Guia guia;

  /// Cómo se lee la ubicación; los tests la reemplazan (no hay GPS ahí).
  @visibleForTesting
  static Future<Position?> Function() leerUbicacion = _ubicacionGps;

  @override
  State<HojaRechazo> createState() => _HojaRechazoState();
}

class _HojaRechazoState extends State<HojaRechazo> {
  final _detalle = TextEditingController();
  String? _motivo;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _detalle.dispose();
    super.dispose();
  }

  String? get _motivoFinal {
    final detalle = _detalle.text.trim();
    if (_motivo == null) return null;
    if (_motivo == 'Otro') return detalle.length >= 3 ? detalle : null;
    return detalle.isEmpty ? _motivo : '$_motivo: $detalle';
  }

  Future<void> _confirmar() async {
    final motivo = _motivoFinal;
    if (motivo == null) {
      setState(
        () => _error = _motivo == null
            ? 'Elige un motivo.'
            : 'Escribe qué pasó (al menos 3 letras).',
      );
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final posicion = await HojaRechazo.leerUbicacion();
      if (!mounted) return;
      await context.read<AppState>().rechazarGuia(
        widget.guia.numeroGuia,
        motivo,
        lat: posicion?.latitude,
        lng: posicion?.longitude,
      );
      if (mounted) Navigator.of(context).pop(true);
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
    final rojo = EstadoGuia.rechazado.color;
    final esOtro = _motivo == 'Otro';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Rechazar tarea', style: Ipesa.titulo(24, color: rojo)),
            const SizedBox(height: 4),
            Text(
              'Guía ${widget.guia.numeroGuia} · ${widget.guia.destinatario}',
              style: const TextStyle(color: Ipesa.textoSuave),
            ),
            const SizedBox(height: 18),
            Text('¿Por qué la rechazas?', style: Ipesa.titulo(16)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in motivosRechazo)
                  ChoiceChip(
                    label: Text(m),
                    selected: _motivo == m,
                    showCheckmark: false,
                    selectedColor: EstadoGuia.rechazado.colorFondo,
                    side: BorderSide(color: _motivo == m ? rojo : Ipesa.borde),
                    labelStyle: TextStyle(
                      fontFamily: Ipesa.fuenteTexto,
                      fontWeight: FontWeight.w600,
                      color: _motivo == m ? rojo : Ipesa.texto,
                    ),
                    onSelected: _enviando
                        ? null
                        : (_) => setState(() {
                            _motivo = m;
                            _error = null;
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _detalle,
              enabled: !_enviando,
              maxLines: 3,
              minLines: 2,
              maxLength: 250,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: esOtro
                    ? 'Motivo (obligatorio)'
                    : 'Detalle (opcional)',
                hintText: 'Cuéntale al administrador qué pasó',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: TextStyle(color: rojo)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _enviando ? null : _confirmar,
              style: FilledButton.styleFrom(backgroundColor: rojo),
              icon: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.block),
              label: const Text('Rechazar tarea'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _enviando
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
