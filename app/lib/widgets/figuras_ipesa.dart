import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Las figuras del menú del administrador: cada sección es una placa con
/// degradé, brillo y sombra, con un dibujo blanco encima (y un toque del
/// naranja de la marca). Se pintan en código, así que no pesan nada y se
/// ven nítidas en cualquier pantalla.
enum Figura {
  dashboard,
  guias,
  transportistas,
  recorrido,
  sucursales,
  rastrear,
}

/// Acento cálido común a todas las figuras.
const _acento = Color(0xFFF59E4A);
const _llanta = Color(0xFF17262B);

extension on Figura {
  /// Claro (arriba a la izquierda) y oscuro (abajo a la derecha).
  (Color, Color) get placa => switch (this) {
    Figura.dashboard => (const Color(0xFFFFC07A), const Color(0xFFE0762A)),
    Figura.guias => (const Color(0xFF5B9BEA), const Color(0xFF2459A8)),
    Figura.transportistas => (const Color(0xFF45C7BA), const Color(0xFF148078)),
    Figura.recorrido => (const Color(0xFFA48BEA), const Color(0xFF5B45A8)),
    Figura.sucursales => (const Color(0xFF52C28A), const Color(0xFF1D6B41)),
    Figura.rastrear => (const Color(0xFF86A3AE), const Color(0xFF3A5864)),
  };
}

class FiguraIpesa extends StatelessWidget {
  const FiguraIpesa(this.figura, {super.key, this.tamano = 40});

  final Figura figura;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(tamano),
        painter: _PintorFigura(figura),
      ),
    );
  }
}

class _PintorFigura extends CustomPainter {
  _PintorFigura(this.figura);

  final Figura figura;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final (claro, oscuro) = figura.placa;
    final placa = RRect.fromRectAndRadius(
      Offset.zero & Size.square(s),
      Radius.circular(s * 0.28),
    );

    // Sombra bajo la placa.
    canvas.drawRRect(
      placa.shift(Offset(0, s * 0.06)),
      Paint()
        ..color = oscuro.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.07),
    );
    // Cuerpo con degradé.
    canvas.drawRRect(
      placa,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [claro, oscuro],
        ).createShader(placa.outerRect),
    );
    // Brillo en la mitad de arriba.
    canvas.save();
    canvas.clipRRect(placa);
    canvas.drawOval(
      Rect.fromLTWH(-s * 0.25, -s * 0.62, s * 1.5, s * 1.05),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.34),
            Colors.white.withValues(alpha: 0.04),
          ],
        ).createShader(Rect.fromLTWH(0, 0, s, s * 0.45)),
    );
    canvas.restore();
    // Filo interior.
    canvas.drawRRect(
      placa.deflate(s * 0.012),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.024
        ..color = Colors.white.withValues(alpha: 0.28),
    );

    // El dibujo, en una grilla de 24 × 24.
    final escala = s * 0.64 / 24;
    canvas.save();
    canvas.translate(s * 0.18, s * 0.18);
    canvas.scale(escala);
    _Dibujo(canvas, oscuro).pintar(figura);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PintorFigura old) => old.figura != figura;
}

/// Pinta cada dibujo en coordenadas de 0 a 24.
class _Dibujo {
  _Dibujo(this.c, this.oscuro);

  final Canvas c;
  final Color oscuro;

  static const _blanco = Colors.white;
  static final _blancoSuave = Colors.white.withValues(alpha: 0.72);

  Paint relleno(Color color) => Paint()
    ..color = color
    ..isAntiAlias = true;

  Paint trazo(Color color, double ancho) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = ancho
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// Sombra corta bajo la silueta, para que el dibujo se despegue.
  void sombra(Path silueta) {
    c.drawPath(
      silueta.shift(const Offset(0, 1.1)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.9),
    );
  }

  void pintar(Figura figura) {
    switch (figura) {
      case Figura.dashboard:
        _dashboard();
      case Figura.guias:
        _guias();
      case Figura.transportistas:
        _transportistas();
      case Figura.recorrido:
        _recorrido();
      case Figura.sucursales:
        _sucursales();
      case Figura.rastrear:
        _rastrear();
    }
  }

