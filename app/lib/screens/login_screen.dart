import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rol_usuario.dart';
import '../services/guias_api.dart';
import '../state/app_state.dart';
import 'admin/admin_dashboard_screen.dart';
import 'transportista/task_list_screen.dart';

/// Login simple por nombre + PIN (ver backend/README.md — no es un
/// mecanismo de autenticación real, es solo para pruebas del equipo).
/// Sirve tanto para Transportistas como para Administradores; la pantalla
/// a la que se entra depende del rol que devuelva el backend, no de cómo
/// se llegó aquí.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nombreController = TextEditingController();
  final _pinController = TextEditingController();
  bool _ingresando = false;
  String? _error;

  @override
  void dispose() {
    _nombreController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    final nombre = _nombreController.text.trim();
    final pin = _pinController.text.trim();
    if (nombre.isEmpty || pin.isEmpty) return;

    setState(() {
      _ingresando = true;
      _error = null;
    });
    try {
      final appState = context.read<AppState>();
      await appState.iniciarSesion(nombre, pin);
      if (!mounted) return;
      final destino = appState.rolActual == RolUsuario.administrador
          ? const AdminDashboardScreen()
          : const TaskListScreen();
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => destino));
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (e) {
      setState(() => _error = 'Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _ingresando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ingresar')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _nombreController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              onSubmitted: (_) => _ingresar(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'PIN',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              onSubmitted: (_) => _ingresar(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _ingresando ? null : _ingresar,
              child: _ingresando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Ingresar'),
            ),
          ],
        ),
      ),
    );
  }
}
