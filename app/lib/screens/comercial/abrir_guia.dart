import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/despacho.dart';
import '../../models/guia.dart';
import '../../state/app_state.dart';
import '../../widgets/pasos_registro.dart';
import '../../widgets/ventana_busqueda.dart';
import 'rastreo_detalle_screen.dart';

/// Abre una guía de Rastrear (la única que encontró la búsqueda o la que se
/// tocó en la lista) con la ventana de los pasos. Mientras tanto deja la
/// foto descargada: al tocar "Ver foto" sale al instante.
Future<void> abrirGuiaRastreo(BuildContext context, Guia guia) async {
  final app = context.read<AppState>();
  final abrir = await _mostrarPasos(
    context,
    preparar: guia.tieneFotoEntrega
        ? () => app.fotoEntrega(guia).timeout(const Duration(seconds: 8))
        : null,
  );
  if (!abrir || !context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RastreoDetalleScreen(
        numeroGuia: guia.numeroGuia,
        fechaCreacion: guia.fechaCreacion,
      ),
    ),
  );
}

/// Una guía que solo está en Despachos Ate (no tiene foto).
Future<void> abrirDespachoRastreo(BuildContext context, Despacho d) async {
  final abrir = await _mostrarPasos(context);
  if (!abrir || !context.mounted) return;
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => RastreoDetalleScreen.despacho(d)));
}

Future<bool> _mostrarPasos(
  BuildContext context, {
  Future<void> Function()? preparar,
}) async {
  final listo = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => _Apertura(preparar: preparar),
    transitionBuilder: (_, animacion, _, child) =>
        FadeTransition(opacity: animacion, child: child),
  );
  return listo ?? false;
}

/// La ventana con la marca IPESA y los pasos: Tareas y Despachos IPESA ya
/// están (la búsqueda los trajo), la Foto se baja ahora y luego Lista.
class _Apertura extends StatefulWidget {
  const _Apertura({this.preparar});

  final Future<void> Function()? preparar;

  @override
  State<_Apertura> createState() => _AperturaState();
}

class _AperturaState extends State<_Apertura> {
  /// Cuántos pasos terminaron (el siguiente está en curso).
  int _hechos = 0;

  static const _paso = Duration(milliseconds: 280);

  @override
  void initState() {
    super.initState();
    _avanzar();
  }

  Future<void> _avanzar() async {
    for (var i = 0; i < 2; i++) {
      await Future<void>.delayed(_paso);
      if (!mounted) return;
      setState(() => _hechos++);
    }
    final preparar = widget.preparar;
    // La foto: si falla o demora, la guía se abre igual y se pide ahí.
    await Future.wait([
      Future<void>.delayed(_paso),
      if (preparar != null) preparar().catchError((Object _) {}),
    ]);
    if (!mounted) return;
    setState(() => _hechos = 4);
    // Se ve "¡Listo!" un momento antes de abrir.
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    EstadoPaso estado(int i) => i < _hechos
        ? EstadoPaso.hecho
        : i == _hechos
        ? EstadoPaso.activo
        : EstadoPaso.pendiente;
    return VentanaBusqueda(
      lista: _hechos >= 4,
      pasos: [
        PasoRegistro('Tareas', Icons.assignment_outlined, estado(0)),
        PasoRegistro('Despachos IPESA', Icons.warehouse_outlined, estado(1)),
        PasoRegistro('Foto', Icons.image_outlined, estado(2)),
        PasoRegistro('Lista', Icons.fact_check_outlined, estado(3)),
      ],
    );
  }
}
