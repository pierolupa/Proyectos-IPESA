import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Cielo de la escena de día, a la altura del paisaje.
const cieloEscena = Color(0xFFE3F1EE);

/// El momento del día que pinta el paisaje de Rastrear.
enum MomentoDia { dia, tarde, noche }

/// Día de 6:00 a 17:29, atardecer de 17:30 a 18:44 y noche el resto (hora
/// del celular, que en Perú es la de Lima).
MomentoDia momentoDelDia(DateTime hora) {
  final minuto = hora.hour * 60 + hora.minute;
  if (minuto >= 6 * 60 && minuto < 17 * 60 + 30) return MomentoDia.dia;
  if (minuto >= 17 * 60 + 30 && minuto < 18 * 60 + 45) {
    return MomentoDia.tarde;
  }
  return MomentoDia.noche;
}

/// Los colores del cielo y del paisaje para un momento del día.
class PaletaEscena {
  const PaletaEscena._({
    required this.momento,
    required this.cielo,
    required this.montana,
    required this.cerro,
    required this.pasto,
    required this.pino,
    required this.copa,
    required this.tronco,
    required this.nieve,
    required this.pista,
    required this.nubes,
  });

  final MomentoDia momento;

  /// De arriba (el tope de la pantalla) a abajo (detrás del paisaje).
  final List<Color> cielo;
  final Color montana;
  final Color cerro;
  final Color pasto;
  final Color pino;
  final Color copa;
  final Color tronco;
  final Color nieve;
  final Color pista;

  /// Cuánto se ven las nubes (de noche, casi nada).
  final double nubes;

  /// La hora del celular; los tests la fijan.
  @visibleForTesting
  static DateTime Function() reloj = DateTime.now;

  static PaletaEscena ahora() => de(momentoDelDia(reloj()));

  static PaletaEscena de(MomentoDia momento) => switch (momento) {
    MomentoDia.dia => _dia,
    MomentoDia.tarde => _tarde,
    MomentoDia.noche => _noche,
  };

  /// Al atardecer y de noche el cielo es oscuro: lo que va encima, claro.
  bool get oscuro => momento != MomentoDia.dia;

  /// Texto e íconos que van directo sobre el cielo.
  Color get texto => oscuro ? Colors.white : Ipesa.petroleo;
  Color get textoSuave => oscuro ? const Color(0xFFDCE6F2) : Ipesa.textoSuave;

  /// El cielo detrás del paisaje (el fondo de la pantalla).
  Color get fondo => cielo.last;

  /// El cielo a media pantalla.
  Color get medio => cielo[1];

  /// La línea del tiempo en la lista de resultados.
  Color get linea => oscuro ? const Color(0x59FFFFFF) : Ipesa.mentaBorde;

  static const _dia = PaletaEscena._(
    momento: MomentoDia.dia,
    cielo: [Color(0xFFA9D8EE), Color(0xFFD3ECEF), Color(0xFFE3F1EE)],
    montana: Color(0xFFA3D2C8),
    cerro: Color(0xFF74B8AA),
    pasto: Color(0xFFBFDCD3),
    pino: Color(0xFF0E7A3A),
    copa: Color(0xFF1B7F79),
    tronco: Color(0xFF6B4F3A),
    nieve: Colors.white,
    pista: Color(0xFF1E272C),
    nubes: 1,
  );

  static const _tarde = PaletaEscena._(
    momento: MomentoDia.tarde,
    cielo: [Color(0xFF2A3170), Color(0xFF8E4A86), Color(0xFFEE8A5E)],
    montana: Color(0xFF8C6A9E),
    cerro: Color(0xFF5A4A80),
    pasto: Color(0xFF52606A),
    pino: Color(0xFF1F5B4F),
    copa: Color(0xFF2D6B60),
    tronco: Color(0xFF3A2A22),
    nieve: Color(0xFFFFE2D0),
    pista: Color(0xFF1A1A24),
    nubes: .55,
  );

