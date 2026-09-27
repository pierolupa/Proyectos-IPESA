import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/filtros_rastreo.dart';
import '../../models/guia.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/actualizacion_automatica.dart';
import '../../widgets/carrusel_marcas.dart';
import '../../widgets/estado_badge.dart';
import 'rastreo_detalle_screen.dart';

final _fecha = DateFormat('dd/MM/yyyy');
final _fechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Rangos rápidos de fecha (además de elegir uno a mano en el calendario).
enum _Rango { todas, hoy, semana, mes, personalizado }

/// Vista del equipo comercial: rastrea todas las guías (solo lectura) con
/// filtros por fecha, número de guía, cliente, N° de entrega y N° de
/// pedido. Se actualiza sola mientras está abierta.
class RastreoScreen extends StatefulWidget {
  const RastreoScreen({super.key});

  @override
  State<RastreoScreen> createState() => _RastreoScreenState();
}

class _RastreoScreenState extends State<RastreoScreen> {
  final _guia = TextEditingController();
  final _cliente = TextEditingController();
  final _entrega = TextEditingController();
  final _pedido = TextEditingController();
  GrupoEstado? _grupo;
  CampoFecha _campoFecha = CampoFecha.salida;
  _Rango _rango = _Rango.todas;
  DateTimeRange? _personalizado;
  bool _filtrosAbiertos = false;

  @override
  void dispose() {
    for (final c in [_guia, _cliente, _entrega, _pedido]) {
      c.dispose();
    }
    super.dispose();
  }

  (DateTime?, DateTime?) _limites() {
    final hoy = DateUtils.dateOnly(DateTime.now());
    return switch (_rango) {
      _Rango.todas => (null, null),
      _Rango.hoy => (hoy, hoy),
      _Rango.semana => (hoy.subtract(const Duration(days: 6)), hoy),
      _Rango.mes => (DateTime(hoy.year, hoy.month), hoy),
      _Rango.personalizado => (_personalizado?.start, _personalizado?.end),
    };
  }

  FiltrosRastreo get _filtros {
    final (desde, hasta) = _limites();
    return FiltrosRastreo(
      numeroGuia: _guia.text,
      cliente: _cliente.text,
      numeroEntrega: _entrega.text,
      numeroPedido: _pedido.text,
      grupo: _grupo,
      campoFecha: _campoFecha,
      desde: desde,
      hasta: hasta,
    );
  }

  int get _filtrosActivos =>
      [
        _guia,
        _cliente,
        _entrega,
        _pedido,
      ].where((c) => c.text.trim().isNotEmpty).length +
      (_grupo != null ? 1 : 0) +
      (_rango != _Rango.todas ? 1 : 0);

  void _limpiar() {
    for (final c in [_guia, _cliente, _entrega, _pedido]) {
      c.clear();
    }
    setState(() {
      _grupo = null;
      _rango = _Rango.todas;
      _personalizado = null;
    });
  }

  Future<void> _elegirFechas() async {
    final hoy = DateTime.now();
    final elegido = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(hoy.year + 1, 12, 31),
      initialDateRange: _personalizado,
      helpText: _campoFecha.etiqueta,
      saveText: 'Aplicar',
      // En computadora, una ventana del tamaño de un celular en vez de
      // ocupar toda la pantalla.
      builder: (context, child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 680),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Ipesa.radio),
            child: child,
          ),
        ),
      ),
    );
    if (elegido == null) return;
    setState(() {
      _personalizado = elegido;
      _rango = _Rango.personalizado;
    });
  }

  void _cerrarSesion() {
    context.read<AppState>().cerrarSesion();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final ancha = MediaQuery.sizeOf(context).width >= 1000;
    final resultados = _filtros.aplicar(appState.guias);

    final panel = _PanelFiltros(
      guia: _guia,
      cliente: _cliente,
      entrega: _entrega,
      pedido: _pedido,
      grupo: _grupo,
      campoFecha: _campoFecha,
      rango: _rango,
      personalizado: _personalizado,
      filtrosActivos: _filtrosActivos,
      onTexto: () => setState(() {}),
      onGrupo: (g) => setState(() => _grupo = g),
      onCampoFecha: (c) => setState(() => _campoFecha = c),
      onRango: (r) => r == _Rango.personalizado
          ? _elegirFechas()
          : setState(() => _rango = r),
      onLimpiar: _limpiar,
    );

    final lista = _Resultados(
      guias: resultados,
      total: appState.guias.length,
      cargando: appState.cargando && appState.guias.isEmpty,
      error: appState.error,
      tabla: ancha,
    );

    return Scaffold(
      bottomNavigationBar: const BandaMarcas(),
      body: SafeArea(
        child: ActualizacionAutomatica(
          intervalo: const Duration(seconds: 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Cabecera(
                nombre: appState.transportistaActual,
                onActualizar: appState.cargarGuias,
                onCerrarSesion: _cerrarSesion,
              ),
              Expanded(
                child: ancha
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 340,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(24, 8, 8, 24),
                              child: panel,
                            ),
                          ),
                          Expanded(child: lista),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _BotonFiltros(
                            abiertos: _filtrosAbiertos,
                            activos: _filtrosActivos,
                            onTap: () => setState(
                              () => _filtrosAbiertos = !_filtrosAbiertos,
                            ),
                          ),
                          if (_filtrosAbiertos)
                            Flexible(
                              flex: 3,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  8,
                                ),
                                child: panel,
                              ),
                            ),
                          Expanded(flex: 4, child: lista),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.nombre,
    required this.onActualizar,
    required this.onCerrarSesion,
  });

  final String nombre;
  final VoidCallback onActualizar;
  final VoidCallback onCerrarSesion;

  @override
  Widget build(BuildContext context) {
    Widget boton(String tooltip, IconData icono, VoidCallback onPressed) =>
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            style: IconButton.styleFrom(
              fixedSize: const Size(44, 44),
              backgroundColor: Colors.white,
              side: const BorderSide(color: Ipesa.borde),
            ),
            icon: Icon(icono, color: Ipesa.petroleo, size: 20),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rastreo de guías',
                  style: Ipesa.titulo(
                    MediaQuery.sizeOf(context).width < 600 ? 22 : 26,
                  ),
                ),
                Text(
                  '${nombre.isEmpty ? 'Equipo comercial' : nombre} · '
                  'se actualiza solo cada minuto',
                  style: const TextStyle(fontSize: 14, color: Ipesa.textoSuave),
                ),
              ],
            ),
          ),
          boton('Actualizar', Icons.refresh, onActualizar),
          boton('Cerrar sesión', Icons.logout, onCerrarSesion),
        ],
      ),
    );
  }
}

