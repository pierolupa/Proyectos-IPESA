import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/estado_guia.dart';
import '../models/guia.dart';
import '../models/tipo_entrega.dart';
import '../services/guias_api.dart';
import '../state/app_state.dart';

final _fechaCustodia = DateFormat('dd/MM HH:mm');

/// "Desde 19/10 18:30" de una guía en custodia.
String desdeCustodia(Guia g) =>
    'Desde ${_fechaCustodia.format(g.custodiaDesde!.toLocal())}';

/// Pone (con confirmación) o quita la custodia de [g] y avisa el resultado.
/// La usan el detalle de la tarea y el menú "⋯" de su tarjeta.
Future<void> cambiarCustodia(
  BuildContext context,
  Guia g, {
  required bool poner,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final app = context.read<AppState>();
  if (poner) {
    final seguir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Dejar en custodia?'),
        content: Text(
          'Te quedas con la mercadería de la guía ${g.numeroGuia} y la '
          'entregas mañana temprano, directo al cliente. El comercial verá '
          'que está en custodia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Dejar en custodia'),
          ),
        ],
      ),
    );
    if (seguir != true) return;
  }
  try {
    if (poner) {
      await app.ponerEnCustodia(g);
    } else {
      await app.quitarCustodia(g);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          poner
              ? 'Guía ${g.numeroGuia} en custodia. Mañana regístrala con '
                    '«Registrar entrega».'
              : 'La guía ${g.numeroGuia} ya no está en custodia.',
        ),
      ),
    );
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.mensaje)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Error de conexión: $e')));
  }
}

/// Custodia: el transportista se queda con la mercadería y la entrega
/// directo al día siguiente. La guía sigue en ruta y se entrega con el
/// flujo de siempre; el comercial la ve "En custodia" en Rastrear.
///
/// Sin custodia, un botón para ponerla; con custodia, un aviso con la
/// fecha y la opción de quitarla (si se marcó por error).
class AccionCustodia extends StatefulWidget {
  const AccionCustodia({super.key, required this.guia});

  final Guia guia;

  /// Solo una guía en ruta a un cliente o agencia (no en trasbordo, ni
  /// cerrada, ni un traslado entre sucursales).
  static bool aplica(Guia g) =>
      g.estado == EstadoGuia.enRuta &&
      g.tipoEntrega != TipoEntrega.entreSucursales;

  @override
  State<AccionCustodia> createState() => _AccionCustodiaState();
}

class _AccionCustodiaState extends State<AccionCustodia> {
  bool _ocupado = false;

  Future<void> _cambiar({required bool poner}) async {
    setState(() => _ocupado = true);
    try {
      await cambiarCustodia(context, widget.guia, poner: poner);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.guia;
    if (!g.enCustodia) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.inventory_2_outlined),
        label: const Text('Dejar en custodia'),
        style: OutlinedButton.styleFrom(
          foregroundColor: colorCustodia,
          side: const BorderSide(color: colorCustodia),
        ),
        onPressed: _ocupado ? null : () => _cambiar(poner: true),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
      decoration: BoxDecoration(
        color: colorCustodia.withValues(alpha: 0.08),
        border: Border.all(color: colorCustodia.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.inventory_2_outlined, color: colorCustodia),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'En custodia',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: colorCustodia,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${desdeCustodia(g)}. Mañana entrégala directo con '
                      '«Registrar entrega».',
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _ocupado ? null : () => _cambiar(poner: false),
              child: const Text('Quitar custodia'),
            ),
          ),
        ],
      ),
    );
  }
}
