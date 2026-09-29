import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Las figuras del menú del administrador, en relieve: botones tallados en
/// el mismo petróleo de la barra, con luz arriba a la izquierda y sombra
/// abajo a la derecha. La sección activa se hunde y su dibujo pasa a
/// blanco. Se pintan en código, así que no pesan nada y se ven nítidas en
/// cualquier pantalla.
enum Figura {
  dashboard,
  guias,
  transportistas,
  recorrido,
  sucursales,
  rastrear,
}

const _petroleo = Color(0xFF0F4C5C);
const _llanta = Color(0xFF17262B);

class FiguraIpesa extends StatelessWidget {
  const FiguraIpesa(
    this.figura, {
    super.key,
    this.tamano = 44,
    this.activa = false,
  });

  final Figura figura;
  final double tamano;

  /// Hundida y con el dibujo en blanco.
  final bool activa;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(tamano),
        painter: _PintorFigura(figura, activa),
      ),
    );
  }
}

class _PintorFigura extends CustomPainter {
  _PintorFigura(this.figura, this.activa);

  final Figura figura;
  final bool activa;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final boton = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.06, s * 0.06, s * 0.88, s * 0.88),
      Radius.circular(s * 0.26),
    );
    final desenfoque = MaskFilter.blur(BlurStyle.normal, s * 0.045);

    if (activa) {
      // Hundido: más oscuro arriba a la izquierda, con un filo de sombra.
      canvas.drawRRect(
        boton,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF083743), Color(0xFF15596A)],
          ).createShader(boton.outerRect),
      );
      canvas.drawRRect(
        boton,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.03
          ..color = const Color(0x99062A33),
      );
    } else {
      // En relieve: sombra abajo a la derecha y luz arriba a la izquierda.
      canvas.drawRRect(
        boton.shift(Offset(s * 0.045, s * 0.045)),
        Paint()
          ..color = const Color(0xBF062A33)
          ..maskFilter = desenfoque,
      );
      canvas.drawRRect(
        boton.shift(Offset(-s * 0.045, -s * 0.045)),
        Paint()
          ..color = const Color(0xE61C6C7F)
          ..maskFilter = desenfoque,
      );
      canvas.drawRRect(boton, Paint()..color = _petroleo);
    }

    // El dibujo, en una grilla de 24 × 24.
    final escala = s * 0.5 / 24;
    canvas.save();
    canvas.translate(s * 0.25, s * 0.25);
    canvas.scale(escala);
    final dibujo = activa
        ? _Dibujo(
            canvas,
            principal: Colors.white,
            suave: Colors.white.withValues(alpha: 0.55),
            recorte: const Color(0xFF0B4150),
            acento: const Color(0xFFBFD9D5),
          )
        : _Dibujo(
            canvas,
            principal: const Color(0xFF9CC9C2),
            suave: const Color(0x8C9CC9C2),
            recorte: _petroleo,
            acento: const Color(0xFFDDEFEC),
          );
    dibujo.pintar(figura);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PintorFigura old) =>
      old.figura != figura || old.activa != activa;
}

/// Pinta cada dibujo en coordenadas de 0 a 24.
class _Dibujo {
  _Dibujo(
    this.c, {
    required this.principal,
    required this.suave,
    required this.recorte,
    required this.acento,
  });

  final Canvas c;
  final Color principal;
  final Color suave;

  /// Huecos del dibujo (ventanas, puerta, renglones).
  final Color recorte;
  final Color acento;

  Paint relleno(Color color) => Paint()
    ..color = color
    ..isAntiAlias = true;

