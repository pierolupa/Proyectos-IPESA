import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/estado_badge.dart';
import 'admin_dashboard_screen.dart';

/// Qué guías cuentan en el resumen: hoy o un rango de fechas (de inicio a
/// fin, inclusive). Las que siguen pendientes (en ruta o en trasbordo)
/// cuentan siempre; las cerradas, si se cerraron en el periodo.
@immutable
class PeriodoResumen {
  const PeriodoResumen._(this._desde, this._hasta);

  /// El periodo por defecto.
  static const hoy = PeriodoResumen._(null, null);

  /// Del día de [desde] al de [hasta], inclusive.
  factory PeriodoResumen.fechas(DateTime desde, DateTime hasta) =>
      PeriodoResumen._(_dia(desde), _dia(hasta));

  final DateTime? _desde;
  final DateTime? _hasta;

  static DateTime _dia(DateTime f) => DateTime(f.year, f.month, f.day);

  bool get esHoy => _desde == null;

  /// Primer y último día del periodo.
  (DateTime, DateTime) dias(DateTime ahora) =>
      esHoy ? (_dia(ahora), _dia(ahora)) : (_desde!, _hasta!);

  /// Para el selector: "Fechas" en hoy, si no el rango elegido.
  String get corta {
    if (esHoy) return 'Fechas';
    final f = DateFormat('dd/MM');
    return _desde == _hasta
        ? f.format(_desde!)
        : '${f.format(_desde!)} – ${f.format(_hasta!)}';
  }

  String get etiqueta {
    if (esHoy) return 'Hoy';
    final f = DateFormat('dd/MM/yyyy');
    return _desde == _hasta
        ? f.format(_desde!)
        : 'Del ${f.format(_desde!)} al ${f.format(_hasta!)}';
  }

  bool incluye(Guia guia, DateTime ahora) {
    if (!guia.estado.esCerrada) return true;
    final (desde, hasta) = dias(ahora);
    final cierre = _dia(
      (guia.fechaCierre ?? guia.fechaActualizacion).toLocal(),
    );
    return !cierre.isBefore(desde) && !cierre.isAfter(hasta);
  }

  @override
  bool operator ==(Object other) =>
      other is PeriodoResumen &&
      other._desde == _desde &&
      other._hasta == _hasta;

  @override
  int get hashCode => Object.hash(_desde, _hasta);
}

/// Las guías de un transportista en el periodo, con sus cuentas.
class ResumenTransportista {
  ResumenTransportista(this.nombre, List<Guia> guias)
    : guias = [...guias]
        ..sort((a, b) => b.fechaActualizacion.compareTo(a.fechaActualizacion));

  final String nombre;

  /// De la más reciente a la más antigua.
  final List<Guia> guias;

  int cuantas(GrupoEstado grupo) =>
      guias.where((g) => g.estado.grupo == grupo).length;

  int get pendientes =>
      cuantas(GrupoEstado.enRuta) + cuantas(GrupoEstado.trasbordo);

  DateTime? get ultimaActividad =>
      guias.isEmpty ? null : guias.first.fechaActualizacion;

  List<Guia> de(Iterable<GrupoEstado> grupos) =>
      guias.where((g) => grupos.contains(g.estado.grupo)).toList();
}

/// Un resumen por transportista, el de actividad más reciente primero.
List<ResumenTransportista> resumirPorTransportista(
  Iterable<Guia> guias,
  PeriodoResumen periodo, {
  DateTime? ahora,
}) {
  final momento = ahora ?? DateTime.now();
  final porNombre = <String, List<Guia>>{};
  for (final g in guias) {
    if (!periodo.incluye(g, momento)) continue;
    final nombre = g.transportista.trim().isEmpty
        ? 'Sin transportista'
        : g.transportista.trim();
    porNombre.putIfAbsent(nombre, () => []).add(g);
  }
  return [
    for (final e in porNombre.entries) ResumenTransportista(e.key, e.value),
  ]..sort((a, b) => b.ultimaActividad!.compareTo(a.ultimaActividad!));
}

