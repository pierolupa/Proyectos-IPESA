import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

const _fondo = Color(0xFF0B1A1F);
const _oro = Color(0xFFF6B566);
const _oroOscuro = Color(0xFFE9A04C);

/// Frases que rotan día a día, para que no sea siempre la misma.
const frasesCelebracion = [
  'Entregaste todas tus guías de hoy. Eres muy eficiente: necesitamos más '
      'como tú.',
  'Ruta impecable. Gracias por tu compromiso, ¡sigue así!',
  '¡Otra jornada completa! Los clientes cuentan contigo.',
  'Todo entregado y a tiempo. Eres un ejemplo para el equipo.',
];

/// Felicitación de "jornada impecable" al entregar la última guía pendiente
/// del día. Se muestra una sola vez por día y por transportista: el
/// celular recuerda que ya salió.
class CelebracionJornada {
  CelebracionJornada._();

  /// Los tests la apagan: los rayos giran sin fin y `pumpAndSettle` no
  /// terminaría nunca.
  @visibleForTesting
  static bool animar = true;

  static String _clave(String nombre) => 'celebracion_${nombre.trim()}';

  static String _hoy(DateTime ahora) =>
      '${ahora.year}-${ahora.month}-${ahora.day}';

  /// Muestra la felicitación si hoy todavía no se mostró a [nombre].
  /// [navigator] es el de la app: la pantalla de entrega ya se cerró.
  static Future<void> mostrarSiCorresponde(
    NavigatorState navigator, {
    required String nombre,
    required int entregadasHoy,
    DateTime? ahora,
  }) async {
    final momento = ahora ?? DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_clave(nombre)) == _hoy(momento)) return;
      await prefs.setString(_clave(nombre), _hoy(momento));
    } catch (_) {
      // Sin almacenamiento se muestra igual (a lo más, otra vez).
    }
    if (!navigator.mounted) return;
    final dia = momento.difference(DateTime(2026)).inDays;
    await navigator.push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => _PantallaCelebracion(
          nombre: nombre.trim().split(RegExp(r'\s+')).first,
          entregadas: entregadasHoy,
          frase: frasesCelebracion[dia.abs() % frasesCelebracion.length],
        ),
        transitionsBuilder: (_, animacion, _, hijo) =>
            FadeTransition(opacity: animacion, child: hijo),
      ),
    );
  }
}

class _PantallaCelebracion extends StatefulWidget {
  const _PantallaCelebracion({
    required this.nombre,
    required this.entregadas,
    required this.frase,
  });

  final String nombre;
  final int entregadas;
  final String frase;

  @override
  State<_PantallaCelebracion> createState() => _PantallaCelebracionState();
}

