import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../widgets/guia_card.dart';
import 'capture_flow_screen.dart';
import 'guia_detail_screen.dart';

class TaskListScreen extends StatelessWidget {
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final guias = appState.guiasDelTransportista(appState.transportistaActual);

    return Scaffold(
      appBar: AppBar(
        title: Text('Mis tareas · ${appState.transportistaActual}'),
        actions: [
          IconButton(
            tooltip: 'Cambiar rol',
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<AppState>().cerrarSesion();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.camera_alt),
        label: const Text('Nueva guía'),
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CaptureFlowScreen()));
        },
      ),
      body: guias.isEmpty
          ? const Center(child: Text('No tienes guías asignadas todavía.'))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: guias.length,
              itemBuilder: (context, index) {
                final guia = guias[index];
                return GuiaCard(
                  guia: guia,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            GuiaDetailScreen(numeroGuia: guia.numeroGuia),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
