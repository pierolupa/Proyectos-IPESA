import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/ubicacion.dart';
import '../theme.dart';

/// Estado del GPS en las pantallas del transportista: se activa solo al
/// abrir la pantalla si ya estaba encendido o el celular ya dio permiso
/// (ver [Ubicacion]), y la posición se refresca en silencio.
mixin GpsTransportista<T extends StatefulWidget> on State<T> {
  bool gpsActivo = false;
  bool cargandoGps = false;
  double? lat;
  double? lng;

  @override
  void initState() {
    super.initState();
    _activarSolo();
  }

  Future<void> _activarSolo() async {
    if (!await Ubicacion.debeActivarseSolo() || !mounted || gpsActivo) return;
    final reciente = Ubicacion.reciente;
    if (reciente != null) {
      _usar(reciente);
      refrescarGps();
      return;
    }
    setState(() => cargandoGps = true);
    try {
      final posicion = await Ubicacion.actual();
      if (mounted) _usar(posicion);
    } catch (_) {
      // Queda apagado; el transportista lo enciende con el interruptor.
    } finally {
      if (mounted) setState(() => cargandoGps = false);
    }
  }

  void _usar(Position posicion) => setState(() {
    gpsActivo = true;
    lat = posicion.latitude;
    lng = posicion.longitude;
  });

  Future<void> activarGps() async {
    setState(() => cargandoGps = true);
    try {
      final posicion = await Ubicacion.actual();
      if (!mounted) return;
      _usar(posicion);
      Ubicacion.recordar(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo activar el GPS: $e')));
    } finally {
      if (mounted) setState(() => cargandoGps = false);
    }
  }

  void desactivarGps() {
    setState(() {
      gpsActivo = false;
      lat = null;
      lng = null;
    });
    Ubicacion.recordar(false);
  }

  /// Lee la posición de nuevo sin avisar nada; si falla se queda la
  /// anterior.
  Future<void> refrescarGps() async {
    try {
      final posicion = await Ubicacion.actual();
      if (!mounted || !gpsActivo) return;
      setState(() {
        lat = posicion.latitude;
        lng = posicion.longitude;
      });
    } catch (_) {}
  }

  /// Interruptor "GPS activo" de la pantalla.
  Widget tarjetaGps({
    required String textoActivo,
    required String textoApagado,
  }) {
    return Card(
      color: gpsActivo ? Ipesa.menta : Colors.red[50],
      child: SwitchListTile(
        value: gpsActivo,
        onChanged: cargandoGps
            ? null
            : (v) => v ? activarGps() : desactivarGps(),
        title: const Text('GPS activo'),
        subtitle: Text(
          cargandoGps
              ? 'Activando la ubicación de tu celular...'
              : gpsActivo
              ? textoActivo
              : textoApagado,
        ),
        secondary: cargandoGps
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                gpsActivo ? Icons.gps_fixed : Icons.gps_off,
                color: gpsActivo ? Colors.green : Colors.red,
              ),
      ),
    );
  }
}
