import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../state/app_state.dart';
import '../../widgets/estado_badge.dart';

/// Corrección manual de datos (ARCHITECTURE.md, sección 6): el
/// administrador tiene acceso total para cambiar el estado de cualquier
/// tarea y corregir el número de guía cuando el OCR falló.
class AdminGuiaEditScreen extends StatefulWidget {
  const AdminGuiaEditScreen({super.key, required this.numeroGuia});

  final String numeroGuia;

  @override
  State<AdminGuiaEditScreen> createState() => _AdminGuiaEditScreenState();
}

class _AdminGuiaEditScreenState extends State<AdminGuiaEditScreen> {
  late final TextEditingController _numeroController;

  @override
  void initState() {
    super.initState();
    _numeroController = TextEditingController(text: widget.numeroGuia);
  }

  @override
  void dispose() {
    _numeroController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final guia = appState.buscarPorNumero(widget.numeroGuia);

    if (guia == null) {
      return const Scaffold(body: Center(child: Text('Guía no encontrada.')));
    }

    return Scaffold(
      appBar: AppBar(title: Text('Editar · ${guia.numeroGuia}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EstadoBadge(estado: guia.estado),
          const SizedBox(height: 24),
          Text(
            'Número de guía',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _numeroController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    helperText:
                        'Corrección manual cuando el OCR no leyó bien la guía.',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _numeroController.text.trim() == guia.numeroGuia
                    ? null
                    : () {
                        final nuevo = _numeroController.text.trim();
                        context.read<AppState>().corregirNumeroGuia(
                          guia.numeroGuia,
                          nuevo,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Número corregido.')),
                        );
                      },
                child: const Text('Guardar'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Estado', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          DropdownButtonFormField<EstadoGuia>(
            initialValue: guia.estado,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              for (final estado in EstadoGuia.values)
                DropdownMenuItem(value: estado, child: Text(estado.etiqueta)),
            ],
            onChanged: (nuevoEstado) {
              if (nuevoEstado == null) return;
              context.read<AppState>().actualizarEstado(
                guia.numeroGuia,
                nuevoEstado,
                porAdmin: true,
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            'Destinatario: ${guia.destinatario}\n'
            'Origen: ${guia.origen}\n'
            'Destino: ${guia.destino}\n'
            'Transportista: ${guia.transportista}',
            style: TextStyle(color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}
