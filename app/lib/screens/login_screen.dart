import 'dart:math' as math;

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
      'assets/brand/rpa_logo.png',
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
      body: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth < 900 ? _movil(context) : _escritorio(context),
      ),
    );
  }

  /// Celular: portada negra arriba, cinta verde de marcas cruzada y el
  /// formulario debajo, en blanco.
  // Alto de la pantalla SIN el teclado. Al abrirse el teclado el alto
  // disponible baja (en el navegador del celular hasta la ventana se
  // achica); si el diseño se armara con ese alto cambiaría de estructura,
  // el campo que se está escribiendo se volvería a crear y perdería el foco:
  // el teclado se cerraba solo. Se recalcula si cambia el ancho (girar).
  double _altoSinTeclado = 0;
  double _anchoMedido = 0;

  Widget _movil(BuildContext context) {
    final relleno = MediaQuery.paddingOf(context);
    final formulario = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: EdgeInsets.fromLTRB(28, 46, 28, 18 + relleno.bottom),
          child: _formulario(context),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final alto =
            constraints.maxHeight + MediaQuery.viewInsetsOf(context).bottom;
        if (constraints.maxWidth != _anchoMedido) {
          _anchoMedido = constraints.maxWidth;
          _altoSinTeclado = alto;
        } else if (alto > _altoSinTeclado) {
          _altoSinTeclado = alto;
        }
        // Pantalla muy baja (celular acostado): la portada tiene alto fijo
        // y se desplaza. Si no, todo entra sin bajar: el formulario mide lo
        // que necesita y la portada toma el resto. Con el teclado abierto,
        // el contenido se desplaza para dejar a la vista el campo activo.
        final bajo = _altoSinTeclado < 620;
        return SingleChildScrollView(
          child: SizedBox(
            height: bajo ? null : _altoSinTeclado,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: bajo ? MainAxisSize.min : MainAxisSize.max,
              children: [
                if (bajo)
                  SizedBox(
                    height: 300 + relleno.top,
                    child: _portadaConCinta(relleno.top),
                  )
                else
                  Expanded(child: _portadaConCinta(relleno.top)),
                formulario,
              ],
            ),
          ),
        );
      },
    );
  }

  /// La portada negra con la cinta verde montada sobre su borde inferior
  /// (la mitad de la cinta cae sobre el blanco del formulario).
  Widget _portadaConCinta(double arriba) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: _Portada(margenSuperior: arriba + 36, reservaInferior: 44),
        ),
        const Positioned(
          left: -40,
          right: -40,
          bottom: -24,
          child: _CintaMarcas(),
        ),
      ],
    );
  }

  /// Computadora: la portada negra ocupa la izquierda (con la cinta
  /// cruzándola) y el formulario va a la derecha.
  Widget _escritorio(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 11,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                const Positioned.fill(
                  child: _Portada(margenSuperior: 72, escala: 1.35),
                ),
                Positioned(
                  left: -60,
                  right: -60,
                  bottom: constraints.maxHeight * 0.14,
                  child: const _CintaMarcas(),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 9,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: _formulario(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _cambiarModo() => setState(() {
    _modoRegistro = !_modoRegistro;
    _error = null;
  });

  Widget _formulario(BuildContext context) {
    final registro = _modoRegistro;
    final accion = _enviando ? null : _enviar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          registro ? 'Crea tu cuenta' : 'Ingresa a tu cuenta',
          style: Ipesa.titulo(26, color: Colors.black),
        ),
        if (registro) ...[
          const SizedBox(height: 6),
          const Text(
            'Tu cuenta se crea como transportista.',
            style: TextStyle(fontSize: 15, color: Ipesa.textoSuave),
          ),
        ],
        const SizedBox(height: 20),
        const _EtiquetaLinea('NOMBRE'),
        TextField(
          controller: _nombreController,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(fontSize: 18, color: Colors.black),
          decoration: _decoracionLinea(pista: 'Juan Pérez'),
          onSubmitted: (_) => _enviar(),
        ),
        const SizedBox(height: 18),
        const _EtiquetaLinea('PIN'),
        TextField(
          controller: _pinController,
          obscureText: !_verPin,
          keyboardType: TextInputType.number,
          style: const TextStyle(
            fontSize: 18,
            letterSpacing: 4,
            color: Colors.black,
          ),
          decoration: _decoracionLinea(
            pista: '••••',
            ayuda: registro
                ? 'Elige un PIN: lo usarás para volver a entrar.'
                : null,
            sufijo: IconButton(
              tooltip: _verPin ? 'Ocultar PIN' : 'Mostrar PIN',
              icon: Icon(
                _verPin ? Icons.visibility_off : Icons.visibility,
                color: Ipesa.textoSuave,
              ),
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
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: accion,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  minimumSize: const Size(0, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _enviando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(registro ? 'Crear cuenta' : 'Ingresar'),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 56,
              height: 56,
              child: IconButton.filled(
                tooltip: registro ? 'Crear cuenta' : 'Ingresar',
                onPressed: accion,
                style: IconButton.styleFrom(
                  backgroundColor: _verdeIpesa,
                  disabledBackgroundColor: _verdeIpesa.withValues(alpha: .5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.arrow_forward, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              registro ? '¿Ya tienes cuenta? ' : '¿Transportista nuevo? ',
              style: const TextStyle(fontSize: 15, color: Ipesa.textoSuave),
            ),
            TextButton(
              onPressed: _enviando ? null : _cambiarModo,
              style: TextButton.styleFrom(
                foregroundColor: _verdeIpesa,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 44),
                textStyle: const TextStyle(
                  fontFamily: Ipesa.fuenteTexto,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
              child: Text(registro ? 'Ingresa' : 'Crea tu cuenta'),
            ),
          ],
        ),
      ],
    );
  }

  static InputDecoration _decoracionLinea({
    required String pista,
    String? ayuda,
    Widget? sufijo,
  }) {
    const linea = UnderlineInputBorder(
      borderSide: BorderSide(color: Color(0xFF111111), width: 2),
    );
    return InputDecoration(
      hintText: pista,
      helperText: ayuda,
      suffixIcon: sufijo,
      filled: false,
      isDense: true,
      contentPadding: const EdgeInsets.fromLTRB(2, 10, 2, 12),
      border: linea,
      enabledBorder: linea,
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: _verdeIpesa, width: 2.5),
      ),
    );
  }
}

/// Verde de IPESA (el del botón "Cotiza" de ipesa.com.pe, oscurecido para
/// que el texto blanco encima se lea bien).
const _verdeIpesa = Color(0xFF0E7A3A);

class _EtiquetaLinea extends StatelessWidget {
  const _EtiquetaLinea(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
        color: Ipesa.textoSuave,
      ),
    );
  }
}

