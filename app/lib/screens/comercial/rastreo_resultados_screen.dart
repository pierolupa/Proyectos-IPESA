import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/despacho.dart';
import '../../models/estado_guia.dart';
import '../../models/filtros_rastreo.dart';
import '../../models/guia.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/escena_ruta.dart';
import '../../widgets/lugares_sucursal.dart';
import 'rastreo_detalle_screen.dart';

final _fecha = DateFormat('dd/MM/yyyy');

/// Resultados de una búsqueda del comercial cuando coincide más de una
/// guía: tarjetas flotantes sobre el mismo paisaje del buscador (con el
/// camión abajo); el estado va como texto de color, sin fondo. Tocar una
/// abre la guía. Se actualiza con la pantalla de búsqueda de abajo.
class RastreoResultadosScreen extends StatelessWidget {
  const RastreoResultadosScreen({super.key, required this.filtros});

  final FiltrosRastreo filtros;

  /// Qué se buscó, en palabras, para mostrarlo arriba de la lista.
  String get _resumen {
    final f = filtros;
    String rango() {
      if (DateUtils.isSameDay(f.desde, f.hasta)) {
        return DateUtils.isSameDay(f.desde, DateTime.now())
            ? 'hoy'
            : _fecha.format(f.desde!);
      }
      return '${_fecha.format(f.desde!)} – ${_fecha.format(f.hasta!)}';
    }

    return [
      if (f.numeroGuia.trim().isNotEmpty) 'Guía: ${f.numeroGuia.trim()}',
      if (f.cliente.trim().isNotEmpty) 'Cliente: ${f.cliente.trim()}',
      if (f.numeroPedido.trim().isNotEmpty) 'Pedido: ${f.numeroPedido.trim()}',
      if (f.numeroEntrega.trim().isNotEmpty)
        'Entrega: ${f.numeroEntrega.trim()}',
      if (f.tieneRango) 'Tareas de ${rango()}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final guias = filtros.conGrupo(null).aplicar(appState.guias);
    final despachos = filtros
        .conGrupo(null)
        .aplicarDespachos(appState.despachos);
    final ancho = MediaQuery.sizeOf(context).width;
    final altoEscena = ancho < 600 ? 170.0 : 220.0;
    final n = guias.length + despachos.length;

    return Scaffold(
      backgroundColor: cieloEscena,
      body: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: EscenaRuta(alto: altoEscena),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            // La lista termina sobre el suelo: el camión queda a la vista.
            bottom: math.max(altoEscena - 56, 112),
            child: SafeArea(
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: ancho >= 1000 ? 1200 : 560,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                        child: Row(
                          children: [
                            IconButton.filled(
                              tooltip: 'Nueva búsqueda',
                              onPressed: () => Navigator.of(context).maybePop(),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Ipesa.petroleo,
                                fixedSize: const Size(44, 44),
                                elevation: 2,
                                shadowColor: const Color(0x330F4C5C),
                              ),
                              icon: const Icon(Icons.chevron_left, size: 26),
                            ),
                            Expanded(
                              child: Text(
                                'Resultados',
                                textAlign: TextAlign.center,
                                style: Ipesa.titulo(17),
                              ),
                            ),
                            const SizedBox(width: 44),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              n == 1
                                  ? '1 guía encontrada'
                                  : '$n guías encontradas',
                              style: Ipesa.titulo(24),
                            ),
                            if (_resumen.isNotEmpty)
                              Text(
                                _resumen,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Ipesa.textoSuave,
                                ),
                              ),
                            const SizedBox(height: 4),
                            _Conteos(guias: guias, despachos: despachos.length),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _Resultados(
                          guias: guias,
                          despachos: despachos,
                          total: n,
                          cargando: appState.cargando && appState.guias.isEmpty,
                          error: appState.error,
                          ancha: ancho >= 700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _conteo(GrupoEstado grupo, int n) => switch (grupo) {
  GrupoEstado.enRuta => '$n en ruta',
  GrupoEstado.trasbordo => '$n en trasbordo',
  GrupoEstado.entregado => n == 1 ? '1 entregada' : '$n entregadas',
  GrupoEstado.rechazado => n == 1 ? '1 rechazada' : '$n rechazadas',
};

EstadoGuia _estadoDe(GrupoEstado g) => switch (g) {
  GrupoEstado.enRuta => EstadoGuia.enRuta,
  GrupoEstado.trasbordo => EstadoGuia.enProcesoTrasbordo,
  GrupoEstado.entregado => EstadoGuia.entregado,
  GrupoEstado.rechazado => EstadoGuia.rechazado,
};

/// "2 en ruta · 1 entregada", cada parte en el color de su estado; solo
/// los estados que tienen guías.
class _Conteos extends StatelessWidget {
  const _Conteos({required this.guias, this.despachos = 0});

  final List<Guia> guias;

  /// Cuántas están solo en la hoja Despachos Ate.
  final int despachos;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 2,
      children: [
        for (final g in GrupoEstado.values)
          if (guias.where((x) => x.estado.grupo == g).length case final n
              when n > 0)
            Text(
              _conteo(g, n),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _estadoDe(g).color,
              ),
            ),
        if (despachos > 0)
          Text(
            despachos == 1 ? '1 despachada' : '$despachos despachadas',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _colorDespacho,
            ),
          ),
      ],
    );
  }
}

/// Las guías que solo están en Despachos Ate: "Despachado", sin
/// seguimiento.
const _colorDespacho = colorDespachado;

void _abrirDespacho(BuildContext context, Despacho d) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => RastreoDetalleScreen.despacho(d)));
}

