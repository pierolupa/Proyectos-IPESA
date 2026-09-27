import 'package:flutter/material.dart';

/// Fondo de la pantalla de inicio: el negro del logo de IPESA. El mismo
/// color y logo están en web/index.html, que se ve mientras carga la app,
/// para que el paso de uno a otro no se note.
const colorSplash = Color(0xFF000000);

/// Pantalla de inicio: logo IPESA sobre negro, "CARGANDO DATOS" y un
/// indicador de carga. El logo entra con un fundido suave.
class SplashIpesa extends StatelessWidget {
  const SplashIpesa({super.key});

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final anchoLogo = (ancho * 0.52).clamp(160.0, 260.0);
    return Scaffold(
      backgroundColor: colorSplash,
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, t, hijo) => Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.92 + 0.08 * t, child: hijo),
          ),
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
      ),
    );
  }
}
