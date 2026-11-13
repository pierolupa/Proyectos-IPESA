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

/// Las sucursales con las que trabaja IPESA, por región. En cada vuelta
/// el camión del paisaje para en una de cada región, en este orden.
const _sucursalesPorRegion = [
  // Costa.
  [
    'Almacen Barranca',
    'Almacen Chiclayo',
    'Almacen Chocope',
    'Almacen Ica',
    'Almacen Piura',
    'Almacen Viru',
    'Tienda TR Tacna',
    'Tienda TR Trujillo',
  ],
  // Lima.
  [
    'Almacen Ate',
    'Almacen Lurin',
    'Almacen Santa Clara',
    'Tienda TR Callao',
    'Tienda TR Los Olivos',
    'Tienda TR Lurin Kio',
    'Tienda TR San Luis',
    'Tienda TR Santa Anita',
    'Tienda TR Santa Clara',
  ],
  // Sierra.
  [
    'Almacen Arequipa',
    'Almacen Cajamarca',
    'Almacen Cusco',
    'Almacen Huancayo',
    'Almacen Juliaca',
    'Tienda TR Arequipa',
    'Tienda TR Cusco',
    'Tienda TR Huancayo',
    'Tienda TR Juliaca',
  ],
  // Selva.
  [
    'Almacen Iquitos',
    'Almacen Pucallpa',
    'Almacen Tarapoto',
    'Tienda TR Nueva Cajamarca',
  ],
];

/// La sucursal de la [region] donde para el camión en la [vuelta]: cada
/// vuelta pasa a la siguiente de la lista, así no se repite hasta haber
/// pasado por todas (la vuelta inicial es al azar).
@visibleForTesting
String sucursalEnEscena(int vuelta, int region) {
  final lista = _sucursalesPorRegion[region];
  return lista[(vuelta + region * 3) % lista.length];
}

/// Lo que avanza el paisaje de adelante entre una sucursal y la siguiente.
const _tramo = 420.0;

/// La parte de cada tramo en que el camión maneja; el resto está parado
/// dejando el pedido.
const _manejo = .68;

/// Dónde va el camión en la vuelta [t] (de 0 a 1): los px que avanzó, si
/// está manejando, en qué tramo va y, si está parado, cuánto lleva de la
/// entrega (de 0 a 1).
({double avance, bool enMarcha, int parada, double entrega}) _recorrido(
  double t,
) {
  final n = _sucursalesPorRegion.length;
  final x = t * n;
  final i = x.floor().clamp(0, n - 1);
  final u = x - i;
  if (u < _manejo) {
    final k = Curves.easeInOut.transform(u / _manejo);
    return (avance: (i + k) * _tramo, enMarcha: true, parada: i, entrega: 0);
  }
  return (
    avance: (i + 1) * _tramo,
    enMarcha: false,
    parada: i,
    entrega: (u - _manejo) / (1 - _manejo),
  );
}