void _abrirGuia(BuildContext context, Guia guia) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RastreoDetalleScreen(
        numeroGuia: guia.numeroGuia,
        fechaCreacion: guia.fechaCreacion,
      ),
    ),
  );
}

final _hora = DateFormat('HH:mm');
const _dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

/// Un resultado de la línea de tiempo: una guía de la app o un despacho de
/// Despachos Ate, con lo que se muestra de cada uno.
class _Evento {
  _Evento.guia(BuildContext context, Guia g)
    : fecha = g.fechaCreacion.toLocal(),
      numero = g.numeroGuia,
      cliente = g.destinatario,
      estado = g.estado.etiqueta,
      color = g.estado.color,
      detalle = _detalleGuia(context, g),
      numeros = _numeros(g.numeroPedido, g.numeroEntrega),
      abrir = ((c) => _abrirGuia(c, g));

  _Evento.despacho(Despacho d)
    : fecha = d.fecha.toLocal(),
      numero = d.numeroGuia,
      cliente = d.cliente,
      estado = 'Despachado',
      color = _colorDespacho,
      detalle = [
        'Salió de Almacen Ate',
        if (d.transporte.isNotEmpty) 'Entregada a ${d.transporte}',
        if (d.sucursal.isNotEmpty) d.sucursal,
      ].join(' · '),
      numeros = _numeros(d.numeroPedido, d.numeroEntrega),
      abrir = ((c) => _abrirDespacho(c, d));

  final DateTime fecha;
  final String numero;
  final String cliente;
  final String estado;
  final Color color;
  final String detalle;

  /// "Pedido … · Entrega …" (lo que se tenga).
  final String numeros;
  final void Function(BuildContext) abrir;

  static String _numeros(String pedido, String entrega) => [
    if (pedido.isNotEmpty) 'Pedido $pedido',
    if (entrega.isNotEmpty) 'Entrega $entrega',
  ].join(' · ');

  static String _detalleGuia(BuildContext context, Guia g) {
    final recojo = sucursalDeRecojo(context, g);
    final salida = [
      'Salió ${_hora.format(g.fechaCreacion.toLocal())}',
      if (recojo != null) 'de $recojo',
    ].join(' ');
    final String fin;
    if (g.estado.esFinal) {
      final lugar = lugarDeEntrega(context, g);
      final cuando = fechaDeCierre(g);
      fin = [
        'Entregada',
        if (cuando != null) _hora.format(cuando),
        if (lugar != null) 'en $lugar',
      ].join(' ');
    } else if (g.estado == EstadoGuia.rechazado) {
      fin = g.motivoRechazo.isEmpty
          ? 'No se entregó'
          : 'Rechazada: ${g.motivoRechazo}';
    } else {
      fin = g.transportista;
    }
    return [salida, if (fin.isNotEmpty) fin].join(' · ');
  }
}

