import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../services/guias_api.dart';
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
  bool _guardandoNumero = false;
  bool _guardandoEstado = false;

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

  void _mostrarError(Object e) {
    if (!mounted) return;
    final mensaje = e is ApiException ? e.mensaje : 'Error de conexión: $e';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _guardarNumero(String actual) async {
    final nuevo = _numeroController.text.trim();
    setState(() => _guardandoNumero = true);
    try {
      await context.read<AppState>().corregirNumeroGuia(actual, nuevo);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Número corregido.')));
    } catch (e) {
      _numeroController.text = actual;
      _mostrarError(e);
    } finally {
      if (mounted) setState(() => _guardandoNumero = false);
    }
  }

  Future<void> _cambiarEstado(String numeroGuia, EstadoGuia nuevoEstado) async {
    setState(() => _guardandoEstado = true);
    try {
      await context.read<AppState>().actualizarEstado(
        numeroGuia,
        nuevoEstado,
        porAdmin: true,
      );
    } catch (e) {
      _mostrarError(e);
    } finally {
      if (mounted) setState(() => _guardandoEstado = false);
    }
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
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    helperText:
                        'Corrección manual cuando el OCR no leyó bien la guía.',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed:
                    _guardandoNumero ||
                        _numeroController.text.trim() == guia.numeroGuia
                    ? null
                    : () => _guardarNumero(guia.numeroGuia),
                child: _guardandoNumero
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Estado', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          DropdownButtonFormField<EstadoGuia>(
            initialValue: guia.estado,
            decoration: const InputDecoration(),
            items: [
              for (final estado in EstadoGuia.values)
                DropdownMenuItem(value: estado, child: Text(estado.etiqueta)),
            ],
            onChanged: _guardandoEstado
                ? null
                : (nuevoEstado) {
                    if (nuevoEstado == null) return;
                    _cambiarEstado(guia.numeroGuia, nuevoEstado);
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
