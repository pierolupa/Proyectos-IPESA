import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/guia.dart';
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
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: appState.cargando
                ? null
                : () => context.read<AppState>().cargarGuias(),
          ),
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
      body: _buildBody(context, appState, guias),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppState appState,
    List<Guia> guias,
  ) {
    if (appState.cargando && guias.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (appState.error != null && guias.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 40),
              const SizedBox(height: 12),
              Text(
                'No se pudo cargar: ${appState.error}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.read<AppState>().cargarGuias(),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (guias.isEmpty) {
      return const Center(child: Text('No tienes guías asignadas todavía.'));
    }
    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().cargarGuias(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: guias.length,
        itemBuilder: (context, index) {
          final guia = guias[index];
          return GuiaCard(
            guia: guia,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GuiaDetailScreen(numeroGuia: guia.numeroGuia),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