class _Resultados extends StatelessWidget {
  const _Resultados({
    required this.guias,
    this.despachos = const [],
    required this.total,
    required this.cargando,
    required this.error,
    required this.ancha,
  });

  final List<Guia> guias;
  final List<Despacho> despachos;
  final int total;
  final bool cargando;
  final String? error;

  /// En la PC el día va a la izquierda; en el celular, arriba.
  final bool ancha;

  @override
  Widget build(BuildContext context) {
    if (cargando) return const Center(child: CircularProgressIndicator());
    if (error != null && total == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No se pudieron cargar las guías: $error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (guias.isEmpty && despachos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 40, color: Ipesa.textoSuave),
              SizedBox(height: 8),
              Text(
                'Ninguna guía coincide con los filtros.',
                style: TextStyle(color: Ipesa.textoSuave),
              ),
            ],
          ),
        ),
      );
    }

    // Por día de salida, del más reciente al más antiguo.
    final eventos = [
      for (final g in guias) _Evento.guia(context, g),
      for (final d in despachos) _Evento.despacho(d),
    ]..sort((a, b) => b.fecha.compareTo(a.fecha));
    final dias = <DateTime, List<_Evento>>{};
    for (final e in eventos) {
      dias.putIfAbsent(DateUtils.dateOnly(e.fecha), () => []).add(e);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        for (final MapEntry(key: dia, value: lista) in dias.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _Dia(dia: dia, eventos: lista, ancha: ancha),
          ),
      ],
    );
  }
}

/// Un día de la línea de tiempo: la fecha con su total y sus guías.
class _Dia extends StatelessWidget {
  const _Dia({required this.dia, required this.eventos, required this.ancha});

  final DateTime dia;
  final List<_Evento> eventos;
  final bool ancha;

  @override
  Widget build(BuildContext context) {
    final hoy = DateUtils.dateOnly(DateTime.now());
    final titulo = DateUtils.isSameDay(dia, hoy)
        ? 'Hoy ${DateFormat('dd/MM').format(dia)}'
        : '${_dias[dia.weekday - 1]} ${DateFormat('dd/MM').format(dia)}'
              '${dia.year != hoy.year ? '/${dia.year}' : ''}';
    final cabecera = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: Ipesa.titulo(16)),
        Text(
          eventos.length == 1 ? '1 guía' : '${eventos.length} guías',
          style: const TextStyle(fontSize: 13, color: Ipesa.textoSuave),
        ),
      ],
    );
    final lista = DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Ipesa.mentaBorde, width: 2)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, e) in eventos.indexed)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                child: _FilaEvento(evento: e),
              ),
          ],
        ),
      ),
    );
    if (ancha) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: cabecera,
            ),
          ),
          Expanded(child: lista),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: cabecera,
        ),
        lista,
      ],
    );
  }
}

/// Una guía en la línea de tiempo: número, cliente, el detalle de salida y
/// entrega, y el estado como texto de color (sin fondo ni ícono).
class _FilaEvento extends StatelessWidget {
  const _FilaEvento({required this.evento});

  final _Evento evento;

  @override
  Widget build(BuildContext context) {
    final e = evento;
    final estado = Text(
      e.estado,
      style: TextStyle(
        fontFamily: Ipesa.fuenteTitulos,
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: e.color,
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // El punto sobre la línea del día, del color del estado.
        Positioned(
          left: -21,
          top: 17,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: e.color,
              shape: BoxShape.circle,
              border: Border.all(color: cieloEscena, width: 2),
            ),
          ),
        ),
        Material(
          color: Colors.white,
          elevation: 1.5,
          shadowColor: const Color(0x330F4C5C),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => e.abrir(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(e.numero, style: Ipesa.titulo(15)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                e.cliente,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: Ipesa.texto,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          e.detalle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Ipesa.textoSuave,
                          ),
                        ),
                        if (e.numeros.isNotEmpty)
                          Text(
                            e.numeros,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Ipesa.etiqueta,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  estado,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
