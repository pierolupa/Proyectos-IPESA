import 'package:flutter/material.dart';

import '../models/estado_guia.dart';

class EstadoBadge extends StatelessWidget {
  const EstadoBadge({super.key, required this.estado});

  final EstadoGuia estado;

  @override
  Widget build(BuildContext context) {
    // Align evita que el badge se estire a todo el ancho dentro de listas.
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: estado.colorFondo,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          estado.etiqueta,
          style: TextStyle(
            color: estado.color,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