EstadoGuia _estadoDe(GrupoEstado g) => switch (g) {
  GrupoEstado.enRuta => EstadoGuia.enRuta,
  GrupoEstado.trasbordo => EstadoGuia.enProcesoTrasbordo,
  GrupoEstado.entregado => EstadoGuia.entregado,
  GrupoEstado.rechazado => EstadoGuia.rechazado,
};

String _conteo(GrupoEstado grupo, int n) => switch (grupo) {
  GrupoEstado.enRuta => '$n en ruta',
  GrupoEstado.trasbordo => '$n en trasbordo',
  GrupoEstado.entregado => n == 1 ? '1 entregada' : '$n entregadas',
  GrupoEstado.rechazado => n == 1 ? '1 rechazada' : '$n rechazadas',
};

String _iniciales(String nombre) {
  final partes = nombre.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return partes.take(2).map((p) => p[0].toUpperCase()).join();
}

/// Selector del periodo: "Hoy" o un rango de fechas de inicio a fin.
class SelectorPeriodo extends StatelessWidget {
  const SelectorPeriodo({
    super.key,
    required this.periodo,
    required this.onCambio,
  });

  final PeriodoResumen periodo;
  final ValueChanged<PeriodoResumen> onCambio;

  Future<void> _elegirFechas(BuildContext context) async {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final (desde, hasta) = periodo.dias(ahora);
    final elegido = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: hoy,
      initialDateRange: DateTimeRange(start: desde, end: hasta),
      helpText: 'Fecha de inicio y fin',
      saveText: 'Ver',
    );
    if (elegido == null) return;
    onCambio(PeriodoResumen.fechas(elegido.start, elegido.end));
  }

  @override
  Widget build(BuildContext context) {
    Widget segmento(
      String texto,
      bool activo,
      VoidCallback onTap, {
      IconData? icono,
    }) => Semantics(
      button: true,
      selected: activo,
      child: Material(
        color: activo ? Ipesa.petroleo : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icono != null) ...[
                  Icon(
                    icono,
                    size: 16,
                    color: activo ? Colors.white : Ipesa.etiqueta,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  texto,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: activo ? FontWeight.w700 : FontWeight.w600,
                    color: activo ? Colors.white : Ipesa.etiqueta,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Ipesa.borde),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          segmento('Hoy', periodo.esHoy, () => onCambio(PeriodoResumen.hoy)),
          const VerticalDivider(width: 1, color: Ipesa.borde),
          segmento(
            periodo.corta,
            !periodo.esHoy,
            () => _elegirFechas(context),
            icono: Icons.calendar_month_outlined,
          ),
        ],
      ),
    );
  }
}

/// Pestaña "Transportistas" del administrador: cada transportista con sus
/// guías del periodo; tocar uno abre su desglose.
class PestanaTransportistas extends StatefulWidget {
  const PestanaTransportistas({super.key});

  @override
  State<PestanaTransportistas> createState() => _PestanaTransportistasState();
}