  static const _noche = PaletaEscena._(
    momento: MomentoDia.noche,
    cielo: [Color(0xFF0A1238), Color(0xFF16276B), Color(0xFF2A4890)],
    montana: Color(0xFF30478A),
    cerro: Color(0xFF1E3568),
    pasto: Color(0xFF233F58),
    pino: Color(0xFF12403F),
    copa: Color(0xFF1A4F4C),
    tronco: Color(0xFF1C1717),
    nieve: Color(0xFFCAD8F5),
    pista: Color(0xFF10141F),
    nubes: .15,
  );
}

/// El cielo de las pantallas de Rastrear: de arriba abajo, con el sol, el
/// sol bajando o la luna y las estrellas según la hora. Cambia solo cuando
/// pasa de un momento del día a otro. [EscenaRuta] y las pantallas toman
/// los colores con [FondoCielo.paletaDe].
class FondoCielo extends StatefulWidget {
  const FondoCielo({super.key, required this.child});

  final Widget child;

  /// La paleta del cielo que la contiene (o la de ahora, si no hay).
  static PaletaEscena paletaDe(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PaletaHeredada>()?.paleta ??
      PaletaEscena.ahora();

  @override
  State<FondoCielo> createState() => _FondoCieloState();
}

class _FondoCieloState extends State<FondoCielo> {
  PaletaEscena _paleta = PaletaEscena.ahora();
  late final Timer _reloj = Timer.periodic(const Duration(minutes: 1), (_) {
    final nueva = PaletaEscena.ahora();
    if (nueva.momento != _paleta.momento) setState(() => _paleta = nueva);
  });

  @override
  void initState() {
    super.initState();
    _reloj;
  }

