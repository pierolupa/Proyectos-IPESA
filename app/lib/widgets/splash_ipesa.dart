import 'package:flutter/material.dart';

/// Fondo de la pantalla de carga: el negro del logo de IPESA. En web, la
/// que se ve es la de web/index.html (idéntica), que tapa a esta hasta que
/// la pantalla siguiente está lista.
const colorSplash = Color(0xFF000000);

/// Pantalla de carga: logo IPESA sobre negro, "CARGANDO DATOS" y un
/// indicador. Aparece de frente, sin animación de entrada.
class SplashIpesa extends StatelessWidget {
  const SplashIpesa({super.key});

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: 36),
            const Text(
              'CARGANDO DATOS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 40),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
