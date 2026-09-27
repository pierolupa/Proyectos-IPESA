import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rol_usuario.dart';
import '../services/guias_api.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/carrusel_marcas.dart';
import '../widgets/splash_ipesa.dart';
import '../services/splash_html.dart';
import 'admin/admin_dashboard_screen.dart';
import 'comercial/rastreo_screen.dart';
import 'transportista/task_list_screen.dart';

/// Pantalla de inicio de la app: login simple por nombre + PIN, con
/// opción de auto-registro (ver backend/README.md — no es un mecanismo
/// de autenticación real, es solo para pruebas del equipo). El
/// auto-registro siempre crea la cuenta como Transportista; las cuentas
/// de Administrador y de Equipo Comercial se dan de alta a mano en la hoja
/// "Usuarios". El rol con el que se entra lo decide el backend, no un
/// selector previo.
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
    super.dispose();
  }

  /// Si ya había una sesión iniciada (ver AppState.restaurarSesion), entra
  /// directo al panel correspondiente en vez de mostrar el login — así
  /// recargar la página no obliga a volver a ingresar cada vez.
  Future<void> _verificarSesionGuardada() async {
    final appState = context.read<AppState>();
    // Mientras se ve la pantalla de carga: se restaura la sesión (con sus
    // guías), se descargan los logos para que no aparezcan de a poco, y el
    // logo IPESA se ve al menos 1,5 s desde que se abrió la página.
    await Future.wait([
      appState.restaurarSesion(),
      _precargarImagenes(),
      Future<void>.delayed(
        esperaMinimaSplash(const Duration(milliseconds: 1500)),
      ),
    ]);
    if (!mounted) return;
    final rol = appState.rolActual;
    if (rol != null) {
      // Sin transición: la pantalla de carga la tapa y se desvanece encima.
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => _pantallaDeInicio(rol),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    }
    setState(() => _verificandoSesion = false);
    // Recién cuando la pantalla siguiente ya está dibujada se quita la de
    // carga de la web: así no hay parpadeo entre una y otra.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    quitarSplashHtml();
  }

  Future<void> _precargarImagenes() async {
    final rutas = [
      'assets/brand/ipesa_blanco.png',
      for (final (_, archivo) in marcasIpesa) 'assets/marcas/$archivo.png',
    ];
    try {
      await Future.wait([
        for (final ruta in rutas) precacheImage(AssetImage(ruta), context),
      ]).timeout(const Duration(seconds: 2));
    } catch (_) {
      // Si un logo no carga (o tarda), igual se sigue: no bloquea la entrada.
    }
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

  @override
  Widget build(BuildContext context) {
    if (_verificandoSesion) return const SplashIpesa();

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
        // En computadora las marcas van en el panel de la izquierda.
        if (MediaQuery.sizeOf(context).width < 900) ...[
          const SizedBox(height: 32),
          const _TituloMarcas(color: Ipesa.textoSuave),
          const SizedBox(height: 10),
          const CarruselMarcas(),
        ],
      ],
    );
  }
}

class _TituloMarcas extends StatelessWidget {
  const _TituloMarcas({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      'MARCAS QUE REPRESENTAMOS',
      style: TextStyle(
        fontSize: 12,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
        color: color,
      ),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorSplash,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Image.asset(
            'assets/brand/ipesa_blanco.png',
            height: 16,
            semanticLabel: 'IPESA',
          ),
        ),
        const SizedBox(width: 10),
        const Flexible(
          child: Text(
            'Tracking Distribución',
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
          Image.asset(
            'assets/brand/ipesa_blanco.png',
            height: 30,
            semanticLabel: 'IPESA',
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
          const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TituloMarcas(color: Ipesa.suaveSobrePetroleo),
              SizedBox(height: 12),
              CarruselMarcas(bordeTarjeta: Colors.transparent),
              SizedBox(height: 20),
              Text(
                'IPESA S.A.C. · Tracking Distribución',
                style: TextStyle(fontSize: 14, color: Ipesa.suaveSobrePetroleo),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
