import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Mientras esta pantalla está abierta, recarga las guías cada [intervalo]
/// sin que el usuario tenga que tocar "Actualizar".
///
/// Si la app no se está viendo (pestaña en segundo plano, celular
/// bloqueado, ventana minimizada) no consulta nada, salvo que se indique
/// [intervaloOculta] (el panel del administrador, para seguir mandando
/// notificaciones). Al volver a verse, actualiza en ese momento.
///
/// Va una sola vez por pantalla principal: las pantallas que se abren
/// encima no llevan otra, porque la de abajo sigue actualizando.
class ActualizacionAutomatica extends StatefulWidget {
  const ActualizacionAutomatica({
    super.key,
    required this.intervalo,
    required this.child,
    this.intervaloOculta,
    this.onCambios,
    this.activa = true,
  });

  /// false = no actualiza (otra pantalla debajo ya lo hace).
  final bool activa;

  final Duration intervalo;

  /// Cada cuánto actualizar con la app oculta; null = no actualizar.
  final Duration? intervaloOculta;
  final Widget child;
  final void Function(List<CambioGuia> cambios)? onCambios;

  @override
  State<ActualizacionAutomatica> createState() =>
      _ActualizacionAutomaticaState();
}

class _ActualizacionAutomaticaState extends State<ActualizacionAutomatica> {
  Timer? _timer;
  bool _enCurso = false;
  bool _oculta = false;
  late final AppLifecycleListener _ciclo;

  @override
  void initState() {
    super.initState();
    _ciclo = AppLifecycleListener(onStateChange: _cambioDeEstado);
    _programar();
  }

  void _cambioDeEstado(AppLifecycleState estado) {
    // "inactive" es visible pero sin foco (p. ej. otra ventana encima).
    final oculta =
        estado == AppLifecycleState.hidden ||
        estado == AppLifecycleState.paused ||
        estado == AppLifecycleState.detached;
    if (oculta == _oculta) return;
    _oculta = oculta;
    if (!oculta && widget.activa) _actualizar();
    _programar();
  }

  void _programar() {
    _timer?.cancel();
    _timer = null;
    final intervalo = _oculta ? widget.intervaloOculta : widget.intervalo;
    if (widget.activa && intervalo != null) {
      _timer = Timer.periodic(intervalo, (_) => _actualizar());
    }
  }

  Future<void> _actualizar() async {
    if (_enCurso || !mounted) return;
    _enCurso = true;
    try {
      final cambios = await context.read<AppState>().actualizarEnSegundoPlano();
      if (mounted && cambios.isNotEmpty) widget.onCambios?.call(cambios);
    } finally {
      _enCurso = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ciclo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
