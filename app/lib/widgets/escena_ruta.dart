import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Cielo de la escena (y fondo de la pantalla que la contiene).
const cieloEscena = Color(0xFFE3F1EE);

/// Paisaje animado al pie de la vista del comercial: cerros, árboles, nubes
/// y un avión pasan en capas (las cercanas más rápido) mientras un camión
/// IPESA avanza por la carretera. Con "reducir animaciones" queda quieto.
class EscenaRuta extends StatefulWidget {
  const EscenaRuta({super.key, this.alto = 210});

  final double alto;

  /// Los tests lo apagan (test/flutter_test_config.dart): una animación
  /// sin fin haría que `pumpAndSettle` no termine nunca.
  @visibleForTesting
  static bool animar = true;

  @override
  State<EscenaRuta> createState() => _EscenaRutaState();
}

class _EscenaRutaState extends State<EscenaRuta>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tiempo = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final quieto =
        !EscenaRuta.animar || MediaQuery.of(context).disableAnimations;
    if (quieto) {
      _tiempo.stop();
    } else if (!_tiempo.isAnimating) {
      _tiempo.repeat();
    }
  }

  @override
  void dispose() {
    _tiempo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: widget.alto,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ancho = constraints.maxWidth;
            return AnimatedBuilder(
              animation: _tiempo,
              builder: (context, _) {
                final t = _tiempo.value;
                // Pequeño rebote del camión, como si pasara por la pista.
                final rebote = math.sin(t * 2 * math.pi * 36) * 1.2;
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: _PintorEscena(t)),
                    ),
                    Positioned(
                      left: (ancho - _Camion.ancho) / 2,
                      bottom: 20 + rebote,
                      child: _Camion(giroRuedas: t * 2 * math.pi * 90),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _PintorEscena extends CustomPainter {
  _PintorEscena(this.t);

  /// Avance de 0 a 1 en cada vuelta de la animación.
  final double t;

  static const _montana = Color(0xFFA3D2C8);
  static const _cerro = Color(0xFF74B8AA);
  static const _pino = Color(0xFF0E7A3A);
  static const _copa = Color(0xFF1B7F79);
  static const _tronco = Color(0xFF6B4F3A);
  static const _pasto = Color(0xFFBFDCD3);
  static const _pista = Color(0xFF1E272C);

  /// Posición x que se desplaza a la izquierda y vuelve a entrar por la
  /// derecha, para capas que se repiten cada [periodo] px.
  static double _envolver(double x, double periodo) {
    final r = x % periodo;
    return r < 0 ? r + periodo : r;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final suelo = h - 52;
    final pintura = Paint()..isAntiAlias = true;

    // Nubes: lentas, cruzan la pantalla una vez por vuelta.
    final nubes = [(0.10, 26.0, 1.0), (0.42, 52.0, 0.8), (0.72, 18.0, 1.15)];
    for (final (x0, y, escala) in nubes) {
      final recorrido = w + 240;
      final x = _envolver(x0 * recorrido - t * recorrido, recorrido) - 120;
      _nube(canvas, Offset(x, y), escala);
    }

    // Avión: pasa una vez por vuelta, de derecha a izquierda.
    final xAvion = w + 80 - t * (w + 260);
    _avion(canvas, Offset(xAvion, 44));

    // Montañas lejanas (lentas) con nieve.
    const periodoM = 260.0;
    final despM = t * periodoM;
    pintura.color = _montana;
    for (var x = -periodoM; x < w + periodoM; x += periodoM) {
      final b = x - despM;
      final picos = [
        (b, 0.0),
        (b + 70, 88.0),
        (b + 130, 40.0),
        (b + 190, 104.0),
        (b + 260, 0.0),
      ];
      final camino = Path()..moveTo(b, suelo);
      for (final (px, alto) in picos) {
        camino.lineTo(px, suelo - alto);
      }
      camino
        ..lineTo(b + 260, suelo)
        ..close();
      canvas.drawPath(camino, pintura);
      final nieve = Paint()..color = Colors.white;
      canvas.drawPath(
        Path()
          ..moveTo(b + 172, suelo - 83)
          ..lineTo(b + 190, suelo - 104)
          ..lineTo(b + 208, suelo - 85)
          ..lineTo(b + 196, suelo - 90)
          ..lineTo(b + 188, suelo - 84)
          ..close(),
        nieve,
      );
      canvas.drawPath(
        Path()
          ..moveTo(b + 56, suelo - 72)
          ..lineTo(b + 70, suelo - 88)
          ..lineTo(b + 84, suelo - 74)
          ..lineTo(b + 70, suelo - 78)
          ..close(),
        nieve,
      );
    }

    // Cerros cercanos.
    const periodoC = 220.0;
    final despC = t * periodoC * 2;
    pintura.color = _cerro;
    for (var x = -periodoC; x < w + periodoC; x += periodoC) {
      final b = x - despC;
      canvas.drawPath(
        Path()
          ..moveTo(b, suelo)
          ..quadraticBezierTo(b + 55, suelo - 46, b + 110, suelo - 10)
          ..quadraticBezierTo(b + 165, suelo - 38, b + 220, suelo)
          ..close(),
        pintura,
      );
    }

    // Pasto y árboles (más rápidos).
    pintura.color = _pasto;
    canvas.drawRect(Rect.fromLTWH(0, suelo, w, 12), pintura);
    const periodoA = 150.0;
    final despA = t * periodoA * 6;
    for (var x = -periodoA; x < w + periodoA; x += periodoA) {
      final b = _envolver(x - despA, w + 2 * periodoA) - periodoA;
      _pinoEn(canvas, Offset(b + 18, suelo + 6), 46);
      _arbolEn(canvas, Offset(b + 70, suelo + 6), 17);
      _pinoEn(canvas, Offset(b + 112, suelo + 6), 34);
    }

    // Carretera con las líneas del centro avanzando.
    pintura.color = _pista;
    canvas.drawRect(Rect.fromLTWH(0, h - 40, w, 40), pintura);
    pintura.color = const Color(0xFF3A474E);
    canvas.drawRect(Rect.fromLTWH(0, h - 40, w, 3), pintura);
    const periodoL = 40.0;
    final despL = t * periodoL * 60;
    pintura.color = Colors.white.withValues(alpha: 0.85);
    for (var x = -periodoL; x < w + periodoL; x += periodoL) {
      final b = x - (despL % periodoL);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(b, h - 21, 22, 3),
          const Radius.circular(2),
        ),
        pintura,
      );
    }
  }

  void _nube(Canvas canvas, Offset o, double e) {
    final p = Paint()..color = Colors.white;
    canvas.drawCircle(o + Offset(0, 8 * e), 14 * e, p);
    canvas.drawCircle(o + Offset(18 * e, 0), 18 * e, p);
    canvas.drawCircle(o + Offset(38 * e, 8 * e), 14 * e, p);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(o.dx - 8 * e, o.dy + 6 * e, 58 * e, 16 * e),
        Radius.circular(8 * e),
      ),
      p,
    );
  }

  void _avion(Canvas canvas, Offset o) {
    final cuerpo = Paint()..color = const Color(0xFFB9C6CA);
    final sombra = Paint()..color = const Color(0xFF8FA1A7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(o.dx, o.dy, 56, 10),
        const Radius.circular(5),
      ),
      cuerpo,
    );
    canvas.drawPath(
      Path()
        ..moveTo(o.dx + 22, o.dy + 5)
        ..lineTo(o.dx + 36, o.dy + 18)
        ..lineTo(o.dx + 42, o.dy + 18)
        ..lineTo(o.dx + 34, o.dy + 5)
        ..close(),
      sombra,
    );
    canvas.drawPath(
      Path()
        ..moveTo(o.dx + 46, o.dy + 2)
        ..lineTo(o.dx + 56, o.dy - 8)
        ..lineTo(o.dx + 58, o.dy + 2)
        ..close(),
      sombra,
    );
    canvas.drawCircle(
      o + const Offset(6, 5),
      2,
      Paint()..color = Ipesa.petroleo,
    );
  }

  void _pinoEn(Canvas canvas, Offset base, double alto) {
    canvas.drawRect(
      Rect.fromLTWH(base.dx - 2.5, base.dy - 10, 5, 10),
      Paint()..color = _tronco,
    );
    final p = Paint()..color = _pino;
    for (var i = 0; i < 3; i++) {
      final y = base.dy - 8 - i * alto * 0.28;
      final ancho = alto * (0.5 - i * 0.1);
      canvas.drawPath(
        Path()
          ..moveTo(base.dx - ancho / 2, y)
          ..lineTo(base.dx, y - alto * 0.42)
          ..lineTo(base.dx + ancho / 2, y)
          ..close(),
        p,
      );
    }
  }

  void _arbolEn(Canvas canvas, Offset base, double radio) {
    canvas.drawRect(
      Rect.fromLTWH(base.dx - 3, base.dy - 16, 6, 16),
      Paint()..color = _tronco,
    );
    canvas.drawCircle(
      Offset(base.dx, base.dy - 16 - radio * 0.8),
      radio,
      Paint()..color = _copa,
    );
  }

  @override
  bool shouldRepaint(_PintorEscena anterior) => anterior.t != t;
}

