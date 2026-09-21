import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rol_usuario.dart';
import '../services/guias_api.dart';
import '../state/app_state.dart';
import 'admin/admin_dashboard_screen.dart';
import 'tracking/public_tracking_screen.dart';
import 'transportista/task_list_screen.dart';

/// Pantalla de inicio de la app: login simple por nombre + PIN, con
/// opción de auto-registro (ver backend/README.md — no es un mecanismo
/// de autenticación real, es solo para pruebas del equipo). El
/// auto-registro siempre crea la cuenta como Transportista; las cuentas
/// de Administrador se dan de alta a mano en la hoja "Usuarios". El
/// rol con el que se entra lo decide el backend, no un selector previo.
/// Equipo Comercial no necesita cuenta — entra por el link de abajo.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nombreController = TextEditingController();
  final _pinController = TextEditingController();
  bool _modoRegistro = false;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _nombreController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final nombre = _nombreController.text.trim();
    final pin = _pinController.text.trim();
    if (nombre.isEmpty || pin.isEmpty) return;

    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final appState = context.read<AppState>();
      if (_modoRegistro) {
        await appState.registrarUsuario(nombre, pin);
      } else {
        await appState.iniciarSesion(nombre, pin);
      }
      if (!mounted) return;
      final destino = appState.rolActual == RolUsuario.administrador
          ? const AdminDashboardScreen()
          : const TaskListScreen();
      // push (no pushReplacement): LoginScreen es la ruta raíz de la app,
      // y "Cambiar rol"/logout hace popUntil(isFirst) para volver a ella.
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => destino));
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (e) {
      setState(() => _error = 'Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _irARastreo() {
    context.read<AppState>().entrarComoComercial();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PublicTrackingScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.local_shipping,
                    size: 56,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'IPESA · Control de Guías',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Conectado a Google Sheets en vivo.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _modoRegistro ? 'Crear cuenta' : 'Ingresar',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nombreController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    onSubmitted: (_) => _enviar(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock),
                      helperText: _modoRegistro
                          ? 'Elige un PIN — lo vas a usar para volver a entrar.'
                          : null,
                    ),
                    onSubmitted: (_) => _enviar(),
                  ),
                  if (_modoRegistro) ...[
                    const SizedBox(height: 8),
                    Text(
                      'La cuenta se crea como Transportista. Si necesitas '
                      'acceso de Administrador, pídeselo a quien administra '
                      'la hoja de guías.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _enviando ? null : _enviar,
                    child: _enviando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_modoRegistro ? 'Crear cuenta' : 'Ingresar'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _enviando
                        ? null
                        : () => setState(() {
                            _modoRegistro = !_modoRegistro;
                            _error = null;
                          }),
                    child: Text(
                      _modoRegistro
                          ? '¿Ya tienes cuenta? Ingresar'
                          : '¿No tienes cuenta? Crear una',
                    ),
                  ),
                  const Divider(height: 32),
                  OutlinedButton.icon(
                    onPressed: _enviando ? null : _irARastreo,
                    icon: const Icon(Icons.search),
                    label: const Text('Rastrear un envío sin cuenta'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
