import 'package:flutter/material.dart';

import '../models/estado_guia.dart';
import '../models/guia.dart';
import '../theme.dart';

/// Recuadro rojo con quién rechazó la tarea y por qué. No dibuja nada si la
/// guía no está rechazada.
class AvisoRechazo extends StatelessWidget {
  const AvisoRechazo({super.key, required this.guia});

  final Guia guia;

  @override
  Widget build(BuildContext context) {
    if (guia.estado != EstadoGuia.rechazado) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EstadoGuia.rechazado.colorFondo,
        border: Border.all(color: const Color(0xFFF3B8B2)),
        borderRadius: BorderRadius.circular(Ipesa.radioCampo),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.block, color: EstadoGuia.rechazado.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rechazada por ${guia.transportista}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: EstadoGuia.rechazado.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  guia.motivoRechazo.isEmpty
                      ? 'Sin motivo registrado.'
                      : 'Motivo: ${guia.motivoRechazo}',
                  style: const TextStyle(color: Ipesa.texto),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
