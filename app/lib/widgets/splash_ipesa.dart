import 'package:flutter/material.dart';

/// Fondo de la pantalla de carga: el negro del logo de IPESA. En web, la
/// que se ve es la de web/index.html (idéntica), que tapa a esta hasta que
/// la pantalla siguiente está lista.
const colorSplash = Color(0xFF000000);

/// Pantalla de carga estática: logo IPESA y el nombre de la app sobre
/// negro. Nada se mueve; se queda fija mientras cargan los datos.
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
            Container(
              width: 44,
              height: 3,
              margin: const EdgeInsets.only(top: 26, bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0E7A3A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'TRACKING DISTRIBUCIÓN',
              style: TextStyle(
                color: Color(0xFFC9CFCD),
                fontSize: 14,
                letterSpacing: 3.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