  /// Un velocímetro: el pulso de la operación.
  void _dashboard() {
    const centro = Offset(12, 15);
    final arco = Rect.fromCircle(center: centro, radius: 9);
    final silueta = Path()..addArc(arco.inflate(1.8), math.pi, math.pi);
    sombra(silueta);
    c.drawArc(
      arco,
      math.pi,
      math.pi,
      false,
      trazo(Colors.black.withValues(alpha: 0.2), 3.4),
    );
    c.drawArc(arco, math.pi, math.pi * 0.68, false, trazo(_blanco, 3.4));
    // Marcas.
    for (var i = 0; i <= 4; i++) {
      final a = math.pi + math.pi * i / 4;
      final dentro = centro + Offset(math.cos(a), math.sin(a)) * 5.2;
      final fuera = centro + Offset(math.cos(a), math.sin(a)) * 6.4;
      c.drawLine(dentro, fuera, trazo(_blancoSuave, 1));
    }
    // Aguja.
    const angulo = math.pi * 1.68;
    final punta = centro + Offset(math.cos(angulo), math.sin(angulo)) * 7;
    c.drawLine(centro, punta, trazo(_llanta, 2.2));
    c.drawCircle(centro, 2.4, relleno(_blanco));
    c.drawCircle(centro, 1, relleno(_llanta));
    // Base.
    c.drawRRect(
      RRect.fromLTRBR(4, 19.4, 20, 21.6, const Radius.circular(1.1)),
      relleno(_blanco),
    );
  }

  /// Una guía con la esquina doblada y un visto de entregada.
  void _guias() {
    final hoja = Path()
      ..moveTo(6, 2.5)
      ..lineTo(13.2, 2.5)
      ..lineTo(18.5, 7.8)
      ..lineTo(18.5, 19.8)
      ..quadraticBezierTo(18.5, 21.5, 16.8, 21.5)
      ..lineTo(6, 21.5)
      ..quadraticBezierTo(4.3, 21.5, 4.3, 19.8)
      ..lineTo(4.3, 4.2)
      ..quadraticBezierTo(4.3, 2.5, 6, 2.5)
      ..close();
    sombra(hoja);
    c.drawPath(hoja, relleno(_blanco));
    c.drawPath(
      Path()
        ..moveTo(13.2, 2.5)
        ..lineTo(13.2, 6.6)
        ..quadraticBezierTo(13.2, 7.8, 14.4, 7.8)
        ..lineTo(18.5, 7.8)
        ..close(),
      relleno(Colors.black.withValues(alpha: 0.16)),
    );
    final linea = trazo(oscuro, 1.6);
    c.drawLine(const Offset(7.4, 11), const Offset(15.4, 11), linea);
    c.drawLine(const Offset(7.4, 14.4), const Offset(12.6, 14.4), linea);
    c.drawLine(const Offset(7.4, 17.8), const Offset(10.6, 17.8), linea);
    // Sello de entregada.
    c.drawCircle(const Offset(17.4, 17.6), 5.2, relleno(_blanco));
    c.drawCircle(const Offset(17.4, 17.6), 4.1, relleno(_acento));
    c.drawPath(
      Path()
        ..moveTo(15.4, 17.7)
        ..lineTo(16.8, 19.1)
        ..lineTo(19.5, 16.2),
      trazo(_blanco, 1.5),
    );
  }

  /// Un camión con la franja de la marca.
  void _transportistas() {
    final caja = RRect.fromLTRBR(
      1.2,
      5.2,
      14.6,
      16.8,
      const Radius.circular(1.6),
    );
    final cabina = Path()
      ..moveTo(15.6, 8.6)
      ..lineTo(19.4, 8.6)
      ..quadraticBezierTo(20.2, 8.6, 20.7, 9.3)
      ..lineTo(22.6, 12.2)
      ..quadraticBezierTo(22.9, 12.7, 22.9, 13.3)
      ..lineTo(22.9, 15.8)
      ..quadraticBezierTo(22.9, 16.8, 21.9, 16.8)
      ..lineTo(15.6, 16.8)
      ..close();
    sombra(
      Path()
        ..addRRect(caja)
        ..addPath(cabina, Offset.zero),
    );
    c.drawRRect(caja, relleno(_blanco));
    c.drawRect(const Rect.fromLTRB(1.2, 12.4, 14.6, 14.2), relleno(_acento));
    c.drawPath(cabina, relleno(_blancoSuave));
    c.drawPath(
      Path()
        ..moveTo(16.9, 10)
        ..lineTo(19.1, 10)
        ..lineTo(21, 12.9)
        ..lineTo(16.9, 12.9)
        ..close(),
      relleno(oscuro),
    );
    for (final x in [5.8, 18.6]) {
      c.drawCircle(Offset(x, 18), 3, relleno(_blanco));
      c.drawCircle(Offset(x, 18), 2.2, relleno(_llanta));
      c.drawCircle(Offset(x, 18), 0.9, relleno(_blanco));
    }
  }