class _PestanaTransportistasState extends State<PestanaTransportistas> {
  PeriodoResumen _periodo = PeriodoResumen.hoy;
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    if (appState.cargando && appState.guias.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final q = _busqueda.trim().toLowerCase();
    final resumenes = resumirPorTransportista(
      appState.guias,
      _periodo,
    ).where((r) => r.nombre.toLowerCase().contains(q)).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final ancha = constraints.maxWidth >= 900;
        final buscador = TextField(
          onChanged: (v) => setState(() => _busqueda = v),
          decoration: const InputDecoration(
            hintText: 'Buscar transportista',
            prefixIcon: Icon(Icons.search),
            contentPadding: EdgeInsets.symmetric(vertical: 12),
          ),
        );
        final selector = SelectorPeriodo(
          periodo: _periodo,
          onCambio: (p) => setState(() => _periodo = p),
        );
        final cabecera = Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
          child: ancha
              ? Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: buscador,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    selector,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buscador,
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerLeft, child: selector),
                  ],
                ),
        );

        void abrir(ResumenTransportista r) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TransportistaDetalleScreen(
              nombre: r.nombre,
              periodoInicial: _periodo,
            ),
          ),
        );

        final Widget lista;
        if (resumenes.isEmpty) {
          lista = ListView(
            children: [
              const SizedBox(height: 80),
              Center(
                child: Text(
                  q.isEmpty
                      ? 'Ningún transportista tiene guías en este periodo.'
                      : 'Ningún transportista coincide con la búsqueda.',
                  style: const TextStyle(color: Ipesa.textoSuave),
                ),
              ),
            ],
          );
        } else {
          lista = ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            itemCount: resumenes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (_, i) => _TarjetaTransportista(
              resumen: resumenes[i],
              ancha: ancha,
              onAbrir: () => abrir(resumenes[i]),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cabecera,
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => context.read<AppState>().cargarGuias(),
                child: lista,
              ),
            ),
          ],
        );
      },
    );
  }
}

const _bordeTarjeta = Color(0xFFE1E6E4);
final _hora = DateFormat('HH:mm');
final _diaHora = DateFormat('dd/MM HH:mm');

/// Un transportista: su cabecera (toca para ver el desglose), sus guías en
/// curso como casillas y, en un panel aparte, las que ya entregó.
class _TarjetaTransportista extends StatelessWidget {
  const _TarjetaTransportista({
    required this.resumen,
    required this.ancha,
    required this.onAbrir,
  });

  final ResumenTransportista resumen;
  final bool ancha;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    final r = resumen;
    final sinNombre = r.nombre == 'Sin transportista';
    // Finalizadas: entregadas o rechazadas; ya no están en curso.
    final finalizadas = r.de([GrupoEstado.entregado, GrupoEstado.rechazado]);
    final enCurso = r.de([GrupoEstado.enRuta, GrupoEstado.trasbordo]);
    final conteos = Wrap(
      spacing: 18,
      runSpacing: 4,
      children: [
        for (final g in GrupoEstado.values)
          if (r.cuantas(g) > 0)
            Text(
              _conteo(g, r.cuantas(g)),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _estadoDe(g).color,
              ),
            ),
      ],
    );

    final cabecera = InkWell(
      onTap: onAbrir,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            _Avatar(nombre: r.nombre, sinNombre: sinNombre),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ipesa.titulo(17, color: Ipesa.texto),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sinNombre
                        ? 'Por asignar · ${haceCuanto(r.ultimaActividad!)}'
                        : 'Última actividad ${haceCuanto(r.ultimaActividad!)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: sinNombre
                          ? EstadoGuia.enProcesoTrasbordo.color
                          : Ipesa.textoSuave,
                    ),
                  ),
                ],
              ),
            ),
            if (ancha) ...[
              conteos,
              Container(
                width: 1,
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 18),
                color: _bordeTarjeta,
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${finalizadas.length}'),
                    TextSpan(
                      text: '/${r.guias.length}',
                      style: const TextStyle(color: Ipesa.textoSuave),
                    ),
                  ],
                ),
                style: Ipesa.titulo(20, color: Ipesa.texto),
              ),
              const SizedBox(width: 14),
            ],
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: Ipesa.borde),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.chevron_right, color: Ipesa.petroleo),
            ),
          ],
        ),
      ),
    );

    final casillasEnCurso = _Seccion(
      titulo: 'En curso',
      guias: enCurso,
      maximo: 12,
      vacio: 'No tiene guías en curso.',
      onVerMas: onAbrir,
    );
    final panelFinalizadas = _PanelFinalizadas(
      guias: finalizadas,
      onVerMas: onAbrir,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _bordeTarjeta),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: EdgeInsets.fromLTRB(ancha ? 24 : 16, 16, ancha ? 24 : 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cabecera,
          if (!ancha) ...[const SizedBox(height: 8), conteos],
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) => c.maxWidth >= 720
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: casillasEnCurso),
                      const SizedBox(width: 20),
                      SizedBox(
                        width: _PanelFinalizadas.ancho,
                        child: panelFinalizadas,
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      casillasEnCurso,
                      const SizedBox(height: 14),
                      panelFinalizadas,
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.nombre, required this.sinNombre});

  final String nombre;
  final bool sinNombre;

  @override
  Widget build(BuildContext context) {
    if (sinNombre) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Ipesa.borde, width: 1.5),
        ),
        child: const Icon(
          Icons.person_outline,
          size: 22,
          color: Ipesa.textoSuave,
        ),
      );
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: Ipesa.petroleo,
      child: Text(
        _iniciales(nombre),
        style: Ipesa.titulo(15, color: Colors.white),
      ),
    );
  }
}

