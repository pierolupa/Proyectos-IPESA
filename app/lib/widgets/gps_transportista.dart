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

  /// La última lectura, para saber si es aproximada.
  Position? posicionGps;

  /// La ubicación tiene demasiado error para saber en qué sucursal está.
  bool get gpsAproximado =>
      posicionGps != null && Ubicacion.esAproximada(posicionGps!);

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
    posicionGps = posicion;
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
      posicionGps = null;
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
        posicionGps = posicion;
      });
    } catch (_) {}
  }

  /// Lee de nuevo mostrando que está leyendo (botón "Leer de nuevo").
  Future<void> releerGps() async {
    setState(() => cargandoGps = true);
    await refrescarGps();
    if (mounted) setState(() => cargandoGps = false);
  }

  /// Interruptor "GPS activo" de la pantalla.
  Widget tarjetaGps({
    required String textoActivo,
    required String textoApagado,
  }) {
    final aproximado = gpsActivo && gpsAproximado;
    final tarjeta = Card(
      color: aproximado
          ? const Color(0xFFFFF4DB)
          : gpsActivo
          ? Ipesa.menta
          : Colors.red[50],
      child: SwitchListTile(
        value: gpsActivo,
        onChanged: cargandoGps
            ? null
            : (v) => v ? activarGps() : desactivarGps(),
        title: const Text('GPS activo'),
        subtitle: Text(
          cargandoGps
              ? 'Leyendo la ubicación de tu celular...'
              : aproximado
              ? 'Ubicación aproximada (${Ubicacion.textoPrecision(posicionGps!)})'
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
                aproximado
                    ? Icons.gps_not_fixed
                    : gpsActivo
                    ? Icons.gps_fixed
                    : Icons.gps_off,
                color: aproximado
                    ? const Color(0xFFA86500)
                    : gpsActivo
                    ? Colors.green
                    : Colors.red,
              ),
      ),
    );
    if (!aproximado) return tarjeta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tarjeta,
        AvisoUbicacionAproximada(
          precision: Ubicacion.textoPrecision(posicionGps!),
          onReleer: cargandoGps ? null : releerGps,
        ),
      ],
    );
  }
}

/// Qué hacer cuando el celular da una ubicación aproximada: casi siempre es
/// la "ubicación precisa" apagada para el navegador, o el GPS sin señal
/// todavía (bajo techo).
class AvisoUbicacionAproximada extends StatelessWidget {
  const AvisoUbicacionAproximada({
    super.key,
    required this.precision,
    required this.onReleer,
  });

  final String precision;
  final VoidCallback? onReleer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4DB),
        borderRadius: BorderRadius.circular(Ipesa.radioCampo),
        border: Border.all(color: const Color(0xFFE9C46A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tu celular da una ubicación con un error de $precision: la '
            'guía puede quedar marcada lejos de donde estás.',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B4100),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '1. Activa la ubicación precisa: Ajustes › Aplicaciones › '
            'Chrome › Permisos › Ubicación › "Usar ubicación precisa".\n'
            '2. Sal a un lugar abierto unos segundos y vuelve a leer.',
            style: TextStyle(fontSize: 13.5, color: Color(0xFF6B4100)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onReleer,
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Leer de nuevo'),
            ),
          ),
        ],
      ),
    );
  }
}