  @override
  void dispose() {
    _reloj.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PaletaHeredada(
      paleta: _paleta,
      child: Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: CustomPaint(painter: _PintorCielo(_paleta)),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _PaletaHeredada extends InheritedWidget {
  const _PaletaHeredada({required this.paleta, required super.child});

  final PaletaEscena paleta;

  @override
  bool updateShouldNotify(_PaletaHeredada anterior) =>
      anterior.paleta.momento != paleta.momento;
}

class _PintorCielo extends CustomPainter {
  _PintorCielo(this.p);

  final PaletaEscena p;

  @override
  void paint(Canvas canvas, Size size) {
    final todo = Offset.zero & size;
    canvas.drawRect(
      todo,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: p.cielo,
        ).createShader(todo),
    );
    final w = size.width;
    final h = size.height;
    switch (p.momento) {
      case MomentoDia.noche:
        // Estrellas siempre en el mismo lugar (semilla fija).
        final azar = math.Random(7);
        final estrella = Paint();
        for (var i = 0; i < 110; i++) {
          final x = azar.nextDouble() * w;
          final y = azar.nextDouble() * h * .78;
          final r = .5 + azar.nextDouble() * 1.1;
          estrella.color = Colors.white.withValues(
            alpha: .3 + azar.nextDouble() * .7,
          );
          canvas.drawCircle(Offset(x, y), r, estrella);
        }
        _astro(
          canvas,
          Offset(w - 52, 112),
          17,
          const Color(0xFFF5F1DC),
          const Color(0xFFDDE6FF),
        );
        final crater = Paint()..color = const Color(0xFFDDD8BE);
        canvas.drawCircle(Offset(w - 58, 107), 3.4, crater);
        canvas.drawCircle(Offset(w - 46, 118), 2.5, crater);
        canvas.drawCircle(Offset(w - 48, 103), 1.6, crater);
      case MomentoDia.tarde:
        // El sol bajando, detrás de los cerros.
        _astro(
          canvas,
          Offset(w * .68, h - 150),
          30,
          const Color(0xFFFFE6A3),
          const Color(0xFFFFD27A),
        );
      case MomentoDia.dia:
        _astro(
          canvas,
          Offset(w - 52, 112),
          20,
          const Color(0xFFFFE27A),
          const Color(0xFFFFF1B8),
        );
    }
  }

  void _astro(Canvas canvas, Offset c, double r, Color color, Color halo) {
    canvas.drawCircle(
      c,
      r * 3.2,
      Paint()
        ..shader = RadialGradient(
          colors: [halo.withValues(alpha: .55), halo.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r * 3.2)),
    );
    canvas.drawCircle(c, r, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PintorCielo anterior) => anterior.p.momento != p.momento;
}

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
    final paleta = FondoCielo.paletaDe(context);
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
                      child: CustomPaint(painter: _PintorEscena(t, paleta)),
                    ),
                    // De noche, la luz de los faros sobre la pista.
                    if (paleta.momento == MomentoDia.noche)
                      Positioned(
                        left: (ancho + _Camion.ancho) / 2 - 6,
                        right: 0,
                        bottom: 14 + rebote,
                        height: 46,
                        child: const CustomPaint(painter: _PintorFaros()),
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

/// El haz de luz de los faros, que se abre y se apaga hacia adelante.
class _PintorFaros extends CustomPainter {
  const _PintorFaros();

  @override
  void paint(Canvas canvas, Size size) {
    final haz = Path()
      ..moveTo(0, size.height - 30)
      ..lineTo(size.width, size.height - 44)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height - 25)
      ..close();
    canvas.drawPath(
      haz,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xA6FFE9A0), Color(0x00FFE9A0)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_PintorFaros anterior) => false;
}

class _PintorEscena extends CustomPainter {
  _PintorEscena(this.t, this.p);

  /// Avance de 0 a 1 en cada vuelta de la animación.
  final double t;
  final PaletaEscena p;

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
    pintura.color = p.montana;
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
      // La cara de la derecha de cada cerro, en sombra: les da volumen.
      final sombra = Paint()
        ..color = Colors.black.withValues(alpha: p.oscuro ? .24 : .12);
      for (final (cima, sig) in [(picos[1], picos[2]), (picos[3], picos[4])]) {
        canvas.drawPath(
          Path()
            ..moveTo(cima.$1, suelo - cima.$2)
            ..lineTo(sig.$1, suelo - sig.$2)
            ..lineTo(sig.$1, suelo)
            ..lineTo(cima.$1 + 8, suelo)
            ..close(),
          sombra,
        );
      }
      final nieve = Paint()..color = p.nieve;
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

    // Bruma al pie de las montañas: las aleja.
    final bruma = Rect.fromLTWH(0, suelo - 56, w, 56);
    canvas.drawRect(
      bruma,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            p.fondo.withValues(alpha: 0),
            p.fondo.withValues(alpha: p.oscuro ? .35 : .55),
          ],
        ).createShader(bruma),
    );

