import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../theme.dart';

const _anchoNombre = 230.0;
const _anchoMinimoLinea = 700.0;
const _anchoPastilla = 118.0;
const _altoCarril = 40.0;
const _maxCarriles = 3;

/// Línea de tiempo del día: una fila por transportista y cada guía ubicada
/// en la hora de su último movimiento (registro, traslado o entrega).
class RecorridoTimeline extends StatelessWidget {
  const RecorridoTimeline({
    super.key,
    required this.guias,
    required this.onGuia,
    this.ahora,
  });

  final List<Guia> guias;
  final ValueChanged<Guia> onGuia;

  /// Inyectable para tests; por defecto, la hora actual.
  final DateTime? ahora;

  @override
  Widget build(BuildContext context) {
    final ahora = this.ahora ?? DateTime.now();
    final deHoy = guias.where((g) {
      final f = g.fechaActualizacion.toLocal();
      return f.year == ahora.year &&
          f.month == ahora.month &&
          f.day == ahora.day;
    }).toList();

    final porTransportista = <String, List<Guia>>{};
    for (final g in deHoy) {
      porTransportista.putIfAbsent(g.transportista, () => []).add(g);
    }
    final nombres = porTransportista.keys.toList()..sort();

    var horaInicio = 7;
    var horaFin = 19;
    for (final g in deHoy) {
      final h = g.fechaActualizacion.toLocal().hour;
      horaInicio = math.min(horaInicio, h);
      horaFin = math.max(horaFin, h + 1);
    }

    int contar(GrupoEstado grupo) =>
        guias.where((g) => g.estado.grupo == grupo).length;
    final entregadasHoy = deHoy
        .where((g) => g.estado.grupo == GrupoEstado.entregado)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: const [
            Text(
              'Cada guía aparece a la hora de su último movimiento.',
              style: TextStyle(fontSize: 15, color: Ipesa.textoSuave),
            ),
            Wrap(
              spacing: 16,
              children: [
                _Leyenda(estado: EstadoGuia.enRuta, texto: 'En ruta'),
                _Leyenda(
                  estado: EstadoGuia.enProcesoTrasbordo,
                  texto: 'Trasbordo',
                ),
                _Leyenda(estado: EstadoGuia.entregado, texto: 'Entregado'),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(Ipesa.radio),
            boxShadow: Ipesa.sombraSuave,
          ),
          clipBehavior: Clip.antiAlias,
          child: nombres.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'Aún no hay movimientos registrados hoy.',
                      style: TextStyle(color: Ipesa.textoSuave),
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final ancho = math.max(
                      constraints.maxWidth,
                      _anchoNombre + _anchoMinimoLinea,
                    );
                    final tabla = SizedBox(
                      width: ancho,
                      child: _Tabla(
                        anchoLinea: ancho - _anchoNombre - 16,
                        nombres: nombres,
                        porTransportista: porTransportista,
                        horaInicio: horaInicio,
                        horaFin: horaFin,
                        ahora: ahora,
                        onGuia: onGuia,
                      ),
                    );
                    if (ancho <= constraints.maxWidth) return tabla;
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: tabla,
                    );
                  },
                ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _Cifra(
              titulo: 'Entregadas hoy',
              valor: entregadasHoy,
              destacada: true,
            ),
            _Cifra(
              titulo: 'En ruta ahora',
              valor: contar(GrupoEstado.enRuta),
              color: EstadoGuia.enRuta.color,
            ),
            _Cifra(
              titulo: 'En trasbordo',
              valor: contar(GrupoEstado.trasbordo),
              color: EstadoGuia.enProcesoTrasbordo.color,
            ),
          ],
        ),
      ],
    );
  }
}

class _Tabla extends StatelessWidget {
  const _Tabla({
    required this.anchoLinea,
    required this.nombres,
    required this.porTransportista,
    required this.horaInicio,
    required this.horaFin,
    required this.ahora,
    required this.onGuia,
  });

  final double anchoLinea;
  final List<String> nombres;
  final Map<String, List<Guia>> porTransportista;
  final int horaInicio;
  final int horaFin;
  final DateTime ahora;
  final ValueChanged<Guia> onGuia;

  double _x(DateTime fecha) {
    final f = fecha.toLocal();
    final horas = f.hour + f.minute / 60 - horaInicio;
    return (horas / (horaFin - horaInicio)) * anchoLinea;
  }

