import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/guia.dart';
import '../../state/app_state.dart';
import '../../widgets/estado_badge.dart';

/// Vista de rastreo simplificada (ARCHITECTURE.md, sección 6): sin usuario
/// registrado, solo se ingresan los últimos 4 dígitos de la guía. No se
/// exponen datos completos del destinatario ni del transportista.
class PublicTrackingScreen extends StatefulWidget {
  const PublicTrackingScreen({super.key});

  @override
  State<PublicTrackingScreen> createState() => _PublicTrackingScreenState();
}

class _PublicTrackingScreenState extends State<PublicTrackingScreen> {
  final _controller = TextEditingController();
  List<Guia>? _resultados;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _buscar(BuildContext context) {
    final query = _controller.text.trim();
    if (query.length != 4) return;
    setState(() {
      _resultados = context.read<AppState>().buscarPorUltimosCuatroDigitos(
        query,
      );
    });
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
                    onSubmitted: (_) => _buscar(context),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _buscar(context),
                  child: const Text('Buscar'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_resultados != null)
              Expanded(
                child: _resultados!.isEmpty
                    ? const Center(
                        child: Text('No se encontró ninguna guía.'),
                      )
                    : ListView.separated(
                        itemCount: _resultados!.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final guia = _resultados![index];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '•••• ${guia.ultimosCuatroDigitos}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  EstadoBadge(estado: guia.estado),
                                  const SizedBox(height: 8),
                                  Text('Destino: ${guia.destino}'),
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
