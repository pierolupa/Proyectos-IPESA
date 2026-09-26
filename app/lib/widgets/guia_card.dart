import 'package:flutter/material.dart';

import '../models/guia.dart';
import 'estado_badge.dart';

class GuiaCard extends StatelessWidget {
  const GuiaCard({super.key, required this.guia, this.onTap});

  final Guia guia;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        onTap: onTap,
        title: Text(
          guia.numeroGuia,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${guia.destinatario} · ${guia.destino}'),
        ),
        trailing: EstadoBadge(estado: guia.estado),
        isThreeLine: false,
      ),
    );
  }
}
