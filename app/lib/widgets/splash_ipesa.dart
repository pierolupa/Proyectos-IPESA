import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Fondo de la pantalla de carga: el negro del logo de IPESA.
const colorSplash = Color(0xFF000000);

/// Pantalla de carga: logo IPESA, "CARGANDO DATOS" y una ruedita.
///
/// En web se muestra SOLO la de web/index.html, que tapa a esta hasta que
/// la pantalla siguiente está lista: aquí queda el fondo negro, sin logo,
/// para que nunca se vean dos logos superpuestos (el HTML y Flutter no
/// quedan al mismo píxel). En celular nativo se dibuja completa.
class SplashIpesa extends StatelessWidget {
  const SplashIpesa({super.key});

  /// En web no dibuja nada encima del negro (ver arriba). Los tests la
  /// dibujan completa.
  @visibleForTesting
  static bool soloFondo = kIsWeb;

  /// Los tests la apagan: una animación sin fin haría que `pumpAndSettle`
  /// no termine nunca.
  @visibleForTesting
  static bool animar = true;

  @override
  Widget build(BuildContext context) {
    if (soloFondo) return const Scaffold(backgroundColor: colorSplash);
    final ancho = MediaQuery.sizeOf(context).width;
    final anchoLogo = (ancho * 0.52).clamp(160.0, 260.0);
    return Scaffold(
      backgroundColor: colorSplash,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/brand/ipesa_blanco.png',
              width: anchoLogo,
              semanticLabel: 'IPESA',
            ),
            const SizedBox(height: 34),
            const Text(
              'CARGANDO DATOS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 30),
            SizedBox.square(
              dimension: 30,
              child: CircularProgressIndicator(
                value: animar ? null : 0.25,
                strokeWidth: 3,
                color: Colors.white,
                backgroundColor: const Color(0x38FFFFFF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
