import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../state/app_state.dart';
import '../../widgets/guia_card.dart';
import 'admin_guia_edit_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  EstadoGuia? _filtro;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final guias = appState.guias
        .where((g) => _filtro == null || g.estado == _filtro)
        .toList()
      ..sort((a, b) => b.fechaActualizacion.compareTo(a.fechaActualizacion));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Administrador'),
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _FiltroChip(
                    label: 'Todas (${appState.guias.length})',
                    selected: _filtro == null,
                    onTap: () => setState(() => _filtro = null),
                  ),
                  for (final estado in EstadoGuia.values)
                    _FiltroChip(
                      label: estado.etiqueta,
                      selected: _filtro == estado,
                      onTap: () => setState(() => _filtro = estado),
                    ),
                ],
              ),
            ),
          ),
          Expanded(child: _buildLista(context, appState, guias)),
        ],
      ),
    );
  }

  Widget _buildLista(
    BuildContext context,
    AppState appState,
    List<Guia> guias,
  ) {
    if (appState.cargando && guias.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (appState.error != null && appState.guias.isEmpty) {
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
      return const Center(child: Text('No hay guías con este filtro.'));
    }
    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().cargarGuias(),
      child: ListView.builder(
        itemCount: guias.length,
        itemBuilder: (context, index) {
          final guia = guias[index];
          return GuiaCard(
            guia: guia,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      AdminGuiaEditScreen(numeroGuia: guia.numeroGuia),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _FiltroChip extends StatelessWidget {
  const _FiltroChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
    );
  }
}
