import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rol_usuario.dart';
import '../services/guias_api.dart';
import '../state/app_state.dart';
import 'admin/admin_dashboard_screen.dart';
import 'tracking/public_tracking_screen.dart';
import 'transportista/task_list_screen.dart';

const _navy = Color(0xFF0E2038);
const _navyLight = Color(0xFF16345C);

/// Pantalla de inicio de la app: login simple por nombre + PIN, con
/// opción de auto-registro (ver backend/README.md — no es un mecanismo
/// de autenticación real, es solo para pruebas del equipo). El
/// auto-registro siempre crea la cuenta como Transportista; las cuentas
/// de Administrador se dan de alta a mano en la hoja "Usuarios". El
/// rol con el que se entra lo decide el backend, no un selector previo.
/// Equipo Comercial no necesita cuenta — entra por el link de abajo.
///
/// Layout: panel de marca a la izquierda + tarjeta de login a la derecha
/// en pantallas anchas; en pantallas angostas (celular) solo la tarjeta.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nombreController = TextEditingController();
  final _pinController = TextEditingController();
  bool _modoRegistro = false;
  bool _verPin = false;
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
      backgroundColor: _navy,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ancha = constraints.maxWidth >= 900;
            final formulario = Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _TarjetaLogin(
                  nombreController: _nombreController,
                  pinController: _pinController,
                  modoRegistro: _modoRegistro,
                  verPin: _verPin,
                  enviando: _enviando,
                  error: _error,
                  onEnviar: _enviar,
                  onToggleVerPin: () => setState(() => _verPin = !_verPin),
                  onToggleModo: () => setState(() {
                    _modoRegistro = !_modoRegistro;
                    _error = null;
                  }),
                  onRastrear: _irARastreo,
                ),
              ),
            );

            if (!ancha) {
              return Container(color: Colors.grey[100], child: formulario);
            }

            return Row(
              children: [
                const Expanded(child: _PanelMarca()),
                Expanded(
                  child: Container(color: Colors.grey[100], child: formulario),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PanelMarca extends StatelessWidget {
  const _PanelMarca();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navy, _navyLight],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _PatronPuntos()),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Icon(
                      Icons.local_shipping,
                      size: 44,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'IPESA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'CONTROL DE GUÍAS',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'El sistema para seguir cada guía de reparto de IPESA, '
                    'desde la asignación hasta la entrega.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: const [
                      _Badge(icon: Icons.qr_code_2, label: 'OCR de guías'),
                      _Badge(icon: Icons.gps_fixed, label: 'GPS obligatorio'),
                      _Badge(
                        icon: Icons.location_on,
                        label: 'Geofencing',
                      ),
                      _Badge(
                        icon: Icons.fact_check_outlined,
                        label: 'Rastreo público',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Puntos + líneas sutiles de fondo, en el mismo espíritu del panel de
/// marca (decorativo, sin depender de ninguna imagen externa).
class _PatronPuntos extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final puntos = <Offset>[];
    final rnd = List.generate(28, (i) => i);
    for (final i in rnd) {
      final x = (i * 97) % size.width;
      final y = (i * 233) % size.height;
      puntos.add(Offset(x.toDouble(), y.toDouble()));
    }
    final paintLinea = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    final paintPunto = Paint()..color = Colors.white.withValues(alpha: 0.18);

    for (var i = 0; i < puntos.length; i++) {
      for (var j = i + 1; j < puntos.length; j++) {
        final d = (puntos[i] - puntos[j]).distance;
        if (d < 160) {
          canvas.drawLine(puntos[i], puntos[j], paintLinea);
        }
      }
    }
    for (final p in puntos) {
      canvas.drawCircle(p, 2.5, paintPunto);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TarjetaLogin extends StatelessWidget {
  const _TarjetaLogin({
    required this.nombreController,
    required this.pinController,
    required this.modoRegistro,
    required this.verPin,
    required this.enviando,
    required this.error,
    required this.onEnviar,
    required this.onToggleVerPin,
    required this.onToggleModo,
    required this.onRastrear,
  });

  final TextEditingController nombreController;
  final TextEditingController pinController;
  final bool modoRegistro;
  final bool verPin;
  final bool enviando;
  final String? error;
  final VoidCallback onEnviar;
  final VoidCallback onToggleVerPin;
  final VoidCallback onToggleModo;
  final VoidCallback onRastrear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Card(
        color: Colors.white,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _navy,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.local_shipping,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                modoRegistro ? 'Crear cuenta' : 'Iniciar sesión',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                modoRegistro
                    ? 'Se crea como Transportista.'
                    : 'Ingresa tus credenciales para acceder.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Nombre',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              TextField(
                controller: nombreController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Ej: Juan Pérez',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                onSubmitted: (_) => onEnviar(),
              ),
              const SizedBox(height: 18),
              Text('PIN', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              TextField(
                controller: pinController,
                obscureText: !verPin,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '••••',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      verPin ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: onToggleVerPin,
                  ),
                  helperText: modoRegistro
                      ? 'Elige un PIN — lo vas a usar para volver a entrar.'
                      : null,
                ),
                onSubmitted: (_) => onEnviar(),
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Text(error!, style: TextStyle(color: colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: enviando ? null : onEnviar,
                style: FilledButton.styleFrom(backgroundColor: _navy),
                child: enviando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(modoRegistro ? 'Crear cuenta' : 'Ingresar'),
              ),
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: enviando ? null : onToggleModo,
                  child: Text.rich(
                    TextSpan(
                      text: modoRegistro
                          ? '¿Ya tienes cuenta? '
                          : '¿No tienes cuenta? ',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                      children: [
                        TextSpan(
                          text: modoRegistro ? 'Ingresar' : 'Regístrate',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: TextButton.icon(
                  onPressed: enviando ? null : onRastrear,
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('¿Eres cliente? Rastrea tu envío aquí'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
