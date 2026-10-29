import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

enum EstadoPaso { pendiente, activo, hecho, aviso }

/// Un paso del registro de una guía (Foto, Leída por IA, Verificada,
/// Registrada) y la hora en que se completó.
class PasoRegistro {
  const PasoRegistro(this.nombre, this.icono, this.estado, {this.hora});

  final String nombre;
  final IconData icono;
  final EstadoPaso estado;
  final DateTime? hora;
}

const _panel = Color(0xFFF3F6F5);
const _verde = Color(0xFF17663D);
const _verdeTinte = Color(0xFFE5F2EA);
const _petroleoTinte = Color(0xFFE7F0F1);
const _ambar = Color(0xFF9A5B00);
const _ambarFuerte = Color(0xFFC27C0E);
const _ambarTinte = Color(0xFFFDF3E1);
const _ambarBorde = Color(0xFFE3B866);
const _tenue = Color(0xFF98A6A9);
const _punteado = Color(0xFFC3CFCD);
const _borde = Color(0xFFDCE3E1);

const _duracion = Duration(milliseconds: 450);
final _hora = DateFormat('HH:mm');

/// Los pasos en un panel: cada uno con su icono, que gana un check al
/// completarse (o un "!" si falta algo), y la línea entre pasos que se
/// llena de verde. El paso en curso se rodea con un anillo que gira.
class PasosRegistro extends StatelessWidget {
  const PasosRegistro({super.key, required this.pasos});

  final List<PasoRegistro> pasos;

  String get _resumen => pasos
      .map(
        (p) =>
            '${p.nombre}: ${switch (p.estado) {
              EstadoPaso.pendiente => 'pendiente',
              EstadoPaso.activo => 'en curso',
              EstadoPaso.hecho => 'listo${p.hora == null ? '' : ' a las ${_hora.format(p.hora!)}'}',
              EstadoPaso.aviso => 'falta completar',
            }}',
      )
      .join('. ');

  @override
  Widget build(BuildContext context) {
    final n = pasos.length;
    return Semantics(
      label: _resumen,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            // Las uniones van de centro a centro, detrás de los círculos.
            Positioned(
              top: 17,
              left: 0,
              right: 0,
              child: FractionallySizedBox(
                widthFactor: (n - 1) / n,
                child: Row(
                  children: [
                    for (var i = 0; i < n - 1; i++)
                      Expanded(
                        child: _Union(
                          llena: pasos[i + 1].estado == EstadoPaso.hecho,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final p in pasos) Expanded(child: _Paso(p))],
            ),
          ],
        ),
      ),
    );
  }
}

class _Union extends StatelessWidget {
  const _Union({required this.llena});

  final bool llena;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: llena ? 1 : 0),
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeInOutCubic,
      builder: (context, t, _) =>
          CustomPaint(size: const Size.fromHeight(2), painter: _PintaUnion(t)),
    );
  }
}

class _PintaUnion extends CustomPainter {
  _PintaUnion(this.avance);

  final double avance;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final puntos = Paint()
      ..color = _punteado
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (double x = 1; x < size.width; x += 5) {
      canvas.drawLine(Offset(x, y), Offset(x + 0.1, y), puntos);
    }
    if (avance > 0) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width * avance, y),
        Paint()
          ..color = _verde
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_PintaUnion old) => old.avance != avance;
}

class _Paso extends StatelessWidget {
  const _Paso(this.paso);

  final PasoRegistro paso;

  @override
  Widget build(BuildContext context) {
    final e = paso.estado;
    final (fondo, color, borde) = switch (e) {
      EstadoPaso.pendiente => (Colors.white, _tenue, _borde),
      EstadoPaso.activo => (_petroleoTinte, Ipesa.petroleo, _petroleoTinte),
      EstadoPaso.hecho => (_verdeTinte, _verde, _verdeTinte),
      EstadoPaso.aviso => (_ambarTinte, _ambar, _ambarBorde),
    };
    final colorNombre = switch (e) {
      EstadoPaso.pendiente => _tenue,
      EstadoPaso.activo => Ipesa.petroleo,
      EstadoPaso.hecho => Ipesa.texto,
      EstadoPaso.aviso => _ambar,
    };
    final marcado = e == EstadoPaso.hecho || e == EstadoPaso.aviso;

    return Column(
      children: [
        SizedBox.square(
          dimension: 36,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: _duracion,
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: fondo,
                  shape: BoxShape.circle,
                  border: Border.all(color: borde),
                ),
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: color),
                  duration: _duracion,
                  builder: (context, c, _) =>
                      Icon(paso.icono, size: 18, color: c),
                ),
              ),
              if (e == EstadoPaso.activo)
                const Positioned(
                  left: -4,
                  top: -4,
                  right: -4,
                  bottom: -4,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Ipesa.petroleo,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              Positioned(
                right: -3,
                bottom: -3,
                child: AnimatedScale(
                  scale: marcado ? 1 : 0,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutBack,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: e == EstadoPaso.aviso ? _ambarFuerte : _verde,
                      shape: BoxShape.circle,
                      border: Border.all(color: _panel, width: 2),
                    ),
                    child: Icon(
                      e == EstadoPaso.aviso ? Icons.priority_high : Icons.check,
                      size: 9,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        AnimatedDefaultTextStyle(
          duration: _duracion,
          style: TextStyle(
            fontFamily: Ipesa.fuenteTitulos,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colorNombre,
          ),
          child: Text(
            paso.nombre,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(
          height: 15,
          child: e == EstadoPaso.hecho && paso.hora != null
              ? Text(
                  _hora.format(paso.hora!),
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: _tenue,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                )
              : null,
        ),
      ],
    );
  }
}
