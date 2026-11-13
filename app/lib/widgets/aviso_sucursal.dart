import 'package:flutter/material.dart';

import '../theme.dart';

/// "Estás en (sucursal)": el GPS está dentro del perímetro de una sucursal.
class AvisoSucursal extends StatelessWidget {
  const AvisoSucursal({super.key, required this.nombre, required this.detalle});

  final String nombre;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Ipesa.mentaBorde),
        borderRadius: BorderRadius.circular(Ipesa.radioCampo),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront_outlined, color: Ipesa.turquesa),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estás en $nombre',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Ipesa.petroleo,
                  ),
                ),
                Text(
                  detalle,
                  style: const TextStyle(fontSize: 13, color: Ipesa.textoSuave),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
