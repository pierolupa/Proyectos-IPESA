import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/guias_api.dart';
import '../../state/app_state.dart';
import '../../widgets/estado_badge.dart';

/// Vista de rastreo simplificada (ARCHITECTURE.md, sección 6): sin usuario
/// registrado, solo se ingresan los últimos 4 dígitos de la guía. No se
/// exponen datos completos del destinatario ni del transportista — por eso
/// llama directo a la API en vez de usar la lista completa de AppState.
class PublicTrackingScreen extends StatefulWidget {
  const PublicTrackingScreen({super.key, this.api});

  /// Inyectable para tests; en la app real usa el backend desplegado.
  final GuiasApi? api;

  @override
  State<PublicTrackingScreen> createState() => _PublicTrackingScreenState();
}

class _PublicTrackingScreenState extends State<PublicTrackingScreen> {
  late final GuiasApi _api = widget.api ?? GuiasApi();
  final _controller = TextEditingController();
  List<ResultadoRastreo>? _resultados;
  bool _buscando = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final query = _controller.text.trim();
    if (query.length != 4) return;
    setState(() {
      _buscando = true;
      _error = null;
    });
    try {
      final resultados = await _api.buscarPorUltimosCuatroDigitos(query);
      setState(() => _resultados = resultados);
    } catch (e) {
      setState(() {
        _error = e is ApiException ? e.mensaje : 'Error de conexión: $e';
        _resultados = null;
      });
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rastreo de envío'),
        actions: [
          IconButton(
            tooltip: 'Volver',
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<AppState>().cerrarSesion();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ingresa los últimos 4 dígitos del número de guía. '
              'No se requiere usuario registrado.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLength: 4,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Últimos 4 dígitos',
                      counterText: '',
                    ),
                    onSubmitted: (_) => _buscar(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _buscando ? null : _buscar,
                  child: _buscando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Buscar'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else if (_resultados != null)
              Expanded(
                child: _resultados!.isEmpty
                    ? const Center(
                        child: Text('No se encontró ninguna guía.'),
                      )
                    : ListView.separated(
                        itemCount: _resultados!.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final resultado = _resultados![index];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '•••• ${resultado.ultimosCuatro}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  EstadoBadge(estado: resultado.estado),
                                  const SizedBox(height: 8),
                                  Text('Destino: ${resultado.destino}'),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