/// Título pequeño + casillas de guías; si son muchas, "Ver N más".
class _Seccion extends StatelessWidget {
  const _Seccion({
    required this.titulo,
    required this.guias,
    required this.maximo,
    required this.vacio,
    required this.onVerMas,
    this.cabecera,
  });

  final String titulo;
  final List<Guia> guias;
  final int maximo;
  final String vacio;
  final VoidCallback onVerMas;
  final Widget? cabecera;

  @override
  Widget build(BuildContext context) {
    final visibles = guias.take(maximo).toList();
    final restantes = guias.length - visibles.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cabecera ??
            Text(
              '${titulo.toUpperCase()} · ${guias.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Ipesa.textoSuave,
              ),
            ),
        const SizedBox(height: 10),
        if (guias.isEmpty)
          Text(vacio, style: const TextStyle(color: Ipesa.textoSuave))
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final g in visibles) _Casilla(guia: g)],
          ),
        if (restantes > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextButton(
              onPressed: onVerMas,
              child: Text(restantes == 1 ? 'Ver 1 más' : 'Ver $restantes más'),
            ),
          ),
      ],
    );
  }
}

/// Ventana aparte con las guías que ya terminaron: entregadas o
/// rechazadas.
class _PanelFinalizadas extends StatelessWidget {
  const _PanelFinalizadas({required this.guias, required this.onVerMas});

  /// Dos casillas por fila.
  static const ancho = _Casilla.ancho * 2 + 10 + 16 * 2 + 2;