  @override
  Widget build(BuildContext context) {
    const altoCabecera = 40.0;
    final xAhora = _x(ahora);
    final mostrarAhora = xAhora >= 0 && xAhora <= anchoLinea;

    return Stack(
      children: [
        Column(
          children: [
            SizedBox(
              height: altoCabecera,
              child: Row(
                children: [
                  const SizedBox(
                    width: _anchoNombre,
                    child: Padding(
                      padding: EdgeInsets.only(left: 18),
                      child: Text(
                        'Transportista',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Ipesa.textoSuave,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: anchoLinea,
                    child: Row(
                      children: [
                        for (var h = horaInicio; h < horaFin; h++)
                          Expanded(
                            child: Text(
                              '${h.toString().padLeft(2, '0')}:00',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Ipesa.textoSuave,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            for (final nombre in nombres)
              _Fila(
                nombre: nombre,
                guias: porTransportista[nombre]!,
                anchoLinea: anchoLinea,
                x: _x,
                onGuia: onGuia,
              ),
          ],
        ),
        if (mostrarAhora)
          Positioned(
            left: _anchoNombre + xAhora,
            top: altoCabecera,
            bottom: 0,
            child: Container(width: 2, color: const Color(0xFFD64545)),
          ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.nombre,
    required this.guias,
    required this.anchoLinea,
    required this.x,
    required this.onGuia,
  });

  final String nombre;
  final List<Guia> guias;
  final double anchoLinea;
  final double Function(DateTime) x;
  final ValueChanged<Guia> onGuia;

  @override
  Widget build(BuildContext context) {
    final ordenadas = [...guias]
      ..sort((a, b) => a.fechaActualizacion.compareTo(b.fechaActualizacion));

    // Reparte en carriles para que las guías con horas cercanas no se tapen.
    final finCarril = <double>[];
    final ubicadas = <(Guia, double, int)>[];
    for (final g in ordenadas) {
      final izq = x(g.fechaActualizacion)
          .clamp(0.0, anchoLinea - _anchoPastilla);
      var carril = finCarril.indexWhere((fin) => fin + 6 <= izq);
      if (carril == -1) {
        if (finCarril.length < _maxCarriles) {
          finCarril.add(0);
          carril = finCarril.length - 1;
        } else {
          carril = finCarril.length - 1;
        }
      }
      finCarril[carril] = izq + _anchoPastilla;
      ubicadas.add((g, izq, carril));
    }
    final alto = 24 + finCarril.length * _altoCarril;

    int contar(GrupoEstado grupo) =>
        guias.where((g) => g.estado.grupo == grupo).length;
    final resumen = [
      if (contar(GrupoEstado.entregado) > 0)
        '${contar(GrupoEstado.entregado)} entregada${contar(GrupoEstado.entregado) == 1 ? '' : 's'}',
      if (contar(GrupoEstado.enRuta) > 0)
        '${contar(GrupoEstado.enRuta)} en ruta',
      if (contar(GrupoEstado.trasbordo) > 0)
        '${contar(GrupoEstado.trasbordo)} trasbordo',
      if (contar(GrupoEstado.rechazado) > 0)
        '${contar(GrupoEstado.rechazado)} rechazada${contar(GrupoEstado.rechazado) == 1 ? '' : 's'}',
    ].join(' · ');

    return Container(
      height: math.max(alto, 76),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEEF1F0))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _anchoNombre,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Ipesa.menta,
                      shape: BoxShape.circle,
                    ),
                    child: Text(_iniciales(nombre), style: Ipesa.titulo(12)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          resumen,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Ipesa.textoSuave,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: anchoLinea,
            child: Stack(
              children: [
                for (final (g, izq, carril) in ubicadas)
                  Positioned(
                    left: izq,
                    top: 12 + carril * _altoCarril,
                    width: _anchoPastilla,
                    child: _Pastilla(guia: g, onTap: () => onGuia(g)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _iniciales(String nombre) => nombre
      .split(' ')
      .where((p) => p.isNotEmpty)
      .take(2)
      .map((p) => p[0].toUpperCase())
      .join();
}

class _Pastilla extends StatelessWidget {
  const _Pastilla({required this.guia, required this.onTap});

  final Guia guia;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hora = DateFormat('HH:mm').format(guia.fechaActualizacion.toLocal());
    return Tooltip(
      message:
          '${guia.numeroGuia} · ${guia.destinatario}\n'
          '${guia.estado.etiqueta} a las $hora',
      child: Material(
        color: guia.estado.colorFondo,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Text(
              guia.numeroGuia,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: Ipesa.fuenteTitulos,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: guia.estado.color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda({required this.estado, required this.texto});

  final EstadoGuia estado;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: estado.color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          texto,
          style: const TextStyle(fontSize: 14, color: Ipesa.etiqueta),
        ),
      ],
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra({
    required this.titulo,
    required this.valor,
    this.color = Ipesa.petroleo,
    this.destacada = false,
  });

  final String titulo;
  final int valor;
  final Color color;
  final bool destacada;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: destacada ? Ipesa.petroleo : Colors.white,
        borderRadius: BorderRadius.circular(Ipesa.radio),
        boxShadow: destacada ? null : Ipesa.sombraSuave,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontSize: 14,
              color: destacada ? Ipesa.suaveSobrePetroleo : Ipesa.textoSuave,
            ),
          ),
          Text(
            '$valor',
            style: Ipesa.titulo(32, color: destacada ? Colors.white : color),
          ),
        ],
      ),
    );
  }
}
