import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/filtros_rastreo.dart';
import '../../models/guia.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/actualizacion_automatica.dart';
import '../../widgets/estado_badge.dart';
import 'rastreo_detalle_screen.dart';

final _fecha = DateFormat('dd/MM/yyyy');
final _fechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Resultados de una búsqueda del comercial: las guías que cumplen los
/// filtros, con chips para acotar por estado. Se actualiza sola.
class RastreoResultadosScreen extends StatefulWidget {
  const RastreoResultadosScreen({super.key, required this.filtros});

  final FiltrosRastreo filtros;

  @override
  State<RastreoResultadosScreen> createState() =>
      _RastreoResultadosScreenState();
}

class _RastreoResultadosScreenState extends State<RastreoResultadosScreen> {
  late GrupoEstado? _grupo = widget.filtros.grupo;

  /// Qué se buscó, en palabras, para mostrarlo arriba de la lista.
  List<String> get _resumen {
    final f = widget.filtros;
    return [
      if (f.numeroGuia.trim().isNotEmpty) 'Guía: ${f.numeroGuia.trim()}',
      if (f.cliente.trim().isNotEmpty) 'Cliente: ${f.cliente.trim()}',
      if (f.numeroPedido.trim().isNotEmpty) 'Pedido: ${f.numeroPedido.trim()}',
      if (f.numeroEntrega.trim().isNotEmpty)
        'Entrega: ${f.numeroEntrega.trim()}',
      if (f.tieneRango)
        '${f.campoFecha == CampoFecha.salida ? 'Salida' : 'Entrega'}: '
            '${_fecha.format(f.desde!)} – ${_fecha.format(f.hasta!)}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final filtros = widget.filtros.conGrupo(_grupo);
    final guias = filtros.aplicar(appState.guias);
    final base = widget.filtros.conGrupo(null).aplicar(appState.guias);
    final ancha = MediaQuery.sizeOf(context).width >= 1000;
    final resumen = _resumen;

    return Scaffold(
      appBar: AppBar(title: const Text('Resultados')),
      body: ActualizacionAutomatica(
        intervalo: const Duration(seconds: 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r
                      in resumen.isEmpty ? ['Todas las guías'] : resumen)
                    Chip(
                      avatar: const Icon(
                        Icons.search,
                        size: 16,
                        color: Ipesa.petroleo,
                      ),
                      label: Text(r),
                      backgroundColor: Ipesa.menta,
                      side: BorderSide.none,
                    ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  _ChipEstado(
                    etiqueta: 'Todos · ${base.length}',
                    seleccionado: _grupo == null,
                    onTap: () => setState(() => _grupo = null),
                  ),
                  for (final g in GrupoEstado.values)
                    _ChipEstado(
                      etiqueta:
                          '${g.etiqueta} · '
                          '${base.where((x) => x.estado.grupo == g).length}',
                      seleccionado: _grupo == g,
                      onTap: () => setState(() => _grupo = g),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _Resultados(
                guias: guias,
                total: base.length,
                cargando: appState.cargando && appState.guias.isEmpty,
                error: appState.error,
                tabla: ancha,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipEstado extends StatelessWidget {
  const _ChipEstado({
    required this.etiqueta,
    required this.seleccionado,
    required this.onTap,
  });

  final String etiqueta;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(etiqueta),
        selected: seleccionado,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        backgroundColor: Colors.white,
        selectedColor: Ipesa.menta,
        side: BorderSide(color: seleccionado ? Ipesa.petroleo : Ipesa.borde),
        labelStyle: TextStyle(
          fontFamily: Ipesa.fuenteTexto,
          color: seleccionado ? Ipesa.petroleo : Ipesa.texto,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
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
        builder: (_) => RastreoDetalleScreen(numeroGuia: guia.numeroGuia),
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

    final resumen = Padding(
      padding: EdgeInsets.fromLTRB(tabla ? 16 : 20, 8, 20, 10),
      child: Text(
        guias.length == total
            ? '$total ${total == 1 ? 'guía' : 'guías'}'
            : '${guias.length} de $total ${total == 1 ? 'guía' : 'guías'}',
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Ipesa.textoSuave,
        ),
      ),
    );

    if (guias.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          resumen,
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
          resumen,
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
      padding: const EdgeInsets.fromLTRB(8, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          resumen,
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Ipesa.radio),
                border: Border.all(color: Ipesa.borde),
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
                celda(6, EstadoBadge(estado: g.estado)),
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
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
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
                  EstadoBadge(estado: guia.estado),
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
