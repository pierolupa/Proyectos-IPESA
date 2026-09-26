import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/sucursal.dart';
import '../../services/guias_api.dart';
import '../../state/app_state.dart';
import '../../widgets/mapa_ubicacion.dart';

const _centroLima = LatLng(-12.0464, -77.0428);

/// El administrador marca el perímetro de una sucursal: toca el mapa para
/// poner el centro y ajusta el radio. Si [sucursal] es null, se crea una.
class SucursalEditScreen extends StatefulWidget {
  const SucursalEditScreen({super.key, this.sucursal});

  final Sucursal? sucursal;

  @override
  State<SucursalEditScreen> createState() => _SucursalEditScreenState();
}

class _SucursalEditScreenState extends State<SucursalEditScreen> {
  late final TextEditingController _nombreController;
  LatLng? _centro;
  late double _radio;
  bool _guardando = false;

  bool get _esNueva => widget.sucursal == null;

  @override
  void initState() {
    super.initState();
    final s = widget.sucursal;
    _nombreController = TextEditingController(text: s?.nombre ?? '');
    _centro = s == null ? null : LatLng(s.lat, s.lng);
    _radio = s?.radioM ?? 150;
  }

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }

  Future<void> _ejecutar(Future<void> Function() accion, String ok) async {
    setState(() => _guardando = true);
    try {
      await accion();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final mensaje = e is ApiException ? e.mensaje : 'Error de conexión: $e';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensaje)));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _guardar() {
    final nombre = _nombreController.text.trim();
    _ejecutar(
      () => context.read<AppState>().guardarSucursal(
        Sucursal(
          nombre: nombre,
          lat: _centro!.latitude,
          lng: _centro!.longitude,
          radioM: _radio.roundToDouble(),
        ),
      ),
      'Perímetro de $nombre guardado.',
    );
  }

  Future<void> _eliminar() async {
    final nombre = widget.sucursal!.nombre;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Eliminar $nombre?'),
        content: const Text(
          'Los traslados hacia esta sucursal no podrán registrar su llegada '
          'hasta que se vuelva a marcar su perímetro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    _ejecutar(
      () => context.read<AppState>().eliminarSucursal(nombre),
      '$nombre eliminada.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final puedeGuardar =
        !_guardando &&
        _centro != null &&
        _nombreController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_esNueva ? 'Nueva sucursal' : widget.sucursal!.nombre),
        actions: [
          if (!_esNueva)
            IconButton(
              tooltip: 'Eliminar sucursal',
              icon: const Icon(Icons.delete_outline),
              onPressed: _guardando ? null : _eliminar,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nombreController,
            enabled: _esNueva,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Nombre de la sucursal',
              helperText:
                  'Es el nombre que el transportista elige como destino.',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _centro == null
                ? 'Toca el mapa en la ubicación de la sucursal.'
                : 'Toca el mapa para mover el centro del perímetro.',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 380,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: _centro ?? _centroLima,
                  initialZoom: _centro == null ? 11 : 16,
                  onTap: (_, punto) => setState(() => _centro = punto),
                ),
                children: [
                  ...capasBaseMapa(),
                  if (_centro != null)
                    capaPerimetro(
                      Sucursal(
                        nombre: '',
                        lat: _centro!.latitude,
                        lng: _centro!.longitude,
                        radioM: _radio,
                      ),
                    ),
                  if (_centro != null)
                    MarkerLayer(markers: [marcador(_centro!, Colors.purple)]),
                  atribucionMapa,
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Radio del perímetro: ${_radio.round()} m',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Slider(
            value: _radio,
            min: 20,
            max: 1000,
            divisions: 98,
            label: '${_radio.round()} m',
            onChanged: (v) => setState(() => _radio = v),
          ),
          const Text(
            'El transportista solo puede registrar la llegada del traslado '
            'si su GPS está dentro de este círculo.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: puedeGuardar ? _guardar : null,
            icon: _guardando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
            label: const Text('Guardar perímetro'),
          ),
        ],
      ),
    );
  }
}
