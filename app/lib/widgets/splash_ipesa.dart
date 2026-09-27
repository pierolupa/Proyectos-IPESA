import 'package:flutter/material.dart';

/// Fondo de la pantalla de carga: el negro del logo de IPESA. En web, la
/// que se ve es la de web/index.html (idéntica), que tapa a esta hasta que
/// la pantalla siguiente está lista.
const colorSplash = Color(0xFF000000);

/// Pantalla de carga: logo IPESA y el nombre de la app fijos sobre negro,
/// y debajo una barra de progreso que se va llenando mientras cargan los
/// datos (rápido al principio y cada vez más lento, sin llegar al final).
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
            const SizedBox(height: 26),
            const Text(
              'TRACKING DISTRIBUCIÓN',
              style: TextStyle(
                color: Color(0xFFC9CFCD),
                fontSize: 14,
                letterSpacing: 3.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: (ancho * 0.46).clamp(160.0, 220.0),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 0.92),
                duration: const Duration(seconds: 8),
                curve: const Cubic(.12, .7, .25, 1),
                builder: (context, avance, _) => LinearProgressIndicator(
                  value: avance,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                  color: const Color(0xFF0E7A3A),
                  backgroundColor: const Color(0x24FFFFFF),
                  semanticsLabel: 'Cargando',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
