import 'package:flutter/material.dart';

import '../models/estado_guia.dart';

class EstadoBadge extends StatelessWidget {
  const EstadoBadge({super.key, required this.estado});

  final EstadoGuia estado;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: estado.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: estado.color.withValues(alpha: 0.4)),
      ),
      child: Text(
        estado.etiqueta,
        style: TextStyle(
          color: estado.color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