class _PantallaCelebracionState extends State<_PantallaCelebracion>
    with TickerProviderStateMixin {
  /// Rayos girando y destellos (sin fin).
  late final _giro = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  /// Entrada: el trofeo sube y después aparecen el texto y el botón.
  late final _entrada = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final quieto =
        !CelebracionJornada.animar || MediaQuery.of(context).disableAnimations;
    if (quieto) {
      _giro.value = 0;
      _entrada.value = 1;
    } else {
      if (!_giro.isAnimating) _giro.repeat();
      if (_entrada.value == 0) _entrada.forward();
    }
  }

  @override
  void dispose() {
    _giro.dispose();
    _entrada.dispose();
    super.dispose();
  }

  Animation<double> _tramo(
    double desde,
    double hasta, [
    Curve c = Curves.easeOut,
  ]) => CurvedAnimation(
    parent: _entrada,
    curve: Interval(desde, hasta, curve: c),
  );

  @override
  Widget build(BuildContext context) {
    final trofeo = _tramo(0, 0.55, Curves.easeOutBack);
    final texto = _tramo(0.45, 0.8);
    final boton = _tramo(0.7, 1);
    return Material(
      color: _fondo,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final alto = c.maxHeight;
            final escena = math.min(alto * 0.5, 420.0);
            return Column(
              children: [
                SizedBox(
                  height: escena,
                  width: double.infinity,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_giro, _entrada]),
                    builder: (_, _) => CustomPaint(
                      painter: _EscenaTrofeo(
                        giro: _giro.value,
                        entrada: trofeo.value,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: FadeTransition(
                    opacity: texto,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.06),
                        end: Offset.zero,
                      ).animate(texto),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          children: [
                            const Text(
                              'JORNADA IMPECABLE',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                                color: _oro,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '¡Excelente trabajo, ${widget.nombre}!',
                              textAlign: TextAlign.center,
                              style: Ipesa.titulo(
                                32,
                                color: Colors.white,
                              ).copyWith(height: 1.12),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              widget.frase,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 17,
                                height: 1.45,
                                color: Color(0xFFC9D6DA),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              widget.entregadas == 1
                                  ? '1 guía entregada hoy'
                                  : '${widget.entregadas} guías entregadas hoy',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: ScaleTransition(
                    scale: Tween(begin: 0.9, end: 1.0).animate(boton),
                    child: FadeTransition(
                      opacity: boton,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _oro,
                            foregroundColor: _fondo,
                            minimumSize: const Size.fromHeight(54),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                              fontFamily: Ipesa.fuenteTexto,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('¡Sigo así!'),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Rayos de luz girando, halo dorado, el trofeo con la placa IPESA y
/// destellos. Dibujado en un lienzo de 390×420 centrado.
class _EscenaTrofeo extends CustomPainter {
  _EscenaTrofeo({required this.giro, required this.entrada});

  /// 0→1: una vuelta completa de los rayos.
  final double giro;

  /// 0→1: el trofeo sube y crece.
  final double entrada;

  @override
  void paint(Canvas canvas, Size size) {
    final escala = math.min(size.width / 390, size.height / 420);
    canvas.translate(
      (size.width - 390 * escala) / 2,
      (size.height - 420 * escala) / 2,
    );
    canvas.scale(escala);
    const centro = Offset(195, 230);

    // Rayos.
    canvas.save();
    canvas.translate(centro.dx, centro.dy);
    canvas.rotate(giro * 2 * math.pi);
    final rayo = Paint()..color = _oro.withValues(alpha: 0.10);
    for (var i = 0; i < 8; i++) {
      canvas.save();
      canvas.rotate(i * math.pi / 4);
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(-18, -320)
          ..lineTo(18, -320)
          ..close(),
        rayo,
      );
      canvas.restore();
    }
    canvas.restore();

    // Halo.
    canvas.drawCircle(
      centro,
      150,
      Paint()
        ..shader = RadialGradient(
          colors: [_oro.withValues(alpha: 0.5), _oro.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: centro, radius: 150)),
    );

    // Destellos que titilan.
    final brillo = (math.sin(giro * 2 * math.pi * 10) + 1) / 2;
    for (final (x, y, r, fase) in [
      (110.0, 130.0, 9.0, 0.0),
      (290.0, 110.0, 9.0, 0.5),
      (300.0, 270.0, 6.0, 0.25),
      (90.0, 280.0, 6.0, 0.75),
    ]) {
      final a = 0.25 + 0.75 * ((brillo + fase) % 1.0);
      _estrella(
        canvas,
        Offset(x, y),
        r,
        Paint()..color = Colors.white.withValues(alpha: a),
      );
    }

    // Trofeo: sube desde abajo y crece.
    final t = entrada.clamp(0.0, 1.2);
    canvas.save();
    canvas.translate(0, (1 - t) * 40);
    canvas.translate(centro.dx, centro.dy);
    final s = 0.6 + 0.4 * t;
    canvas.scale(s);
    canvas.translate(-centro.dx, -centro.dy);
    final oro = Paint()..color = _oro;
    final asa = Paint()
      ..color = _oro
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    // Copa.
    canvas.drawPath(
      Path()
        ..moveTo(150, 150)
        ..lineTo(240, 150)
        ..lineTo(240, 190)
        ..arcToPoint(const Offset(150, 190), radius: const Radius.circular(45))
        ..close(),
      oro,
    );
    // Asas.
    canvas.drawPath(
      Path()
        ..moveTo(150, 160)
        ..lineTo(128, 160)
        ..arcToPoint(
          const Offset(150, 198),
          radius: const Radius.circular(22),
          clockwise: false,
        ),
      asa,
    );
    canvas.drawPath(
      Path()
        ..moveTo(240, 160)
        ..lineTo(262, 160)
        ..arcToPoint(const Offset(240, 198), radius: const Radius.circular(22)),
      asa,
    );
    // Pie y base.
    canvas.drawRect(
      const Rect.fromLTWH(186, 232, 18, 30),
      Paint()..color = _oroOscuro,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(164, 262, 62, 16),
        const Radius.circular(3),
      ),
      Paint()..color = _oroOscuro,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(154, 278, 82, 20),
        const Radius.circular(4),
      ),
      Paint()..color = Ipesa.turquesa,
    );
    final placa = TextPainter(
      text: const TextSpan(
        text: 'IPESA',
        style: TextStyle(
          fontFamily: Ipesa.fuenteTexto,
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    placa.paint(canvas, Offset(195 - placa.width / 2, 288 - placa.height / 2));
    // Estrella de la copa.
    _estrella(
      canvas,
      const Offset(195, 180),
      14,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
      puntas: 5,
    );
    canvas.restore();
  }

  /// Estrella de [puntas] puntas (4 = destello).
  void _estrella(
    Canvas canvas,
    Offset c,
    double r,
    Paint paint, {
    int puntas = 4,
  }) {
    final interior = puntas == 4 ? r * 0.3 : r * 0.45;
    final path = Path();
    for (var i = 0; i < puntas * 2; i++) {
      final radio = i.isEven ? r : interior;
      final ang = -math.pi / 2 + i * math.pi / puntas;
      final p = c + Offset(math.cos(ang) * radio, math.sin(ang) * radio);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), paint);
  }

  @override
  bool shouldRepaint(_EscenaTrofeo old) =>
      old.giro != giro || old.entrada != entrada;
}