    // Cerros cercanos, con luz arriba y sombra abajo.
    const periodoC = 220.0;
    final despC = t * periodoC * 2;
    final cerros = Rect.fromLTWH(0, suelo - 46, w, 46);
    pintura.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(p.cerro, Colors.white, p.oscuro ? .06 : .14)!,
        Color.lerp(p.cerro, Colors.black, .18)!,
      ],
    ).createShader(cerros);
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

    pintura.shader = null;

    // Pasto y árboles (más rápidos).
    pintura.color = p.pasto;
    canvas.drawRect(Rect.fromLTWH(0, suelo, w, 12), pintura);
    const periodoA = 150.0;
    final despA = t * periodoA * 6;
    for (var x = -periodoA; x < w + periodoA; x += periodoA) {
      final b = _envolver(x - despA, w + 2 * periodoA) - periodoA;
      _pinoEn(canvas, Offset(b + 18, suelo + 6), 46);
      _arbolEn(canvas, Offset(b + 70, suelo + 6), 17);
      _pinoEn(canvas, Offset(b + 112, suelo + 6), 34);
    }

    // Carretera (más clara al fondo) con las líneas del centro avanzando.
    final pista = Rect.fromLTWH(0, h - 40, w, 40);
    pintura.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color.lerp(p.pista, Colors.white, .14)!, p.pista],
    ).createShader(pista);
    canvas.drawRect(pista, pintura);
    pintura.shader = null;
    pintura.color = Colors.white.withValues(alpha: .22);
    canvas.drawRect(Rect.fromLTWH(0, h - 40, w, 2), pintura);
    // La sombra del camión sobre la pista.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2 + 4, h - 15),
        width: 186,
        height: 10,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: .38)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
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
    final blanco = Paint()..color = Colors.white.withValues(alpha: p.nubes);
    canvas.drawCircle(o + Offset(0, 8 * e), 14 * e, blanco);
    canvas.drawCircle(o + Offset(18 * e, 0), 18 * e, blanco);
    canvas.drawCircle(o + Offset(38 * e, 8 * e), 14 * e, blanco);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(o.dx - 8 * e, o.dy + 6 * e, 58 * e, 16 * e),
        Radius.circular(8 * e),
      ),
      blanco,
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
      Paint()..color = p.tronco,
    );
    final hoja = Paint()..color = p.pino;
    final hojaSombra = Paint()..color = Color.lerp(p.pino, Colors.black, .32)!;
    for (var i = 0; i < 3; i++) {
      final y = base.dy - 8 - i * alto * 0.28;
      final ancho = alto * (0.5 - i * 0.1);
      final cima = Offset(base.dx, y - alto * 0.42);
      // Mitad con luz y mitad en sombra.
      canvas.drawPath(
        Path()
          ..moveTo(base.dx - ancho / 2, y)
          ..lineTo(cima.dx, cima.dy)
          ..lineTo(base.dx, y)
          ..close(),
        hoja,
      );
      canvas.drawPath(
        Path()
          ..moveTo(base.dx, y)
          ..lineTo(cima.dx, cima.dy)
          ..lineTo(base.dx + ancho / 2, y)
          ..close(),
        hojaSombra,
      );
    }
  }

  void _arbolEn(Canvas canvas, Offset base, double radio) {
    canvas.drawRect(
      Rect.fromLTWH(base.dx - 3, base.dy - 16, 6, 16),
      Paint()..color = p.tronco,
    );
    final centro = Offset(base.dx, base.dy - 16 - radio * 0.8);
    canvas.drawCircle(
      centro,
      radio,
      Paint()..color = Color.lerp(p.copa, Colors.black, .28)!,
    );
    canvas.drawCircle(
      centro - Offset(radio * .2, radio * .18),
      radio * .8,
      Paint()..color = p.copa,
    );
    canvas.drawCircle(
      centro - Offset(radio * .38, radio * .42),
      radio * .28,
      Paint()..color = Colors.white.withValues(alpha: .16),
    );
  }

  @override
  bool shouldRepaint(_PintorEscena anterior) =>
      anterior.t != t || anterior.p.momento != p.momento;
}

