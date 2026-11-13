import 'package:flutter/material.dart';

import '../models/estado_guia.dart';

class EstadoBadge extends StatelessWidget {
  const EstadoBadge({super.key, required this.estado, this.custodia = false});

  final EstadoGuia estado;

  /// En ruta pero en custodia del transportista (ver Guia.enCustodia).
  final bool custodia;

  @override
  Widget build(BuildContext context) {
    final color = custodia ? colorCustodia : estado.color;
    // Align evita que el badge se estire a todo el ancho dentro de listas.
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      heightFactor: 1,
      // Sin fondo: un punto y el texto en el color del estado.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            custodia ? 'En custodia' : estado.etiqueta,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