class _BotonFiltros extends StatelessWidget {
  const _BotonFiltros({
    required this.abiertos,
    required this.activos,
    required this.onTap,
  });

  final bool abiertos;
  final int activos;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          minimumSize: const Size(0, 48),
        ),
        icon: Icon(abiertos ? Icons.expand_less : Icons.tune),
        label: Text(
          activos == 0
              ? (abiertos ? 'Ocultar filtros' : 'Filtros')
              : '${abiertos ? 'Ocultar filtros' : 'Filtros'} · $activos',
        ),
      ),
    );
  }
}

class _PanelFiltros extends StatelessWidget {
  const _PanelFiltros({
    required this.guia,
    required this.cliente,
    required this.entrega,
    required this.pedido,
    required this.grupo,
    required this.campoFecha,
    required this.rango,
    required this.personalizado,
    required this.filtrosActivos,
    required this.onTexto,
    required this.onGrupo,
    required this.onCampoFecha,
    required this.onRango,
    required this.onLimpiar,
  });

  final TextEditingController guia;
  final TextEditingController cliente;
  final TextEditingController entrega;
  final TextEditingController pedido;
  final GrupoEstado? grupo;
  final CampoFecha campoFecha;
  final _Rango rango;
  final DateTimeRange? personalizado;
  final int filtrosActivos;
  final VoidCallback onTexto;
  final ValueChanged<GrupoEstado?> onGrupo;
  final ValueChanged<CampoFecha> onCampoFecha;
  final ValueChanged<_Rango> onRango;
  final VoidCallback onLimpiar;

  Widget _campo(TextEditingController c, String etiqueta, IconData icono) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          onChanged: (_) => onTexto(),
          decoration: InputDecoration(
            labelText: etiqueta,
            prefixIcon: Icon(icono, size: 20),
            isDense: true,
            suffixIcon: c.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Borrar',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      c.clear();
                      onTexto();
                    },
                  ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final titulo = Theme.of(context).textTheme.labelLarge;
    String etiquetaRango(_Rango r) => switch (r) {
      _Rango.todas => 'Todas',
      _Rango.hoy => 'Hoy',
      _Rango.semana => 'Últimos 7 días',
      _Rango.mes => 'Este mes',
      _Rango.personalizado =>
        personalizado == null
            ? 'Elegir fechas…'
            : '${_fecha.format(personalizado!.start)} – '
                  '${_fecha.format(personalizado!.end)}',
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Ipesa.radio),
        border: Border.all(color: Ipesa.borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Buscar', style: Ipesa.titulo(17))),
              if (filtrosActivos > 0)
                TextButton(
                  onPressed: onLimpiar,
                  child: const Text('Limpiar filtros'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _campo(guia, 'N° de guía', Icons.receipt_long_outlined),
          _campo(cliente, 'Cliente', Icons.business_outlined),
          _campo(entrega, 'N° de entrega', Icons.local_shipping_outlined),
          _campo(pedido, 'N° de pedido', Icons.shopping_bag_outlined),
          const SizedBox(height: 8),
          Text('Fechas', style: titulo),
          const SizedBox(height: 8),
          SegmentedButton<CampoFecha>(
            segments: [
              for (final c in CampoFecha.values)
                ButtonSegment(
                  value: c,
                  label: Text(c == CampoFecha.salida ? 'Salida' : 'Entrega'),
                ),
            ],
            selected: {campoFecha},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onCampoFecha(s.first),
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: Ipesa.menta,
              selectedForegroundColor: Ipesa.petroleo,
              textStyle: const TextStyle(
                fontFamily: Ipesa.fuenteTexto,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in _Rango.values)
                _Chip(
                  etiqueta: etiquetaRango(r),
                  icono: r == _Rango.personalizado ? Icons.date_range : null,
                  seleccionado: rango == r,
                  onTap: () => onRango(r),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Estado', style: titulo),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(
                etiqueta: 'Todos',
                seleccionado: grupo == null,
                onTap: () => onGrupo(null),
              ),
              for (final g in GrupoEstado.values)
                _Chip(
                  etiqueta: g.etiqueta,
                  seleccionado: grupo == g,
                  onTap: () => onGrupo(g),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.etiqueta,
    required this.seleccionado,
    required this.onTap,
    this.icono,
  });

  final String etiqueta;
  final bool seleccionado;
  final VoidCallback onTap;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      avatar: icono == null
          ? null
          : Icon(icono, size: 16, color: Ipesa.petroleo),
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
            ? '$total guías'
            : '${guias.length} de $total guías',
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