/// Camión IPESA de costado: caja negra con el logo, cabina petróleo.
class _Camion extends StatelessWidget {
  const _Camion({required this.giroRuedas});

  final double giroRuedas;

  static const ancho = 176.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ancho,
      height: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Caja de carga.
          Positioned(
            left: 0,
            top: 0,
            width: 118,
            height: 64,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/brand/ipesa_blanco.png',
                width: 82,
                semanticLabel: 'IPESA',
              ),
            ),
          ),
          // Franja verde bajo la caja.
          Positioned(
            left: 0,
            top: 64,
            width: 124,
            height: 6,
            child: Container(color: const Color(0xFF0E7A3A)),
          ),
          // Cabina.
          Positioned(
            left: 122,
            top: 18,
            width: 50,
            height: 52,
            child: Container(
              decoration: const BoxDecoration(
                color: Ipesa.petroleo,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(6),
                ),
              ),
            ),
          ),
          // Ventana de la cabina.
          Positioned(
            left: 134,
            top: 25,
            width: 30,
            height: 18,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFBFE6DE),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(10),
                  topLeft: Radius.circular(3),
                  bottomLeft: Radius.circular(3),
                  bottomRight: Radius.circular(3),
                ),
              ),
            ),
          ),
          // Faro.
          Positioned(
            left: 166,
            top: 54,
            width: 8,
            height: 6,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF2C14E),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(left: 16, top: 60, child: _Rueda(giro: giroRuedas)),
          Positioned(left: 76, top: 60, child: _Rueda(giro: giroRuedas)),
          Positioned(left: 136, top: 60, child: _Rueda(giro: giroRuedas)),
        ],
      ),
    );
  }
}

class _Rueda extends StatelessWidget {
  const _Rueda({required this.giro});

  final double giro;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Transform.rotate(
        angle: giro,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: const Color(0xFFB9C6CA),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF6B7A80), width: 2),
          ),
          alignment: Alignment.topCenter,
          child: Container(width: 2, height: 5, color: const Color(0xFF6B7A80)),
        ),
      ),
    );
  }
}
