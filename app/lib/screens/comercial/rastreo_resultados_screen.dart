import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/filtros_rastreo.dart';
import '../../models/guia.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/escena_ruta.dart';
import 'rastreo_detalle_screen.dart';

final _fecha = DateFormat('dd/MM/yyyy');
final _fechaHora = DateFormat('dd/MM/yyyy HH:mm');

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
    final ancho = MediaQuery.sizeOf(context).width;
    final altoEscena = ancho < 600 ? 170.0 : 220.0;
    final n = guias.length;

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
                            _Conteos(guias: guias),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _Resultados(
                          guias: guias,
                          total: guias.length,
                          cargando: appState.cargando && appState.guias.isEmpty,
                          error: appState.error,
                          tabla: ancho >= 1000,
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
  const _Conteos({required this.guias});

  final List<Guia> guias;

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
      ],
    );
  }
}

/// El estado como texto de color con un punto, sin fondo.
class _EstadoTexto extends StatelessWidget {
  const _EstadoTexto({required this.estado});

  final EstadoGuia estado;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: estado.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          estado.etiqueta,
          style: TextStyle(
            fontFamily: Ipesa.fuenteTitulos,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: estado.color,
          ),
        ),
      ],
    );
  }
}

class _Resultados extends StatelessWidget {
  const _Resultados({
    required this.guias,
    required this.total,
    required this.cargando,
    required this.error,
    required this.tabla,
  });

  final List<Guia> guias;
  final int total;
  final bool cargando;
  final String? error;
  final bool tabla;

  void _abrir(BuildContext context, Guia guia) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RastreoDetalleScreen(
          numeroGuia: guia.numeroGuia,
          fechaCreacion: guia.fechaCreacion,
        ),
      ),
    );
  }

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

    if (guias.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Center(
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
            ),
          ),
        ],
      );
    }

    if (!tabla) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: guias.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _Tarjeta(
                guia: guias[i],
                onTap: () => _abrir(context, guias[i]),
              ),
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Ipesa.radio),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A0F4C5C),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _FilaTabla.encabezado(),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      itemCount: guias.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _FilaTabla(
                        guia: guias[i],
                        onTap: () => _abrir(context, guias[i]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _fechaEntrega(Guia g) {
  final fecha =
      g.fechaCierre ?? (g.estado.esFinal ? g.fechaActualizacion : null);
  return fecha == null ? '—' : _fechaHora.format(fecha.toLocal());
}

class _FilaTabla extends StatelessWidget {
  const _FilaTabla({required Guia this.guia, required VoidCallback this.onTap});
  const _FilaTabla.encabezado() : guia = null, onTap = null;

  final Guia? guia;
  final VoidCallback? onTap;

  static const _flex = [14, 22, 11, 11, 13, 13, 12];

  @override
  Widget build(BuildContext context) {
    final g = guia;
    const estiloEncabezado = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Ipesa.etiqueta,
    );
    const estiloDato = TextStyle(fontSize: 14, color: Ipesa.texto);

    Widget celda(int i, Widget hijo) => Expanded(
      flex: _flex[i],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: hijo,
      ),
    );
    Widget texto(int i, String valor, {TextStyle estilo = estiloDato}) => celda(
      i,
      Text(
        valor.isEmpty ? '—' : valor,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: estilo,
      ),
    );

    final fila = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 8,
        vertical: g == null ? 12 : 14,
      ),
      child: Row(
        children: g == null
            ? [
                texto(0, 'N° de guía', estilo: estiloEncabezado),
                texto(1, 'Cliente', estilo: estiloEncabezado),
                texto(2, 'Pedido', estilo: estiloEncabezado),
                texto(3, 'Entrega', estilo: estiloEncabezado),
                texto(4, 'Salida', estilo: estiloEncabezado),
                texto(5, 'Entregada', estilo: estiloEncabezado),
                texto(6, 'Estado', estilo: estiloEncabezado),
              ]
            : [
                texto(0, g.numeroGuia, estilo: Ipesa.titulo(14)),
                texto(1, g.destinatario),
                texto(2, g.numeroPedido),
                texto(3, g.numeroEntrega),
                texto(4, _fechaHora.format(g.fechaCreacion.toLocal())),
                texto(5, _fechaEntrega(g)),
                celda(
                  6,
                  // "En proceso de trasbordo" es largo: se achica para caber.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _EstadoTexto(estado: g.estado),
                  ),
                ),
              ],
      ),
    );

    if (g == null) return ColoredBox(color: Ipesa.fondo, child: fila);
    return InkWell(onTap: onTap, child: fila);
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.guia, required this.onTap});

  final Guia guia;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final extra = [
      if (guia.numeroPedido.isNotEmpty) 'Pedido ${guia.numeroPedido}',
      if (guia.numeroEntrega.isNotEmpty) 'Entrega ${guia.numeroEntrega}',
    ].join(' · ');
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: const Color(0x330F4C5C),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(guia.numeroGuia, style: Ipesa.titulo(15)),
                  ),
                  const SizedBox(width: 12),
                  _EstadoTexto(estado: guia.estado),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                guia.destinatario,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (extra.isNotEmpty)
                Text(
                  extra,
                  style: const TextStyle(fontSize: 13, color: Ipesa.etiqueta),
                ),
              Text(
                'Salió ${_fechaHora.format(guia.fechaCreacion.toLocal())}'
                '${guia.estado.esFinal ? ' · entregada ${_fechaEntrega(guia)}' : ''}',
                style: const TextStyle(fontSize: 13, color: Ipesa.textoSuave),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
