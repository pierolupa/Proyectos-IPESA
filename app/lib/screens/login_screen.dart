import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rol_usuario.dart';
import '../services/guias_api.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'admin/admin_dashboard_screen.dart';
import 'comercial/rastreo_screen.dart';
import 'tracking/public_tracking_screen.dart';
import 'transportista/task_list_screen.dart';

/// Pantalla de inicio de la app: login simple por nombre + PIN, con
/// opción de auto-registro (ver backend/README.md — no es un mecanismo
/// de autenticación real, es solo para pruebas del equipo). El
/// auto-registro siempre crea la cuenta como Transportista; las cuentas
/// de Administrador se dan de alta a mano en la hoja "Usuarios". El
/// rol con el que se entra lo decide el backend, no un selector previo.
/// Los clientes no necesitan cuenta: rastrean desde la tarjeta de abajo.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nombreController = TextEditingController();
  final _pinController = TextEditingController();
  final _rastreoController = TextEditingController();
  bool _modoRegistro = false;
  bool _verPin = false;
  bool _enviando = false;
  bool _verificandoSesion = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _verificarSesionGuardada(),
    );
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _pinController.dispose();
    _rastreoController.dispose();
    super.dispose();
  }

  /// Si ya había una sesión iniciada (ver AppState.restaurarSesion), entra
  /// directo al panel correspondiente en vez de mostrar el login — así
  /// recargar la página no obliga a volver a ingresar cada vez.
  Future<void> _verificarSesionGuardada() async {
    final appState = context.read<AppState>();
    await appState.restaurarSesion();
    if (!mounted) return;
    final rol = appState.rolActual;
    if (rol != null) {
      final destino = _pantallaDeInicio(rol);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => destino));
    }
    if (mounted) setState(() => _verificandoSesion = false);
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
      final destino = _pantallaDeInicio(appState.rolActual!);
      // push (no pushReplacement): LoginScreen es la ruta raíz de la app,
      // y el logout hace popUntil(isFirst) para volver a ella.
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => destino));
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (e) {
      setState(() => _error = 'Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  static Widget _pantallaDeInicio(RolUsuario rol) => switch (rol) {
    RolUsuario.administrador => const AdminDashboardScreen(),
    RolUsuario.transportista => const TaskListScreen(),
    RolUsuario.comercial => const RastreoScreen(),
  };

  void _irARastreo() {
    final digitos = _rastreoController.text.trim();
    context.read<AppState>().entrarComoComercial();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublicTrackingScreen(
          ultimosCuatro: digitos.length == 4 ? digitos : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_verificandoSesion) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: Ipesa.petroleo)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final formulario = Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 420,
                    minHeight: constraints.maxHeight - 64,
                  ),
                  child: IntrinsicHeight(child: _formulario(context)),
                ),
              ),
            );
            if (constraints.maxWidth < 900) return formulario;
            return Row(
              children: [
                const Expanded(child: _PanelMarca()),
                Expanded(child: formulario),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _formulario(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Marca(),
        const SizedBox(height: 48),
        Text(
          _modoRegistro ? 'Crear cuenta' : 'Bienvenido',
          style: Ipesa.titulo(34),
        ),
        const SizedBox(height: 8),
        Text(
          _modoRegistro
              ? 'Tu cuenta se crea como transportista.'
              : 'Ingresa para ver y registrar tus guías.',
          style: const TextStyle(fontSize: 17, color: Ipesa.textoSuave),
        ),
        const SizedBox(height: 32),
        const _Etiqueta('Nombre'),
        TextField(
          controller: _nombreController,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(fontSize: 17),
          decoration: const InputDecoration(hintText: 'Ej. Juan Pérez'),
          onSubmitted: (_) => _enviar(),
        ),
        const SizedBox(height: 14),
        const _Etiqueta('PIN'),
        TextField(
          controller: _pinController,
          obscureText: !_verPin,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 17),
          decoration: InputDecoration(
            hintText: '4 dígitos',
            helperText: _modoRegistro
                ? 'Elige un PIN: lo usarás para volver a entrar.'
                : null,
            suffixIcon: IconButton(
              tooltip: _verPin ? 'Ocultar PIN' : 'Mostrar PIN',
              icon: Icon(_verPin ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _verPin = !_verPin),
            ),
          ),
          onSubmitted: (_) => _enviar(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _enviando ? null : _enviar,
          child: _enviando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_modoRegistro ? 'Crear cuenta' : 'Ingresar'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _enviando
              ? null
              : () => setState(() {
                  _modoRegistro = !_modoRegistro;
                  _error = null;
                }),
          child: Text(
            _modoRegistro ? 'Ya tengo cuenta: ingresar' : 'Crear una cuenta',
          ),
        ),
        const Spacer(),
        const SizedBox(height: 24),
        _TarjetaRastreo(
          controller: _rastreoController,
          onBuscar: _enviando ? null : _irARastreo,
        ),
      ],
    );
  }
}

class _Marca extends StatelessWidget {
  const _Marca();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Ipesa.turquesa,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text('IPESA', style: Ipesa.titulo(18).copyWith(letterSpacing: 3)),
        const SizedBox(width: 6),
        const Flexible(
          child: Text(
            '· Tracking Distribución',
            style: TextStyle(fontSize: 14, color: Ipesa.textoSuave),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Ipesa.etiqueta,
        ),
      ),
    );
  }
}

class _TarjetaRastreo extends StatelessWidget {
  const _TarjetaRastreo({required this.controller, required this.onBuscar});

  final TextEditingController controller;
  final VoidCallback? onBuscar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Ipesa.menta,
        borderRadius: BorderRadius.circular(Ipesa.radio),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('¿Eres cliente? Rastrea tu envío', style: Ipesa.titulo(16)),
          const SizedBox(height: 8),
          const Text(
            'Escribe los últimos 4 dígitos de tu guía.',
            style: TextStyle(fontSize: 14, color: Ipesa.etiqueta),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: controller,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 18, letterSpacing: 4),
                  decoration: const InputDecoration(
                    hintText: '0133',
                    counterText: '',
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: Ipesa.mentaBorde),
                    ),
                  ),
                  onSubmitted: (_) => onBuscar?.call(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: onBuscar,
                  style: FilledButton.styleFrom(
                    backgroundColor: Ipesa.turquesa,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Buscar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Panel de marca a la izquierda en pantallas anchas (computadora).
class _PanelMarca extends StatelessWidget {
  const _PanelMarca();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Ipesa.petroleo,
      padding: const EdgeInsets.all(56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'IPESA',
            style: Ipesa.titulo(
              22,
              color: Colors.white,
            ).copyWith(letterSpacing: 4),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cada guía,\ndesde la salida\nhasta la entrega.',
                style: Ipesa.titulo(
                  44,
                  color: Colors.white,
                ).copyWith(height: 1.15),
              ),
              const SizedBox(height: 20),
              const Text(
                'Foto de la guía leída con IA, GPS obligatorio, perímetro de '
                'sucursales y avisos en vivo para el administrador.',
                style: TextStyle(
                  fontSize: 17,
                  height: 1.5,
                  color: Ipesa.suaveSobrePetroleo,
                ),
              ),
            ],
          ),
          const Text(
            'IPESA S.A.C. · Tracking Distribución',
            style: TextStyle(fontSize: 14, color: Ipesa.suaveSobrePetroleo),
          ),
        ],
      ),
    );
  }
}
