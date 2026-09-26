import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Mientras esta pantalla está abierta, recarga las guías cada [intervalo]
/// sin que el usuario tenga que tocar "Actualizar".
class ActualizacionAutomatica extends StatefulWidget {
  const ActualizacionAutomatica({
    super.key,
    required this.intervalo,
    required this.child,
    this.onCambios,
  });

  final Duration intervalo;
  final Widget child;
  final void Function(List<CambioGuia> cambios)? onCambios;

  @override
  State<ActualizacionAutomatica> createState() =>
      _ActualizacionAutomaticaState();
}

class _ActualizacionAutomaticaState extends State<ActualizacionAutomatica> {
  Timer? _timer;
  bool _enCurso = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.intervalo, (_) => _actualizar());
  }

  Future<void> _actualizar() async {
    if (_enCurso) return;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