/// Camión IPESA de costado, con volumen: la caja negra con el logo (con su
/// cara de arriba y la del costado), la cabina petróleo con reflejo en la
/// ventana y ruedas con aro. De noche, con el faro encendido.
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
          Positioned.fill(
            child: CustomPaint(painter: _PintorCamion(giroRuedas)),
          ),
          // El logo sobre el costado de la caja.
          Positioned(
            left: 0,
            top: 6,
            width: 118,
            height: 58,
            child: Center(
              child: Image.asset(
                'assets/brand/ipesa_blanco.png',
                width: 82,
                semanticLabel: 'IPESA',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PintorCamion extends CustomPainter {
  _PintorCamion(this.giro);

  final double giro;

  static Paint _degradado(Rect r, List<Color> colores) => Paint()
    ..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colores,
    ).createShader(r);

  @override
  void paint(Canvas canvas, Size size) {
    // Caja: costado con degradado, cara de arriba y cara de atrás.
    const costado = Rect.fromLTWH(0, 6, 118, 58);
    canvas.drawRRect(
      RRect.fromRectAndRadius(costado, const Radius.circular(4)),
      _degradado(costado, const [Color(0xFF34393C), Color(0xFF050505)]),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, 6)
        ..lineTo(8, 0)
        ..lineTo(126, 0)
        ..lineTo(118, 6)
        ..close(),
      Paint()..color = const Color(0xFF4A5054),
    );
    canvas.drawPath(
      Path()
        ..moveTo(118, 6)
        ..lineTo(126, 0)
        ..lineTo(126, 58)
        ..lineTo(118, 64)
        ..close(),
      Paint()..color = const Color(0xFF0B0D0E),
    );
    canvas.drawLine(
      const Offset(4, 10),
      const Offset(114, 10),
      Paint()
        ..color = Colors.white.withValues(alpha: .14)
        ..strokeWidth = 1,
    );
    // Franja verde y chasis.
    canvas.drawRect(
      const Rect.fromLTWH(0, 64, 124, 6),
      Paint()..color = const Color(0xFF0E7A3A),
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 64, 124, 1.5),
      Paint()..color = const Color(0xFF4ADE80).withValues(alpha: .6),
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 70, 172, 4),
      Paint()..color = const Color(0xFF15191B),
    );
    // Cabina.
    final cabina = Path()
      ..moveTo(128, 24)
      ..lineTo(150, 24)
      ..quadraticBezierTo(160, 24, 165, 32)
      ..lineTo(174, 50)
      ..lineTo(174, 72)
      ..lineTo(128, 72)
      ..close();
    canvas.drawPath(
      cabina,
      _degradado(const Rect.fromLTWH(128, 24, 46, 48), const [
        Color(0xFF1F8098),
        Ipesa.petroleo,
        Color(0xFF0A3644),
      ]),
    );
    // Ventana con reflejo.
    final ventana = Path()
      ..moveTo(134, 30)
      ..lineTo(151, 30)
      ..quadraticBezierTo(156, 30, 159, 36)
      ..lineTo(164, 46)
      ..lineTo(134, 46)
      ..close();
    canvas.drawPath(
      ventana,
      _degradado(const Rect.fromLTWH(134, 30, 30, 16), const [
        Color(0xFFDDF2F6),
        Color(0xFF9CCFDB),
      ]),
    );
    canvas.save();
    canvas.clipPath(ventana);
    canvas.drawPath(
      Path()
        ..moveTo(140, 30)
        ..lineTo(147, 30)
        ..lineTo(141, 46)
        ..lineTo(134, 46)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: .55),
    );
    canvas.restore();
    // Puerta, parachoques y faro.
    canvas.drawLine(
      const Offset(147, 50),
      const Offset(147, 70),
      Paint()
        ..color = Colors.black.withValues(alpha: .28)
        ..strokeWidth = 1.2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(166, 64, 10, 7),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFAEB8BC),
    );
    canvas.drawCircle(
      const Offset(171, 57),
      6,
      Paint()
        ..color = const Color(0xFFFFD54A).withValues(alpha: .35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      const Offset(171, 57),
      3,
      Paint()..color = const Color(0xFFFFD54A),
    );
    // Ruedas.
    for (final x in const [29.0, 89.0, 149.0]) {
      _rueda(canvas, Offset(x, 74));
    }
  }

  void _rueda(Canvas canvas, Offset c) {
    canvas.drawCircle(c, 13, Paint()..color = const Color(0xFF0C0F10));
    canvas.drawCircle(
      c,
      11.5,
      Paint()
        ..color = const Color(0xFF2A3033)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      c,
      6.5,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.35, -.35),
          colors: [Color(0xFFE6ECEE), Color(0xFF8A979B)],
        ).createShader(Rect.fromCircle(center: c, radius: 6.5)),
    );
    final rayo = Paint()
      ..color = const Color(0xFF5F6B6F)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final a = giro + i * 2 * math.pi / 5;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * 2.4,
        c + Offset(math.cos(a), math.sin(a)) * 5.6,
        rayo,
      );
    }
    canvas.drawCircle(c, 2.2, Paint()..color = const Color(0xFF4F5B5F));
  }

  @override
  bool shouldRepaint(_PintorCamion anterior) => anterior.giro != giro;
}