/// Paisaje animado al pie de la vista del comercial: cerros, árboles, nubes
/// y un avión pasan en capas (las cercanas más rápido) mientras un camión
/// IPESA recorre las sucursales. Con "reducir animaciones" queda quieto.
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
  )..addListener(_contarVuelta);

  /// Las vueltas que dio el camión; empieza al azar para que cada vez que
  /// se abre la pantalla salgan otras sucursales.
  int _vuelta = math.Random().nextInt(10000) + 1;
  double _ultimo = 0;

  void _contarVuelta() {
    if (_tiempo.value < _ultimo) _vuelta++;
    _ultimo = _tiempo.value;
  }

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
                final viaje = _recorrido(t);
                // Pequeño rebote del camión mientras maneja.
                final rebote = viaje.enMarcha
                    ? math.sin(t * 2 * math.pi * 36) * 1.2
                    : 0.0;
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _PintorEscena(t, paleta, _vuelta),
                      ),
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
                      child: _Camion(
                        giroRuedas:
                            viaje.avance /
                            (_tramo * _sucursalesPorRegion.length) *
                            2 *
                            math.pi *
                            30,
                      ),
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
  _PintorEscena(this.t, this.p, this.vuelta);

  /// Avance de 0 a 1 en cada vuelta de la animación.
  final double t;
  final PaletaEscena p;

  /// Qué vuelta da el camión: elige las sucursales del recorrido.
  final int vuelta;

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
    final xAvion = w + 80 - t * (w + 300);
    _avion(canvas, Offset(xAvion, 40));

    // Paisaje del Perú: el camión va por la costa y la sierra y se detiene
    // en cada sucursal a dejar un pedido. Se dibuja con colores de día y,
    // según la hora, se oscurece con el tinte de la paleta.
    final viaje = _recorrido(t);
    final d = viaje.avance;
    final tinte = p.tinte;
    if (tinte != null) {
      canvas.saveLayer(Rect.fromLTWH(0, 0, w, h - 40), Paint());
    }

    // Sierra al fondo (lenta).
    const periodoM = _tramo;
    final despM = (d * .25) % periodoM;
    for (var x = -periodoM; x < w + periodoM; x += periodoM) {
      final b = x - despM;
      _cerro(canvas, b + 80, suelo, 110, 56, _verdeLejos);
      _cerro(canvas, b + 400, suelo, 85, 46, _verdeLejos);
      _cerro(canvas, b + 260, suelo, 130, 110, _tierra, nieve: true);
    }

    // Bruma al pie de los cerros: los aleja.
    final bruma = Rect.fromLTWH(0, suelo - 50, w, 50);
    canvas.drawRect(
      bruma,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00E3F1EE), Color(0x99E3F1EE)],
        ).createShader(bruma),
    );

    // Cerros verdes con pinos chicos (velocidad media).
    const periodoH = _tramo;
    final despH = (d * .5) % periodoH;
    for (var x = -periodoH; x < w + periodoH; x += periodoH) {
      final b = x - despH;
      _cerro(canvas, b + 90, suelo + 2, 135, 54, _verdeCerro);
      _cerro(canvas, b + 310, suelo + 2, 150, 66, _verdeCerro);
      for (final (dx, alto) in const [
        (12.0, 29.0),
        (26.0, 36.0),
        (40.0, 26.0),
        (150.0, 31.0),
        (164.0, 38.0),
        (178.0, 29.0),
        (240.0, 26.0),
        (254.0, 34.0),
        (340.0, 36.0),
        (354.0, 29.0),
        (368.0, 41.0),
        (382.0, 31.0),
      ]) {
        _pinoEn(canvas, Offset(b + dx, suelo + 2), alto, lejos: true);
      }
    }

    // Adelante: el campo y las sucursales, que pasan al ritmo del camión.
    final pasto = Rect.fromLTWH(0, suelo - 4, w, h - 40 - suelo + 4);
    canvas.drawRect(
      pasto,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF9CCB6A), Color(0xFF6E9E45)],
        ).createShader(pasto),
    );
    final n = _sucursalesPorRegion.length;
    final largo = _tramo * n;
    // La sucursal queda justo detrás del camión cuando se detiene.
    final junto = (w - _Camion.ancho) / 2 - 44;
    // Sin módulo: en la última parada `d` vale justo `largo` y la sucursal
    // tiene que seguir siendo la de esta vuelta.
    final inicio = -d;
    final avisos = <Offset>[];
    // La vuelta anterior, la actual y la siguiente: así, al empezar otra
    // vuelta, la última sucursal sigue en su sitio.
    for (var c = -1; c <= 1; c++) {
      for (var i = 0; i < n; i++) {
        final a = inicio + c * largo + (i + 1) * _tramo + junto;
        if (a < -_tramo / 2 - 20 || a > w + _tramo / 2 + 20) continue;
        final parada = i == viaje.parada && !viaje.enMarcha;
        final entregada = c < 0 || (c == 0 && (i < viaje.parada || parada));
        _tramoSucursal(
          canvas,
          i,
          sucursalEnEscena(vuelta + c, i),
          a,
          suelo,
          h - 40,
          entregada,
          c == 0 && parada ? viaje.entrega : 1.0,
        );
        if (c == 0 && parada && viaje.entrega > .35) {
          avisos.add(Offset(a, suelo - 58));
        }
      }
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
    for (final aviso in avisos) {
      _entregado(canvas, aviso);
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
    final despL = d;
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

  /// Avión de pasajeros de costado, mirando a la izquierda: fuselaje con
  /// ventanas, cola petróleo, alas, turbina y la estela detrás.
  void _avion(Canvas canvas, Offset o) {
    canvas
      ..save()
      ..translate(o.dx, o.dy);
    // Estela.
    const estela = Rect.fromLTWH(74, -1, 110, 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(estela, const Radius.circular(1.5)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: .7 * p.nubes + .1),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(estela),
    );
    // Ala del otro lado (detrás del fuselaje).
    canvas.drawPath(
      Path()
        ..moveTo(30, 4)
        ..lineTo(43, -7)
        ..lineTo(48, -7)
        ..lineTo(41, 4)
        ..close(),
      Paint()..color = const Color(0xFF9FAFB6),
    );
    // Estabilizador de la cola.
    canvas.drawPath(
      Path()
        ..moveTo(60, 3)
        ..lineTo(76, 0)
        ..lineTo(78, 3)
        ..lineTo(63, 6)
        ..close(),
      Paint()..color = const Color(0xFF9FAFB6),
    );
    // Cola.
    canvas.drawPath(
      Path()
        ..moveTo(56, 1)
        ..lineTo(67, -15)
        ..lineTo(74, -15)
        ..lineTo(72, -1)
        ..close(),
      Paint()..color = Ipesa.petroleo,
    );
    // Fuselaje.
    const cuerpo = Rect.fromLTWH(0, 0, 74, 12);
    canvas.drawPath(
      Path()
        ..moveTo(0, 7)
        ..cubicTo(0, 2.5, 6, .5, 14, .5)
        ..lineTo(56, .5)
        ..quadraticBezierTo(65, .5, 74, -2.5)
        ..lineTo(73, 2.5)
        ..quadraticBezierTo(66, 11, 54, 12)
        ..lineTo(12, 12)
        ..cubicTo(5, 12, 0, 10, 0, 7)
        ..close(),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFE3E9EC), Color(0xFFAAB8BE)],
          stops: [0, .55, 1],
        ).createShader(cuerpo),
    );
    // Franja, cabina y ventanas.
    canvas.drawRect(
      const Rect.fromLTWH(10, 7.6, 50, 1.3),
      Paint()..color = Ipesa.petroleo.withValues(alpha: .85),
    );
    canvas.drawPath(
      Path()
        ..moveTo(3.2, 4.6)
        ..quadraticBezierTo(5, 2.4, 9, 2.2)
        ..lineTo(9, 4.6)
        ..close(),
      Paint()..color = const Color(0xFF2E4A57),
    );
    final ventana = Paint()..color = const Color(0xFF4A6470);
    for (var x = 15.0; x < 54; x += 3.6) {
      canvas.drawCircle(Offset(x, 4.4), .95, ventana);
    }
    // Ala de este lado y turbina.
    canvas.drawPath(
      Path()
        ..moveTo(25, 8)
        ..lineTo(45, 23)
        ..lineTo(51, 23)
        ..lineTo(41, 8)
        ..close(),
      Paint()..color = const Color(0xFFD3DCE0),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(29, 12.5, 13, 5.5),
        const Radius.circular(2.75),
      ),
      Paint()..color = const Color(0xFF8C9CA3),
    );
    canvas.drawOval(
      const Rect.fromLTWH(28.4, 12.7, 3, 5.1),
      Paint()..color = const Color(0xFF55656C),
    );
    // De noche, las luces de la punta del ala parpadean.
    if (p.oscuro && (t * 48).floor().isEven) {
      canvas.drawCircle(
        const Offset(49, 23),
        1.6,
        Paint()..color = const Color(0xFFFF5A5A),
      );
    }
    canvas.restore();
  }

  static const _verdeCerro = [
    Color(0xFFC3E2A8),
    Color(0xFF84BE6E),
    Color(0xFF4F8C4B),
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
          ..moveTo(cx - rx, base - ry * .76)
          ..quadraticBezierTo(
            cx - rx * .35,
            base - ry * .66,
            cx - rx * .15,
            base - ry * .78,
          )
          ..quadraticBezierTo(
            cx + rx * .02,
            base - ry * .88,
            cx + rx * .2,
            base - ry * .75,
          )
          ..quadraticBezierTo(
            cx + rx * .45,
            base - ry * .64,
            cx + rx,
            base - ry * .78,
          )
          ..lineTo(cx + rx, base - ry - 4)
          ..lineTo(cx - rx, base - ry - 4)
          ..close(),
        Paint()..color = const Color(0xFFF7FBFA),
      )
      ..restore();
  }

  static const _tierra = [
    Color(0xFFE8B98A),
    Color(0xFFC58B5E),
    Color(0xFF8F5C3A),
  ];
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

  static const _verdeLejos = [
    Color(0xFFC9DCC0),
    Color(0xFF93B48A),
    Color(0xFF5F8A5A),
  ];

  /// Un tramo del viaje: el paisaje de la [region] alrededor de la
  /// sucursal [nombre], que queda en [a]. Con [entregada], la caja ya está
  /// en la puerta; [cayendo] va de 0 a 1 mientras el pedido baja del camión.
  void _tramoSucursal(
    Canvas canvas,
    int region,
    String nombre,
    double a,
    double suelo,
    double piso,
    bool entregada,
    double cayendo,
  ) {
    final base = suelo + 8;
    void sucursal() {
      final letrero = nombre.toUpperCase().replaceFirst('ALMACEN', 'ALMACÉN');
      if (nombre.startsWith('Tienda')) {
        _tienda(canvas, Offset(a, base), letrero);
      } else {
        _almacen(canvas, Offset(a, base), letrero);
      }
    }

    switch (region) {
      case 0: // Costa: el mar con el velero y palmeras.
        _agua(canvas, a + 84, a + 214, suelo, piso);
        _pinoEn(canvas, Offset(a - 170, base), 55);
        _palmera(canvas, Offset(a - 120, base), 50, -8);
        sucursal();
        _palmera(canvas, Offset(a + 74, base + 1), 44, 8);
      case 1: // Lima: edificios al fondo y pinos.
        _edificios(canvas, a - 205, base);
        _edificios(canvas, a + 120, base);
        _pinoEn(canvas, Offset(a - 150, base + 1), 46);
        _pinoEn(canvas, Offset(a - 110, base), 66);
        sucursal();
        _pinoEn(canvas, Offset(a + 84, base), 52);
        _pinoEn(canvas, Offset(a + 186, base), 58);
      case 2: // Sierra: la llama y la casita.
        _pinoEn(canvas, Offset(a - 185, base), 56);
        _llama(canvas, Offset(a - 140, base));
        _pinoEn(canvas, Offset(a - 100, base), 44);
        sucursal();
        _casita(canvas, Offset(a + 92, base));
        _pinoEn(canvas, Offset(a + 145, base), 58);
        _pinoEn(canvas, Offset(a + 180, base + 1), 40);
      default: // Selva: el río y la vegetación tupida.
        _palmera(canvas, Offset(a - 188, base), 54, -6);
        _pinoEn(canvas, Offset(a - 160, base), 66, selva: true);
        _palmera(canvas, Offset(a - 128, base + 1), 46, 8);
        _pinoEn(canvas, Offset(a - 100, base), 52, selva: true);
        sucursal();
        _agua(canvas, a + 84, a + 190, suelo, piso, rio: true);
        _palmera(canvas, Offset(a + 76, base + 1), 50, 8);
        _pinoEn(canvas, Offset(a + 200, base), 62, selva: true);
    }
    if (entregada) {
      // El pedido sale de atrás del camión y cae junto a la puerta.
      final q = Curves.easeIn.transform((cayendo / .35).clamp(0.0, 1.0));
      _caja(
        canvas,
        Offset.lerp(Offset(a + 54, base - 24), Offset(a + 34, base), q)!,
      );
    }
  }

  /// El mar con un velero y arena; con [rio], un río de selva con orillas
  /// de tierra.
  void _agua(
    Canvas canvas,
    double desde,
    double hasta,
    double suelo,
    double piso, {
    bool rio = false,
  }) {
    final mar = Rect.fromLTRB(desde, suelo - 18, hasta, piso);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        mar,
        topLeft: const Radius.circular(12),
        topRight: const Radius.circular(12),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: rio
              ? const [Color(0xFF5FB3A6), Color(0xFF2F7466)]
              : const [Color(0xFF3FA9E0), Color(0xFF1C6FB8)],
        ).createShader(mar),
    );
    final ola = Paint()
      ..color = Colors.white.withValues(alpha: .55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var k = 0; k < 2; k++) {
      final camino = Path()..moveTo(desde + 8 + k * 9, suelo - 9 + k * 6);
      while (camino.getBounds().right < hasta - 22) {
        camino
          ..relativeQuadraticBezierTo(5, -3, 10, 0)
          ..relativeQuadraticBezierTo(5, 3, 10, 0);
      }
      canvas.drawPath(camino, ola);
    }
    if (!rio) _velero(canvas, Offset((desde + hasta) / 2 + 6, suelo - 12));
    // Arena delante del mar.
    final arena = Rect.fromLTRB(desde - 20, suelo - 8, hasta + 14, piso);
    canvas.drawPath(
      Path()
        ..moveTo(desde - 20, piso)
        ..quadraticBezierTo(desde, suelo - 2, desde + 40, suelo)
        ..quadraticBezierTo((desde + hasta) / 2, suelo - 6, hasta - 10, suelo)
        ..quadraticBezierTo(hasta + 6, suelo + 2, hasta + 14, piso)
        ..close(),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: rio
              ? const [Color(0xFFB9A26E), Color(0xFF8A7448)]
              : const [Color(0xFFF6DFA8), Color(0xFFD9B675)],
        ).createShader(arena),
    );
  }

  /// Tres edificios de ciudad, con ventanas, desde [x] hacia la derecha.
  void _edificios(Canvas canvas, double x, double base) {
    for (final (dx, ancho, alto, color) in const [
      (0.0, 26.0, 70.0, Color(0xFFC9D6DD)),
      (22.0, 30.0, 92.0, Color(0xFFB3C4CE)),
      (50.0, 24.0, 58.0, Color(0xFFD6E0E5)),
    ]) {
      final edificio = Rect.fromLTWH(x + dx, base - alto, ancho, alto);
      canvas.drawRect(edificio, Paint()..color = color);
      canvas.drawRect(
        Rect.fromLTWH(edificio.right - 4, edificio.top, 4, alto),
        Paint()..color = Colors.black.withValues(alpha: .08),
      );
      final ventana = Paint()..color = const Color(0xFF8FB8CC);
      for (var y = edificio.top + 6; y < base - 8; y += 9) {
        for (var vx = edificio.left + 4; vx < edificio.right - 8; vx += 7) {
          canvas.drawRect(Rect.fromLTWH(vx, y, 4, 5), ventana);
        }
      }
    }
  }

  static final _letreros = <String, TextPainter>{};

  /// El nombre de la sucursal, en blanco (se arma una sola vez).
  static TextPainter _letrero(String texto, {Color color = Colors.white}) =>
      _letreros.putIfAbsent(
        '$texto${color.toARGB32()}',
        () => TextPainter(
          text: TextSpan(
            text: texto,
            style: TextStyle(
              color: color,
              fontSize: 7.5,
              fontWeight: FontWeight.w800,
              letterSpacing: .3,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );

  void _letreroEn(Canvas canvas, Rect tabla, String nombre) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(tabla, const Radius.circular(2.5)),
      Paint()..color = Ipesa.petroleo,
    );
    final texto = _letrero(nombre);
    final escala = math.min(1.0, (tabla.width - 6) / texto.width);
    canvas
      ..save()
      ..translate(tabla.center.dx, tabla.center.dy)
      ..scale(escala);
    texto.paint(canvas, Offset(-texto.width / 2, -texto.height / 2));
    canvas.restore();
  }

  /// Almacén con volumen: techo y costado, portón enrollable y el letrero.
  void _almacen(Canvas canvas, Offset o, String nombre) {
    final x = o.dx;
    final y = o.dy;
    _sombra(canvas, Offset(x + 6, y), 116);
    // Costado (en sombra) y techo.
    canvas.drawPath(
      Path()
        ..moveTo(x + 50, y - 44)
        ..lineTo(x + 62, y - 53)
        ..lineTo(x + 62, y - 8)
        ..lineTo(x + 50, y)
        ..close(),
      Paint()..color = const Color(0xFFB7C3C8),
    );
    canvas.drawPath(
      Path()
        ..moveTo(x - 52, y - 44)
        ..lineTo(x - 40, y - 53)
        ..lineTo(x + 62, y - 53)
        ..lineTo(x + 50, y - 44)
        ..close(),
      Paint()..color = const Color(0xFF1B6C7F),
    );
    // Frente.
    final frente = Rect.fromLTRB(x - 52, y - 44, x + 50, y);
    canvas.drawRect(
      frente,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7F9FA), Color(0xFFD9E1E4)],
        ).createShader(frente),
    );
    canvas.drawRect(
      Rect.fromLTRB(x - 52, y - 44, x + 50, y - 42),
      Paint()..color = const Color(0xFF0F4C5C),
    );
    _letreroEn(canvas, Rect.fromLTRB(x - 47, y - 39, x + 45, y - 29), nombre);
    // Portón enrollable.
    final porton = Rect.fromLTRB(x - 20, y - 25, x + 18, y);
    canvas.drawRect(porton, Paint()..color = const Color(0xFFA3AFB4));
    final raya = Paint()..color = const Color(0xFF86949A);
    for (var k = porton.top + 3; k < porton.bottom; k += 3.5) {
      canvas.drawRect(Rect.fromLTRB(porton.left, k, porton.right, k + 1), raya);
    }
    // Ventanitas a los lados.
    final vidrio = Paint()..color = const Color(0xFF8FC7E0);
    for (final dx in const [-42.0, 28.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + dx, y - 22, 12, 8),
          const Radius.circular(1.5),
        ),
        vidrio,
      );
    }
  }

  /// Tienda con toldo a rayas, vitrina, puerta y el letrero.
  void _tienda(Canvas canvas, Offset o, String nombre) {
    final x = o.dx;
    final y = o.dy;
    _sombra(canvas, Offset(x + 5, y), 100);
    canvas.drawPath(
      Path()
        ..moveTo(x + 44, y - 46)
        ..lineTo(x + 54, y - 54)
        ..lineTo(x + 54, y - 8)
        ..lineTo(x + 44, y)
        ..close(),
      Paint()..color = const Color(0xFFD6C29E),
    );
    canvas.drawPath(
      Path()
        ..moveTo(x - 46, y - 46)
        ..lineTo(x - 36, y - 54)
        ..lineTo(x + 54, y - 54)
        ..lineTo(x + 44, y - 46)
        ..close(),
      Paint()..color = const Color(0xFF1B6C7F),
    );
    canvas.drawRect(
      Rect.fromLTRB(x - 46, y - 46, x + 44, y),
      Paint()..color = const Color(0xFFF6EBD6),
    );
    _letreroEn(canvas, Rect.fromLTRB(x - 42, y - 43, x + 40, y - 33), nombre);
    // Toldo a rayas.
    for (var k = 0; k < 9; k++) {
      canvas.drawPath(
        Path()
          ..moveTo(x - 46 + k * 10, y - 31)
          ..lineTo(x - 36 + k * 10, y - 31)
          ..lineTo(x - 36 + k * 10, y - 25)
          ..arcToPoint(
            Offset(x - 46 + k * 10, y - 25),
            radius: const Radius.circular(5),
          )
          ..close(),
        Paint()..color = k.isEven ? const Color(0xFF16A34A) : Colors.white,
      );
    }
    // Vitrina y puerta.
    canvas.drawRect(
      Rect.fromLTRB(x - 38, y - 19, x - 6, y - 4),
      Paint()..color = const Color(0xFF8FC7E0),
    );
    canvas.drawRect(
      Rect.fromLTRB(x + 6, y - 20, x + 22, y),
      Paint()..color = const Color(0xFF7A4A2A),
    );
    canvas.drawRect(
      Rect.fromLTRB(x + 9, y - 17, x + 19, y - 9),
      Paint()..color = const Color(0xFFB9DDEB),
    );
  }

  /// La caja del pedido, apoyada en [base] (el centro de abajo).
  void _caja(Canvas canvas, Offset base) {
    final caja = Rect.fromCenter(
      center: base - const Offset(0, 5),
      width: 13,
      height: 10,
    );
    _sombra(canvas, base + const Offset(1, 0), 16);
    canvas.drawRect(caja, Paint()..color = const Color(0xFFC8955C));
    canvas.drawRect(
      Rect.fromLTWH(caja.left, caja.top, caja.width, 2.5),
      Paint()..color = const Color(0xFFDDB07A),
    );
    canvas.drawRect(
      Rect.fromLTWH(caja.center.dx - 1, caja.top, 2, caja.height),
      Paint()..color = const Color(0xFFEAD3A6),
    );
  }

  /// Globito "Entregado" con el check, sobre la sucursal.
  void _entregado(Canvas canvas, Offset centro) {
    const verde = Color(0xFF15803D);
    final texto = _letrero('ENTREGADO', color: verde);
    final globo = Rect.fromCenter(
      center: centro,
      width: texto.width + 26,
      height: texto.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        globo.shift(const Offset(0, 1.5)),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0x33000000),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(globo, const Radius.circular(8)),
      Paint()..color = Colors.white,
    );
    final cy = globo.center.dy;
    canvas.drawPath(
      Path()
        ..moveTo(globo.left + 7, cy)
        ..lineTo(globo.left + 9.5, cy + 2.5)
        ..lineTo(globo.left + 14, cy - 2.5),
      Paint()
        ..color = verde
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    texto.paint(canvas, Offset(globo.left + 18, globo.top + 4));
  }

  /// Sombra sobre el pasto (sin desenfoque: son muchas por cuadro).
  void _sombra(Canvas canvas, Offset centro, double ancho) {
    canvas.drawOval(
      Rect.fromCenter(center: centro, width: ancho, height: ancho * .2),
      Paint()..color = const Color(0x400B3D24),
    );
  }

  /// Pino de tres pisos, mitad con luz y mitad en sombra. Los [lejos] son
  /// más claros (por la bruma) y sin sombra.
  void _pinoEn(
    Canvas canvas,
    Offset base,
    double alto, {
    bool lejos = false,
    bool selva = false,
  }) {
    if (!lejos) _sombra(canvas, base + const Offset(3, 0), alto * .55);
    canvas.drawRect(
      Rect.fromLTWH(
        base.dx - alto * .05,
        base.dy - alto * .2,
        alto * .1,
        alto * .2,
      ),
      Paint()..color = const Color(0xFF7A5634),
    );
    final verde = lejos
        ? const Color(0xFF4F9A68)
        : selva
        ? const Color(0xFF1F7A3E)
        : const Color(0xFF2E9A55);
    final hoja = Paint()..color = verde;
    final hojaSombra = Paint()..color = Color.lerp(verde, Colors.black, .32)!;
    for (var i = 0; i < 3; i++) {
      final y = base.dy - alto * .16 - i * alto * 0.28;
      final ancho = alto * (0.5 - i * 0.1);
      final cima = Offset(base.dx, y - alto * 0.42);
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

  @override
  bool shouldRepaint(_PintorEscena anterior) =>
      anterior.t != t ||
      anterior.vuelta != vuelta ||
      anterior.p.momento != p.momento;
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