  /// Una ruta punteada del punto de partida al pin de destino.
  void _recorrido() {
    final ruta = Path()
      ..moveTo(5, 18.6)
      ..cubicTo(5, 11, 18, 17, 17.6, 9.5);
    final punteado = Path();
    for (final m in ruta.computeMetrics()) {
      for (double d = 0; d < m.length; d += 3.4) {
        punteado.addPath(m.extractPath(d, d + 1.8), Offset.zero);
      }
    }
    c.drawPath(punteado, trazo(_blancoSuave, 1.9));
    // Partida.
    c.drawCircle(const Offset(5, 18.6), 3, relleno(_blanco));
    c.drawCircle(const Offset(5, 18.6), 1.3, relleno(oscuro));
    // Destino.
    final pin = Path()
      ..moveTo(17.6, 14.2)
      ..cubicTo(15.4, 11.6, 13, 9.2, 13, 6.8)
      ..arcToPoint(const Offset(22.2, 6.8), radius: const Radius.circular(4.6))
      ..cubicTo(22.2, 9.2, 19.8, 11.6, 17.6, 14.2)
      ..close();
    sombra(pin);
    c.drawPath(pin, relleno(_blanco));
    c.drawCircle(const Offset(17.6, 6.8), 2, relleno(_acento));
  }

  /// Una tienda con su toldo a rayas.
  void _sucursales() {
    final cuerpo = RRect.fromLTRBAndCorners(
      4.6,
      9.4,
      19.4,
      20.6,
      bottomLeft: const Radius.circular(1.2),
      bottomRight: const Radius.circular(1.2),
    );
    sombra(
      Path()
        ..addRRect(cuerpo)
        ..addRect(const Rect.fromLTRB(3, 3.4, 21, 10)),
    );
    c.drawRRect(cuerpo, relleno(_blancoSuave));
    // Puerta y ventana.
    c.drawRRect(
      RRect.fromLTRBAndCorners(
        10.2,
        13.4,
        14.4,
        20.6,
        topLeft: const Radius.circular(1.6),
        topRight: const Radius.circular(1.6),
      ),
      relleno(oscuro),
    );
    c.drawRRect(
      RRect.fromLTRBR(15.6, 13, 18, 16, const Radius.circular(0.6)),
      relleno(oscuro),
    );
    c.drawRRect(
      RRect.fromLTRBR(6, 13, 8.4, 16, const Radius.circular(0.6)),
      relleno(oscuro),
    );
    // Toldo: cuatro gajos alternados.
    const ancho = 18 / 4;
    for (var i = 0; i < 4; i++) {
      final x = 3 + i * ancho;
      final gajo = Path()
        ..moveTo(x, 3.4)
        ..lineTo(x + ancho, 3.4)
        ..lineTo(x + ancho, 8)
        ..arcToPoint(Offset(x, 8), radius: const Radius.circular(ancho / 2))
        ..close();
      c.drawPath(gajo, relleno(i.isEven ? _blanco : _acento));
    }
    c.drawLine(
      const Offset(2.6, 20.8),
      const Offset(21.4, 20.8),
      trazo(_blanco, 1.6),
    );
  }

  /// Una lupa sobre un paquete.
  void _rastrear() {
    final caja = RRect.fromLTRBR(
      2.4,
      3.2,
      14.2,
      15,
      const Radius.circular(1.6),
    );
    sombra(Path()..addRRect(caja));
    c.drawRRect(caja, relleno(_blancoSuave));
    c.drawRect(const Rect.fromLTRB(7.3, 3.2, 9.3, 9), relleno(_acento));
    const centro = Offset(14.2, 13.2);
    sombra(Path()..addOval(Rect.fromCircle(center: centro, radius: 6.4)));
    c.drawLine(
      const Offset(18.6, 17.6),
      const Offset(21.6, 20.6),
      trazo(_blanco, 3.4),
    );
    c.drawCircle(centro, 5.2, relleno(Colors.white.withValues(alpha: 0.3)));
    c.drawCircle(centro, 5.2, trazo(_blanco, 2.2));
    c.drawArc(
      Rect.fromCircle(center: centro, radius: 3.1),
      math.pi * 1.1,
      math.pi * 0.45,
      false,
      trazo(_blanco, 1.2),
    );
  }
}
