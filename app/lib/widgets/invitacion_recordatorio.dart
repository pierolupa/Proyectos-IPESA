import 'package:flutter/material.dart';

import '../theme.dart';

/// Ofrece activar el recordatorio de las 6 p. m.: un aviso en el celular
/// con las tareas que faltan cerrar, aunque la app esté cerrada.
class InvitacionRecordatorio extends StatelessWidget {
  const InvitacionRecordatorio({
    super.key,
    required this.onActivar,
    required this.onAhoraNo,
  });

  final VoidCallback onActivar;
  final VoidCallback onAhoraNo;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      decoration: BoxDecoration(
        color: Ipesa.menta,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ipesa.mentaBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.notifications_active_outlined, color: Ipesa.petroleo),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Recordatorio a las 6 p. m. de las tareas que te falten '
                  'cerrar, aunque tengas la app cerrada.',
                  style: TextStyle(color: Ipesa.texto, height: 1.3),
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onAhoraNo, child: const Text('Ahora no')),
              const SizedBox(width: 4),
              FilledButton(onPressed: onActivar, child: const Text('Activar')),
            ],
          ),
        ],
      ),
    );
  }
}