/// Portada negra: "IPESA" gigante en contorno de fondo, el logo, y una
/// línea que dice para qué es la app. [escala] la agranda en computadora.
class _Portada extends StatelessWidget {
  const _Portada({
    required this.margenSuperior,
    this.escala = 1,
    this.reservaInferior = 0,
  });

  final double margenSuperior;
  final double escala;

  /// Alto libre al pie (donde pasa la cinta verde): el contenido no lo usa.
  final double reservaInferior;

  // Alto (aprox.) de cada parte, para acomodar la portada al espacio.
  static const _altoEtiqueta = 40.0;
  static const _proporcionLogo = 98 / 331;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          _dibujar(constraints.maxHeight - margenSuperior - reservaInferior),
    );
  }

  Widget _dibujar(double disponible) {
    final altoFrase = 2 * 17 * 1.45 * (escala > 1 ? 1.15 : 1);
    var anchoLogo = 220 * escala;
    var conFrase = true;
    double resto() =>
        _altoEtiqueta +
        anchoLogo * _proporcionLogo +
        (conFrase ? 18 + altoFrase : 0);
    // Primero se achica el espacio entre la etiqueta y el logo; si igual
    // no entra, se quita la frase y, en último caso, se achica el logo.
    if (disponible - resto() < 12) conFrase = false;
    if (disponible - resto() < 12) {
      anchoLogo = ((disponible - _altoEtiqueta - 12) / _proporcionLogo).clamp(
        120.0,
        anchoLogo,
      );
    }
    final espacio = (disponible - resto()).clamp(12.0, 62 * escala);

    return ColoredBox(
      color: Colors.black,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: -18 * escala,
              top: margenSuperior - 30,
              child: ExcludeSemantics(
                child: Text(
                  'IPESA\nIPESA\nIPESA',
                  softWrap: false,
                  style: TextStyle(
                    fontFamily: Ipesa.fuenteTitulos,
                    fontSize: 150 * escala,
                    fontWeight: FontWeight.w800,
                    height: 0.92,
                    letterSpacing: -4,
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 1.5
                      ..color = const Color(0x2EFFFFFF),
                  ),
                ),
              ),
            ),
            // Anclado solo arriba: si en una pantalla muy baja no entrara,
            // se recorta abajo (ClipRect) en vez de desbordarse.
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  28 * escala,
                  margenSuperior,
                  28,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // El nombre de la app: RPA, con su logo (la IA y la
                    // ruta) y lo que significa la sigla.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/brand/rpa_logo.png',
                          width: 40,
                          height: 40,
                          excludeFromSemantics: true,
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'RPA',
                                style: TextStyle(
                                  fontFamily: Ipesa.fuenteTitulos,
                                  color: Colors.white,
                                  fontSize: 20,
                                  height: 1.05,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2,
                                ),
                              ),
                              const Text(
                                'REGISTRO DE PEDIDOS ATENDIDOS',
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: TextStyle(
                                  color: Color(0xFFC9CFCD),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: espacio),
                    Image.asset(
                      'assets/brand/ipesa_blanco.png',
                      width: anchoLogo,
                      semanticLabel: 'IPESA',
                    ),
                    if (conFrase) const SizedBox(height: 18),
                    if (conFrase)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 300 * escala),
                        child: Text(
                          'La IA lo vio, el cliente lo firmó.',
                          style: TextStyle(
                            fontSize: 17 * (escala > 1 ? 1.15 : 1),
                            height: 1.45,
                            color: const Color(0xFFC9CFCD),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cinta verde inclinada con las marcas que representa IPESA avanzando.
class _CintaMarcas extends StatelessWidget {
  const _CintaMarcas();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -4 * math.pi / 180,
      child: Container(
        height: 62,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: _verdeIpesa,
          boxShadow: [
            BoxShadow(
              color: Color(0x38000000),
              blurRadius: 26,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: const CarruselMarcas(
          alto: 40,
          ancho: 100,
          separacion: 12,
          pixelesPorSegundo: 34,
          bordeTarjeta: Colors.transparent,
          difuminar: false,
        ),
      ),
    );
  }
}
