import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'escena_ruta.dart';
import 'pasos_registro.dart';

const _verde = Color(0xFF17663D);
const _negro = Color(0xFF000000);
const _selloVerde = Color(0xFF1E6B4A);

/// Mientras el comercial busca en Rastrear: la pantalla se atenúa y al
/// frente una ventana con la marca IPESA, un mensaje y los pasos reales
/// de la búsqueda (solo iconos). Al terminar, la marca se vuelve un check.
class VentanaBusqueda extends StatelessWidget {
  const VentanaBusqueda({super.key, required this.pasos, required this.lista});

  final List<PasoRegistro> pasos;

  /// Ya terminó: se ve el check y "¡Listo!" un momento antes de abrir.
  final bool lista;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Bloquea los toques mientras busca.
        const ModalBarrier(dismissible: false),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: ColoredBox(color: cieloEscena.withValues(alpha: 0.72)),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x400F4C5C),
                      blurRadius: 40,
                      offset: Offset(0, 18),
                      spreadRadius: -12,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Marca(lista: lista),
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _Mensaje(
                          key: ValueKey(lista),
                          titulo: lista
                              ? '¡Listo! Encontramos tu guía'
                              : 'Estamos buscando tu solicitud',
                          detalle: lista
                              ? 'Abriéndola…'
                              : 'Esto toma solo unos segundos',
                        ),
                      ),
                      const SizedBox(height: 14),
                      PasosRegistro(pasos: pasos),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// El título con un reflejo que lo recorre.
class _Mensaje extends StatefulWidget {
  const _Mensaje({super.key, required this.titulo, required this.detalle});

  final String titulo;
  final String detalle;

  @override
  State<_Mensaje> createState() => _MensajeState();
}

class _MensajeState extends State<_Mensaje>
    with SingleTickerProviderStateMixin {
  late final _reflejo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _reflejo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _reflejo,
          builder: (context, child) => ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) {
              final x = -1.2 + 2.4 * _reflejo.value;
              return LinearGradient(
                begin: Alignment(x - 1.2, 0),
                end: Alignment(x + 1.2, 0),
                colors: const [
                  Ipesa.petroleo,
                  Ipesa.turquesa,
                  Color(0xFF5FB8AC),
                  Ipesa.turquesa,
                  Ipesa.petroleo,
                ],
              ).createShader(rect);
            },
            child: child,
          ),
          child: Text(
            widget.titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: Ipesa.fuenteTitulos,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.detalle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13.5, color: Ipesa.textoSuave),
        ),
      ],
    );
  }
}

/// El cuadro negro "IPESA" de la guía, con un anillo que gira y un brillo
/// que lo cruza. Al terminar se cambia por un check verde.
class _Marca extends StatefulWidget {
  const _Marca({required this.lista});

  final bool lista;

  @override
  State<_Marca> createState() => _MarcaState();
}

class _MarcaState extends State<_Marca> with SingleTickerProviderStateMixin {
  late final _giro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _giro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 84,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedOpacity(
            opacity: widget.lista ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            child: AnimatedBuilder(
              animation: _giro,
              builder: (context, _) => Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size.square(84),
                    painter: _Anillo(_giro.value),
                  ),
                  _Sello(brillo: (_giro.value * 1.4) % 1),
                ],
              ),
            ),
          ),
          AnimatedScale(
            scale: widget.lista ? 1 : 0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment(-0.3, -0.4),
                  colors: [Color(0xFF2E9E68), _verde],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x6617663D),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                    spreadRadius: -6,
                  ),
                ],
              ),
              child: const Icon(Icons.check, size: 34, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sello extends StatelessWidget {
  const _Sello({required this.brillo});

  /// 0 → 1: dónde va el reflejo que cruza el sello.
  final double brillo;

  @override
  Widget build(BuildContext context) {
    final x = -2.0 + 4.0 * brillo;
    return Container(
      width: 58,
      height: 58,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _negro,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 18,
            offset: Offset(0, 8),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Stack(
        children: [
          const Center(
            child: Text(
              'IPESA',
              style: TextStyle(
                fontFamily: Ipesa.fuenteTitulos,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(x - 0.35, -0.3),
                  end: Alignment(x + 0.35, 0.3),
                  colors: const [
                    Color(0x00FFFFFF),
                    Color(0x2EFFFFFF),
                    Color(0x00FFFFFF),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 4,
            child: ColoredBox(color: _selloVerde),
          ),
        ],
      ),
    );
  }
}

/// Un arco que gira alrededor del sello, de turquesa a transparente.
class _Anillo extends CustomPainter {
  _Anillo(this.vuelta);

  final double vuelta;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - 3,
    );
    final inicio = vuelta * 2 * math.pi;
    canvas.drawArc(
      rect,
      inicio,
      math.pi * 1.3,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 1.3,
          colors: const [Color(0x000F4C5C), Ipesa.turquesa],
          transform: GradientRotation(inicio),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_Anillo old) => old.vuelta != vuelta;
}
