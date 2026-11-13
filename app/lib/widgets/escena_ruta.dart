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
    required this.tinte,
    required this.pista,
    required this.nubes,
  });

  final MomentoDia momento;

  /// De arriba (el tope de la pantalla) a abajo (detrás del paisaje).
  final List<Color> cielo;

  /// El paisaje se dibuja con sus colores de día; al atardecer y de noche
  /// se le pone encima este tinte para oscurecerlo.
  final Color? tinte;
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
    tinte: null,
    pista: Color(0xFF1E272C),
    nubes: 1,
  );

  static const _tarde = PaletaEscena._(
    momento: MomentoDia.tarde,
    cielo: [Color(0xFF2A3170), Color(0xFF8E4A86), Color(0xFFEE8A5E)],
    tinte: Color(0x423B2A66),
    pista: Color(0xFF1A1A24),
    nubes: .55,
  );

  static const _noche = PaletaEscena._(
    momento: MomentoDia.noche,
    cielo: [Color(0xFF0A1238), Color(0xFF16276B), Color(0xFF2A4890)],
    tinte: Color(0x5C0A1238),
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

    // Paisaje del Perú: la sierra al fondo y, adelante, la costa con el mar
    // y el campo con la llama y la casita. Se dibuja con colores de día y,
    // según la hora, se oscurece con el tinte de la paleta.
    final tinte = p.tinte;
    if (tinte != null) {
      canvas.saveLayer(Rect.fromLTWH(0, 0, w, h - 40), Paint());
    }
    const periodo = 520.0;

    // Sierra (lenta).
    final despM = t * periodo;
    for (var x = -periodo; x < w + periodo; x += periodo) {
      final b = x - despM;
      _cerro(canvas, b + 120, suelo, 120, 60, _verdeLejos);
      _cerro(canvas, b + 330, suelo, 135, 112, _tierra, nieve: true);
      _cerro(canvas, b + 480, suelo, 90, 48, _verdeLejos);
    }

    // Bruma al pie de los cerros: los aleja.
    final bruma = Rect.fromLTWH(0, suelo - 40, w, 40);
    canvas.drawRect(
      bruma,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0x00E3F1EE), const Color(0x8CE3F1EE)],
        ).createShader(bruma),
    );

    // Costa y campo (más rápidos).
    final despC = (t * periodo * 2) % periodo;
    for (var x = -periodo; x < w + periodo; x += periodo) {
      _costaYCampo(canvas, x - despC, suelo, h - 40);
    }

    if (tinte != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h - 40),
        Paint()
          ..color = tinte
          ..blendMode = BlendMode.srcATop,
      );
      canvas.restore();
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
    // Color sólido (no transparente): así los círculos no se ven encimados.
    final blanco = Paint()..color = Color.lerp(p.medio, Colors.white, p.nubes)!;
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

  static const _tierra = [
    Color(0xFFE8B98A),
    Color(0xFFC58B5E),
    Color(0xFF8F5C3A),
  ];
  static const _verdeLejos = [
    Color(0xFFC9DCC0),
    Color(0xFF93B48A),
    Color(0xFF5F8A5A),
  ];

  /// Un cerro redondo con luz arriba a la izquierda; con [nieve], la cumbre
  /// nevada.
  void _cerro(
    Canvas canvas,
    double cx,
    double base,
    double rx,
    double ry,
    List<Color> colores, {
    bool nieve = false,
  }) {
    final camino = Path()
      ..moveTo(cx - rx, base)
      ..cubicTo(
        cx - rx * .6,
        base - ry * .55,
        cx - rx * .3,
        base - ry,
        cx,
        base - ry,
      )
      ..cubicTo(
        cx + rx * .3,
        base - ry,
        cx + rx * .6,
        base - ry * .55,
        cx + rx,
        base,
      )
      ..close();
    final caja = Rect.fromLTRB(cx - rx, base - ry, cx + rx, base);
    canvas.drawPath(
      camino,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.3, -.5),
          radius: 1.3 * rx / ry,
          colors: colores,
          stops: const [0, .6, 1],
        ).createShader(caja),
    );
    if (!nieve) return;
    canvas
      ..save()
      ..clipPath(camino)
      ..drawPath(
        Path()
          ..moveTo(cx - rx, base - ry * .74)
          ..quadraticBezierTo(
            cx - rx * .35,
            base - ry * .64,
            cx - rx * .15,
            base - ry * .76,
          )
          ..quadraticBezierTo(
            cx + rx * .02,
            base - ry * .86,
            cx + rx * .2,
            base - ry * .73,
          )
          ..quadraticBezierTo(
            cx + rx * .45,
            base - ry * .62,
            cx + rx,
            base - ry * .76,
          )
          ..lineTo(cx + rx, base - ry - 4)
          ..lineTo(cx - rx, base - ry - 4)
          ..close(),
        Paint()..color = const Color(0xFFF7FBFA),
      )
      ..restore();
  }

  /// Un tramo de [_PintorEscena.paint] que se repite: mar con velero, arena,
  /// palmeras, y el campo con pinos, árboles, la llama y la casita.
  void _costaYCampo(Canvas canvas, double b, double suelo, double piso) {
    // Mar con olas.
    final mar = Rect.fromLTWH(b, suelo - 18, 172, piso - suelo + 18);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        mar,
        topLeft: const Radius.circular(12),
        topRight: const Radius.circular(12),
      ),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3FA9E0), Color(0xFF1C6FB8)],
        ).createShader(mar),
    );
    final ola = Paint()
      ..color = Colors.white.withValues(alpha: .55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var i = 0; i < 2; i++) {
      final camino = Path()..moveTo(b + 8 + i * 9, suelo - 9 + i * 6);
      for (var k = 0; k < 7; k++) {
        camino.relativeQuadraticBezierTo(5, -3, 10, 0);
        camino.relativeQuadraticBezierTo(5, 3, 10, 0);
      }
      canvas.drawPath(camino, ola);
    }
    _velero(canvas, Offset(b + 62, suelo - 12));

    // Arena.
    final arena = Rect.fromLTWH(b - 20, suelo - 8, 240, piso - suelo + 8);
    canvas.drawPath(
      Path()
        ..moveTo(b - 20, piso)
        ..lineTo(b - 20, suelo + 4)
        ..quadraticBezierTo(b + 60, suelo - 6, b + 150, suelo - 2)
        ..quadraticBezierTo(b + 195, suelo, b + 220, piso)
        ..close(),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF6DFA8), Color(0xFFD9B675)],
        ).createShader(arena),
    );

    // Campo.
    final campo = Rect.fromLTWH(b + 150, suelo - 20, 380, piso - suelo + 20);
    canvas.drawPath(
      Path()
        ..moveTo(b + 150, piso)
        ..quadraticBezierTo(b + 200, suelo - 16, b + 270, suelo - 8)
        ..quadraticBezierTo(b + 360, suelo - 20, b + 440, suelo - 8)
        ..quadraticBezierTo(b + 495, suelo - 2, b + 530, piso)
        ..close(),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF9CCB6A), Color(0xFF6E9E45)],
        ).createShader(campo),
    );

    final base = suelo + 8;
    _palmera(canvas, Offset(b + 166, base), 50, -8);
    _palmera(canvas, Offset(b + 194, base + 1), 40, 10);
    _pinoEn(canvas, Offset(b + 234, base), 44);
    _arbolEn(canvas, Offset(b + 264, base), 12);
    _llama(canvas, Offset(b + 302, base));
    _pinoEn(canvas, Offset(b + 346, base - 2), 32);
    _casita(canvas, Offset(b + 400, base));
    _arbolEn(canvas, Offset(b + 450, base), 14);
    _pinoEn(canvas, Offset(b + 488, base), 46);
  }

  void _sombra(Canvas canvas, Offset centro, double ancho) {
    canvas.drawOval(
      Rect.fromCenter(center: centro, width: ancho, height: ancho * .18),
      Paint()
        ..color = const Color(0x4D0B3D24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  void _velero(Canvas canvas, Offset o) {
    canvas.drawPath(
      Path()
        ..moveTo(o.dx - 14, o.dy)
        ..lineTo(o.dx + 14, o.dy)
        ..lineTo(o.dx + 10, o.dy + 6)
        ..lineTo(o.dx - 10, o.dy + 6)
        ..close(),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromLTWH(o.dx - 13, o.dy, 26, 2.5),
      Paint()..color = const Color(0xFFE2453C),
    );
    canvas.drawRect(
      Rect.fromLTWH(o.dx - .8, o.dy - 26, 1.6, 26),
      Paint()..color = const Color(0xFF6B6B6B),
    );
    canvas.drawPath(
      Path()
        ..moveTo(o.dx + 1, o.dy - 25)
        ..lineTo(o.dx + 13, o.dy - 3)
        ..lineTo(o.dx + 1, o.dy - 3)
        ..close(),
      Paint()..color = Colors.white,
    );
    canvas.drawPath(
      Path()
        ..moveTo(o.dx - 1, o.dy - 20)
        ..lineTo(o.dx - 10, o.dy - 3)
        ..lineTo(o.dx - 1, o.dy - 3)
        ..close(),
      Paint()..color = const Color(0xFFE9EEF0),
    );
  }

  void _palmera(Canvas canvas, Offset base, double alto, double inclina) {
    final cima = Offset(base.dx + inclina, base.dy - alto);
    _sombra(canvas, base + const Offset(3, 0), 26);
    canvas.drawPath(
      Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(
          base.dx + inclina * .2,
          base.dy - alto * .6,
          cima.dx,
          cima.dy,
        ),
      Paint()
        ..color = const Color(0xFF9A6A3E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    final largo = alto * .8;
    for (final (angulo, color) in const [
      (-150.0, Color(0xFF3E9A3A)),
      (-30.0, Color(0xFF3E9A3A)),
      (-115.0, Color(0xFF6CC24A)),
      (10.0, Color(0xFF5CB847)),
      (-70.0, Color(0xFF7BD155)),
    ]) {
      canvas
        ..save()
        ..translate(cima.dx, cima.dy)
        ..rotate(angulo * math.pi / 180)
        ..drawOval(
          Rect.fromLTWH(-2, -largo * .12, largo, largo * .24),
          Paint()..color = color,
        )
        ..restore();
    }
    final coco = Paint()..color = const Color(0xFF6B4A2A);
    canvas.drawCircle(cima + const Offset(-1, 3), 2.6, coco);
    canvas.drawCircle(cima + const Offset(3, 3), 2.6, coco);
  }

  void _llama(Canvas canvas, Offset o) {
    _sombra(canvas, o + const Offset(2, 0), 30);
    final lana = Paint()..color = const Color(0xFFF7F3EC);
    final pata = Paint()..color = const Color(0xFFE2DACB);
    for (final x in const [-8.0, -4.0, 5.0, 9.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(o.dx + x, o.dy - 11, 2.6, 11),
          const Radius.circular(1.2),
        ),
        pata,
      );
    }
    canvas.drawOval(
      Rect.fromCenter(center: o + const Offset(0, -14), width: 24, height: 14),
      lana,
    );
    // La mantita de colores.
    for (final (y, alto, color) in const [
      (-21.0, 9.0, Color(0xFFE2453C)),
      (-17.0, 2.0, Color(0xFFF6C343)),
      (-14.0, 1.6, Color(0xFF2E9A5C)),
    ]) {
      canvas.drawRect(
        Rect.fromLTWH(o.dx - 6, o.dy + y, 11, alto),
        Paint()..color = color,
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(o.dx + 8, o.dy - 16)
        ..quadraticBezierTo(o.dx + 11, o.dy - 26, o.dx + 10, o.dy - 34)
        ..lineTo(o.dx + 15, o.dy - 34)
        ..quadraticBezierTo(o.dx + 16, o.dy - 24, o.dx + 13, o.dy - 15)
        ..close(),
      lana,
    );
    canvas.drawOval(
      Rect.fromCenter(center: o + const Offset(14, -35), width: 11, height: 7),
      lana,
    );
    canvas.drawPath(
      Path()
        ..moveTo(o.dx + 10, o.dy - 37)
        ..lineTo(o.dx + 9, o.dy - 43)
        ..lineTo(o.dx + 12, o.dy - 39)
        ..close()
        ..moveTo(o.dx + 13, o.dy - 38)
        ..lineTo(o.dx + 13, o.dy - 44)
        ..lineTo(o.dx + 15.5, o.dy - 39)
        ..close(),
      pata,
    );
    canvas.drawCircle(
      o + const Offset(15.5, -36),
      .9,
      Paint()..color = const Color(0xFF222222),
    );
  }

  void _casita(Canvas canvas, Offset o) {
    _sombra(canvas, o, 52);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(o.dx - 20, o.dy - 26, 40, 26),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFE8C48A),
    );
    canvas.drawPath(
      Path()
        ..moveTo(o.dx - 26, o.dy - 24)
        ..lineTo(o.dx, o.dy - 44)
        ..lineTo(o.dx + 26, o.dy - 24)
        ..close(),
      Paint()..color = const Color(0xFFB5532E),
    );
    canvas.drawPath(
      Path()
        ..moveTo(o.dx, o.dy - 44)
        ..lineTo(o.dx + 26, o.dy - 24)
        ..lineTo(o.dx + 20, o.dy - 24)
        ..lineTo(o.dx, o.dy - 40)
        ..close(),
      Paint()..color = const Color(0xFF8C3B1E),
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(o.dx - 5, o.dy - 15, 10, 15),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF7A4A2A),
    );
    final ventana = Paint()..color = const Color(0xFF8FC7E0);
    for (final x in const [-16.0, 9.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(o.dx + x, o.dy - 19, 7, 7),
          const Radius.circular(1.5),
        ),
        ventana,
      );
    }
  }

  void _pinoEn(Canvas canvas, Offset base, double alto) {
    _sombra(canvas, base + const Offset(3, 0), alto * .55);
    canvas.drawRect(
      Rect.fromLTWH(base.dx - 2.5, base.dy - 10, 5, 10),
      Paint()..color = const Color(0xFF7A5634),
    );
    const verde = Color(0xFF2E9A55);
    final hoja = Paint()..color = verde;
    final hojaSombra = Paint()..color = Color.lerp(verde, Colors.black, .32)!;
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
    _sombra(canvas, base + const Offset(3, 0), radio * 1.8);
    canvas.drawRect(
      Rect.fromLTWH(base.dx - 3, base.dy - 16, 6, 16),
      Paint()..color = const Color(0xFF7A5634),
    );
    final centro = Offset(base.dx, base.dy - 16 - radio * 0.8);
    canvas.drawCircle(
      centro,
      radio,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.35, -.4),
          colors: [Color(0xFF9BE07A), Color(0xFF4FAE3E), Color(0xFF21702A)],
          stops: [0, .6, 1],
        ).createShader(Rect.fromCircle(center: centro, radius: radio)),
    );
    canvas.drawCircle(
      centro - Offset(radio * .38, radio * .42),
      radio * .26,
      Paint()..color = Colors.white.withValues(alpha: .3),
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