  final List<Guia> guias;
  final VoidCallback onVerMas;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7F5),
        border: Border.all(color: _bordeTarjeta),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _Seccion(
        titulo: 'Finalizadas',
        guias: guias,
        maximo: 8,
        vacio: 'Aún no finaliza ninguna.',
        onVerMas: onVerMas,
        cabecera: Row(
          children: [
            const Icon(Icons.task_alt, size: 18, color: Ipesa.petroleo),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Finalizadas',
                style: Ipesa.titulo(15, color: Ipesa.texto),
              ),
            ),
            Text(
              '${guias.length}',
              style: Ipesa.titulo(15, color: Ipesa.petroleo),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una guía: número, estado (solo texto de color) y hora; tocarla la abre.
class _Casilla extends StatelessWidget {
  const _Casilla({required this.guia});

  static const ancho = 176.0;

  final Guia guia;

  @override
  Widget build(BuildContext context) {
    final g = guia;
    final fecha = g.fechaActualizacion.toLocal();
    final ahora = DateTime.now();
    final hoy =
        fecha.year == ahora.year &&
        fecha.month == ahora.month &&
        fecha.day == ahora.day;
    return SizedBox(
      width: ancho,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: _bordeTarjeta),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => abrirGuiaAdmin(context, g),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 3, color: g.estado.color),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.numeroGuia,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Ipesa.texto,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (g.destinatario.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      // El cliente, recortado si es largo (completo al
                      // pasar el mouse).
                      Tooltip(
                        message: g.destinatario.trim(),
                        waitDuration: const Duration(milliseconds: 400),
                        child: Text(
                          g.destinatario.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Ipesa.etiqueta,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      '${g.eliminacionPendiente ? 'Pide eliminar' : g.estado.grupo.etiqueta} · '
                      '${(hoy ? _hora : _diaHora).format(fecha)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: g.eliminacionPendiente
                            ? EstadoGuia.rechazado.color
                            : g.estado.color,
                      ),
                    ),
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

/// Desglose de un transportista: cuántas guías tiene en cada estado, qué
/// tan seguido entrega, por qué rechazó, y cada guía (tocarla la abre).
class TransportistaDetalleScreen extends StatefulWidget {
  const TransportistaDetalleScreen({
    super.key,
    required this.nombre,
    this.periodoInicial = PeriodoResumen.hoy,
  });

  final String nombre;
  final PeriodoResumen periodoInicial;

  @override
  State<TransportistaDetalleScreen> createState() =>
      _TransportistaDetalleScreenState();
}

/// Las pestañas de la tabla de guías del transportista.
enum _Pestana {
  pendientes('Pendientes', [GrupoEstado.enRuta, GrupoEstado.trasbordo]),
  entregadas('Entregadas', [GrupoEstado.entregado]),
  rechazadas('Rechazadas', [GrupoEstado.rechazado]);

  const _Pestana(this.titulo, this.grupos);
  final String titulo;
  final List<GrupoEstado> grupos;
}

class _TransportistaDetalleScreenState
    extends State<TransportistaDetalleScreen> {
  late PeriodoResumen _periodo = widget.periodoInicial;
  var _pestana = _Pestana.pendientes;
  var _busqueda = '';

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final resumen = resumirPorTransportista(
      appState.guias,
      _periodo,
    ).where((r) => r.nombre == widget.nombre).firstOrNull;
    final ancho = MediaQuery.sizeOf(context).width;

    return Scaffold(
      appBar: AppBar(title: Text(widget.nombre)),
      body: ancho >= 1000
          ? _vistaAncha(resumen)
          : _vistaAngosta(resumen, ancho >= 700),
    );
  }

  Widget get _selector => SelectorPeriodo(
    periodo: _periodo,
    onCambio: (p) => setState(() => _periodo = p),
  );

  static const _sinGuias = Padding(
    padding: EdgeInsets.symmetric(vertical: 40),
    child: Text(
      'No tiene guías en este periodo.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Ipesa.textoSuave),
    ),
  );

  /// Los indicadores: uno por estado y el cierre (con la eficiencia).
  List<Widget> _indicadores(ResumenTransportista r) {
    final total = r.guias.length;
    final entregadas = r.cuantas(GrupoEstado.entregado);
    final cerradas = entregadas + r.cuantas(GrupoEstado.rechazado);
    String pct(int n) => '${total == 0 ? 0 : (n * 100 / total).round()} %';
    return [
      for (final g in GrupoEstado.values)
        _Cifra(grupo: g, cantidad: r.cuantas(g)),
      _Indicador(
        valor: pct(cerradas),
        etiqueta: 'Cierre',
        color: Ipesa.petroleo,
        detalle: 'Eficiencia ${pct(entregadas)}',
      ),
    ];
  }

  /// Escritorio: indicadores arriba; abajo la tabla de guías y, al
  /// costado, el mapa con el recorrido y la línea del día. La página no
  /// se desplaza: solo la tabla y la línea del día.
  Widget _vistaAncha(ResumenTransportista? resumen) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 76,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: _selector),
                if (resumen != null)
                  for (final w in _indicadores(resumen)) ...[
                    const SizedBox(width: 12),
                    Expanded(child: w),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: resumen == null
                ? const Align(alignment: Alignment.topCenter, child: _sinGuias)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: _tabla(resumen)),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 3,
                              child: MapaGuias(
                                guias: resumen.guias,
                                recorrido: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              flex: 2,
                              child: _LineaDelDia(
                                guias: resumen.guias,
                                titulo: _periodo.esHoy
                                    ? 'Línea del día'
                                    : 'Actividad',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tabla(ResumenTransportista resumen) {
    final texto = _busqueda.trim().toLowerCase();
    final guias = resumen
        .de(_pestana.grupos)
        .where(
          (g) =>
              texto.isEmpty ||
              g.numeroGuia.toLowerCase().contains(texto) ||
              g.destinatario.toLowerCase().contains(texto) ||
              g.destino.toLowerCase().contains(texto),
        )
        .toList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _bordeTarjeta),
        borderRadius: BorderRadius.circular(Ipesa.radio),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final p in _Pestana.values)
                          _BotonPestana(
                            titulo: p.titulo,
                            cantidad: resumen.de(p.grupos).length,
                            activa: p == _pestana,
                            onTap: () => setState(() => _pestana = p),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 240,
                  child: TextField(
                    onChanged: (v) => setState(() => _busqueda = v),
                    decoration: const InputDecoration(
                      hintText: 'Buscar',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const _FilaTabla(
            encabezado: true,
            celdas: [
              Text('GUÍA'),
              Text('DESTINATARIO'),
              Text('ESTADO'),
              Text('HACE'),
            ],
          ),
          Expanded(
            child: guias.isEmpty
                ? Center(
                    child: Text(
                      texto.isEmpty
                          ? 'Sin guías ${_pestana.titulo.toLowerCase()}.'
                          : 'Ninguna guía coincide con la búsqueda.',
                      style: const TextStyle(color: Ipesa.textoSuave),
                    ),
                  )
                : ListView.builder(
                    itemCount: guias.length,
                    itemBuilder: (context, i) {
                      final g = guias[i];
                      final nota = g.estado == EstadoGuia.rechazado
                          ? g.motivoRechazo
                          : g.resumenTransbordo.isNotEmpty
                          ? g.resumenTransbordo
                          : g.enDespachoCorte
                          ? 'Despacho Corte ${g.despachoCorte}'
                          : '';
                      return InkWell(
                        onTap: () => abrirGuiaAdmin(context, g),
                        child: _FilaTabla(
                          celdas: [
                            Text(g.numeroGuia, style: Ipesa.titulo(14.5)),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  g.destinatario,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (nota.isNotEmpty)
                                  Text(
                                    nota,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: g.estado == EstadoGuia.rechazado
                                          ? EstadoGuia.rechazado.color
                                          : g.resumenTransbordo.isNotEmpty
                                          ? EstadoGuia.enRuta.color
                                          : Ipesa.petroleo,
                                    ),
                                  ),
                              ],
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: EstadoBadge(estado: g.estado),
                            ),
                            Text(
                              haceCuanto(g.fechaActualizacion),
                              style: const TextStyle(color: Ipesa.textoSuave),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Celular o ventana angosta: todo en una columna que se desplaza.
  Widget _vistaAngosta(ResumenTransportista? resumen, bool media) {
    final contenido = <Widget>[
      Align(alignment: Alignment.centerLeft, child: _selector),
      const SizedBox(height: 16),
    ];
    if (resumen == null) {
      contenido.add(_sinGuias);
    } else {
      final motivos = <String, int>{};
      for (final g in resumen.de([GrupoEstado.rechazado])) {
        final motivo = g.motivoRechazo.split(':').first.trim();
        final clave = motivo.isEmpty ? 'Sin motivo' : motivo;
        motivos[clave] = (motivos[clave] ?? 0) + 1;
      }
      contenido.addAll([
        GridView.count(
          crossAxisCount: media ? 5 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: media ? 1.6 : 1.9,
          children: _indicadores(resumen),
        ),
        const SizedBox(height: 14),
        _Linea(
          icono: Icons.schedule,
          texto: 'Última actividad ${haceCuanto(resumen.ultimaActividad!)}',
        ),
        if (motivos.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Motivos de rechazo', style: Ipesa.titulo(16)),
          const SizedBox(height: 6),
          for (final e in motivos.entries)
            _Linea(
              icono: Icons.block,
              color: EstadoGuia.rechazado.color,
              texto: '${e.key} · ${e.value}',
            ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 300,
          child: MapaGuias(guias: resumen.guias, recorrido: true),
        ),
        for (final p in _Pestana.values)
          if (resumen.de(p.grupos) case final guias when guias.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('${p.titulo} · ${guias.length}', style: Ipesa.titulo(17)),
            const SizedBox(height: 8),
            for (final g in guias)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TarjetaGuiaAdmin(guia: g, mostrarTransportista: false),
              ),
          ],
      ]);
    }
    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().cargarGuias(),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: contenido,
          ),
        ),
      ),
    );
  }
}

class _BotonPestana extends StatelessWidget {
  const _BotonPestana({
    required this.titulo,
    required this.cantidad,
    required this.activa,
    required this.onTap,
  });

  final String titulo;
  final int cantidad;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: activa,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: activa ? Ipesa.petroleo : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titulo,
                style: Ipesa.titulo(
                  14.5,
                  color: activa ? Ipesa.petroleo : Ipesa.textoSuave,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: activa ? Ipesa.petroleo : Ipesa.segmento,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$cantidad',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: activa ? Colors.white : Ipesa.etiqueta,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una fila de la tabla de guías (o su encabezado).
class _FilaTabla extends StatelessWidget {
  const _FilaTabla({required this.celdas, this.encabezado = false});

  final List<Widget> celdas;
  final bool encabezado;

  @override
  Widget build(BuildContext context) {
    final estilo = encabezado
        ? const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Ipesa.textoSuave,
          )
        : const TextStyle(fontSize: 14.5, color: Ipesa.texto);
    return Container(
      constraints: BoxConstraints(minHeight: encabezado ? 38 : 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: encabezado ? const Color(0xFFFAFBFB) : null,
        border: const Border(top: BorderSide(color: Color(0xFFEDF1F0))),
      ),
      child: DefaultTextStyle.merge(
        style: estilo,
        child: Row(
          children: [
            SizedBox(width: 130, child: celdas[0]),
            Expanded(child: celdas[1]),
            const SizedBox(width: 12),
            SizedBox(width: 150, child: celdas[2]),
            SizedBox(width: 110, child: celdas[3]),
          ],
        ),
      ),
    );
  }
}

/// Lo que hizo el transportista, con la hora: registros (los de un mismo
/// minuto juntos), entregas y rechazos. Lo último queda abajo, a la vista.
class _LineaDelDia extends StatelessWidget {
  const _LineaDelDia({required this.guias, required this.titulo});

  final List<Guia> guias;
  final String titulo;

  static DateTime _minuto(DateTime f) {
    final l = f.toLocal();
    return DateTime(l.year, l.month, l.day, l.hour, l.minute);
  }

  static String _guias(int n) => n == 1 ? '1 guía' : '$n guías';

  List<(DateTime, String, Color)> _eventos() {
    final eventos = <(DateTime, String, Color)>[];
    // Los registros de un mismo minuto (y despacho) van juntos; las
    // llegadas de un Despacho Corte, también.
    final registros = <(DateTime, String), List<Guia>>{};
    final llegadas = <(DateTime, String), int>{};
    for (final g in guias) {
      registros
          .putIfAbsent((_minuto(g.fechaCreacion), g.despachoCorte), () => [])
          .add(g);
      final cierre = g.fechaCierre ?? g.fechaActualizacion;
      if (g.estado.esFinal && g.enDespachoCorte) {
        final clave = (_minuto(cierre), g.despachoCorte);
        llegadas[clave] = (llegadas[clave] ?? 0) + 1;
      } else if (g.estado.esFinal) {
        eventos.add((
          cierre.toLocal(),
          'Entregó ${g.numeroGuia} · ${g.destinatario}',
          EstadoGuia.entregado.color,
        ));
      } else if (g.estado == EstadoGuia.rechazado) {
        eventos.add((
          g.fechaActualizacion.toLocal(),
          'Rechazó ${g.numeroGuia}'
              '${g.motivoRechazo.isEmpty ? '' : ' · ${g.motivoRechazo}'}',
          EstadoGuia.rechazado.color,
        ));
      }
    }
    for (final MapEntry(key: (minuto, corte), value: lista)
        in registros.entries) {
      eventos.add((
        minuto,
        corte.isNotEmpty
            ? 'Salió Despacho Corte $corte · ${_guias(lista.length)}'
            : lista.length == 1
            ? 'Registró ${lista.first.numeroGuia} · ${lista.first.destinatario}'
            : 'Registró ${lista.length} guías',
        corte.isNotEmpty ? Ipesa.petroleo : EstadoGuia.enRuta.color,
      ));
    }
    for (final MapEntry(key: (minuto, corte), value: n) in llegadas.entries) {
      eventos.add((
        minuto,
        'Llegó Despacho Corte $corte · '
            '${n == 1 ? '1 guía entregada' : '$n guías entregadas'}',
        EstadoGuia.entregado.color,
      ));
    }
    // Del más reciente al más antiguo (la lista va invertida).
    return eventos..sort((a, b) => b.$1.compareTo(a.$1));
  }

  @override
  Widget build(BuildContext context) {
    final eventos = _eventos();
    final hoy = DateTime.now();
    String hora(DateTime f) =>
        f.year == hoy.year && f.month == hoy.month && f.day == hoy.day
        ? DateFormat('HH:mm').format(f)
        : DateFormat('dd/MM HH:mm').format(f);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _bordeTarjeta),
        borderRadius: BorderRadius.circular(Ipesa.radio),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titulo, style: Ipesa.titulo(16, color: Ipesa.petroleo)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: eventos.length,
              itemBuilder: (context, i) {
                final (fecha, texto, color) = eventos[i];
                return SizedBox(
                  height: 38,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 82,
                        child: Text(
                          hora(fecha),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Ipesa.textoSuave,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 22,
                        height: 38,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // La línea que une los eventos.
                            Positioned(
                              top: i == eventos.length - 1 ? 19 : 0,
                              bottom: i == 0 ? 19 : 0,
                              child: Container(width: 2, color: Ipesa.borde),
                            ),
                            Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          texto,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14.5),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra({required this.grupo, required this.cantidad});

  final GrupoEstado grupo;
  final int cantidad;

  @override
  Widget build(BuildContext context) => _Indicador(
    valor: '$cantidad',
    etiqueta: grupo.etiqueta,
    color: _estadoDe(grupo).color,
  );
}

class _Indicador extends StatelessWidget {
  const _Indicador({
    required this.valor,
    required this.etiqueta,
    required this.color,
    this.detalle,
  });

  final String valor;
  final String etiqueta;
  final Color color;
  final String? detalle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _bordeTarjeta),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor, style: Ipesa.titulo(26, color: color)),
          ),
          Text(
            detalle == null ? etiqueta : '$etiqueta · $detalle',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea({required this.icono, required this.texto, this.color});

  final IconData icono;
  final String texto;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icono, size: 18, color: color ?? Ipesa.textoSuave),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 15, color: color ?? Ipesa.texto),
            ),
          ),
        ],
      ),
    );
  }
}