  Paint trazo(Color color, double ancho) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = ancho
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

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
    c.drawArc(arco, math.pi, math.pi, false, trazo(suave, 3.4));
    c.drawArc(arco, math.pi, math.pi * 0.68, false, trazo(principal, 3.4));
    // Marcas.
    for (var i = 0; i <= 4; i++) {
      final a = math.pi + math.pi * i / 4;
      final dentro = centro + Offset(math.cos(a), math.sin(a)) * 5.2;
      final fuera = centro + Offset(math.cos(a), math.sin(a)) * 6.4;
      c.drawLine(dentro, fuera, trazo(suave, 1));
    }
    // Aguja.
    const angulo = math.pi * 1.68;
    final punta = centro + Offset(math.cos(angulo), math.sin(angulo)) * 7;
    c.drawLine(centro, punta, trazo(_llanta, 2.2));
    c.drawCircle(centro, 2.4, relleno(principal));
    c.drawCircle(centro, 1, relleno(_llanta));
    // Base.
    c.drawRRect(
      RRect.fromLTRBR(4, 19.4, 20, 21.6, const Radius.circular(1.1)),
      relleno(principal),
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
    c.drawPath(hoja, relleno(principal));
    c.drawPath(
      Path()
        ..moveTo(13.2, 2.5)
        ..lineTo(13.2, 6.6)
        ..quadraticBezierTo(13.2, 7.8, 14.4, 7.8)
        ..lineTo(18.5, 7.8)
        ..close(),
      relleno(Colors.black.withValues(alpha: 0.16)),
    );
    final linea = trazo(recorte, 1.6);
    c.drawLine(const Offset(7.4, 11), const Offset(15.4, 11), linea);
    c.drawLine(const Offset(7.4, 14.4), const Offset(12.6, 14.4), linea);
    c.drawLine(const Offset(7.4, 17.8), const Offset(10.6, 17.8), linea);
    // Sello de entregada.
    c.drawCircle(const Offset(17.4, 17.6), 5.2, relleno(principal));
    c.drawCircle(const Offset(17.4, 17.6), 4.1, relleno(acento));
    c.drawPath(
      Path()
        ..moveTo(15.4, 17.7)
        ..lineTo(16.8, 19.1)
        ..lineTo(19.5, 16.2),
      trazo(recorte, 1.5),
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
    c.drawRRect(caja, relleno(principal));
    c.drawRect(const Rect.fromLTRB(1.2, 12.4, 14.6, 14.2), relleno(acento));
    c.drawPath(cabina, relleno(suave));
    c.drawPath(
      Path()
        ..moveTo(16.9, 10)
        ..lineTo(19.1, 10)
        ..lineTo(21, 12.9)
        ..lineTo(16.9, 12.9)
        ..close(),
      relleno(recorte),
    );
    for (final x in [5.8, 18.6]) {
      c.drawCircle(Offset(x, 18), 3, relleno(principal));
      c.drawCircle(Offset(x, 18), 2.2, relleno(_llanta));
      c.drawCircle(Offset(x, 18), 0.9, relleno(principal));
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
    c.drawPath(punteado, trazo(suave, 1.9));
    // Partida.
    c.drawCircle(const Offset(5, 18.6), 3, relleno(principal));
    c.drawCircle(const Offset(5, 18.6), 1.3, relleno(recorte));
    // Destino.
    final pin = Path()
      ..moveTo(17.6, 14.2)
      ..cubicTo(15.4, 11.6, 13, 9.2, 13, 6.8)
      ..arcToPoint(const Offset(22.2, 6.8), radius: const Radius.circular(4.6))
      ..cubicTo(22.2, 9.2, 19.8, 11.6, 17.6, 14.2)
      ..close();
    c.drawPath(pin, relleno(principal));
    c.drawCircle(const Offset(17.6, 6.8), 2, relleno(acento));
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
    c.drawRRect(cuerpo, relleno(suave));
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
      relleno(recorte),
    );
    c.drawRRect(
      RRect.fromLTRBR(15.6, 13, 18, 16, const Radius.circular(0.6)),
      relleno(recorte),
    );
    c.drawRRect(
      RRect.fromLTRBR(6, 13, 8.4, 16, const Radius.circular(0.6)),
      relleno(recorte),
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
      c.drawPath(gajo, relleno(i.isEven ? principal : acento));
    }
    c.drawLine(
      const Offset(2.6, 20.8),
      const Offset(21.4, 20.8),
      trazo(principal, 1.6),
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
    c.drawRRect(caja, relleno(suave));
    c.drawRect(const Rect.fromLTRB(7.3, 3.2, 9.3, 9), relleno(acento));
    const centro = Offset(14.2, 13.2);
    c.drawLine(
      const Offset(18.6, 17.6),
      const Offset(21.6, 20.6),
      trazo(principal, 3.4),
    );
    c.drawCircle(centro, 5.2, relleno(Colors.white.withValues(alpha: 0.3)));
    c.drawCircle(centro, 5.2, trazo(principal, 2.2));
    c.drawArc(
      Rect.fromCircle(center: centro, radius: 3.1),
      math.pi * 1.1,
      math.pi * 0.45,
      false,
      trazo(principal, 1.2),
    );
  }
}
