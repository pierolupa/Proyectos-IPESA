import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import 'admin_dashboard_screen.dart';

/// Qué guías cuentan en el resumen. Las que siguen pendientes (en ruta o
/// en trasbordo) cuentan siempre; las cerradas, si se cerraron en el
/// periodo.
enum PeriodoResumen {
  hoy('Hoy'),
  semana('Últimos 7 días'),
  mes('Este mes'),
  todo('Todo');

  const PeriodoResumen(this.etiqueta);
  final String etiqueta;

  /// Para el selector compacto.
  String get corta => switch (this) {
    PeriodoResumen.hoy => 'Hoy',
    PeriodoResumen.semana => '7 días',
    PeriodoResumen.mes => 'Mes',
    PeriodoResumen.todo => 'Todo',
  };

  bool incluye(Guia guia, DateTime ahora) {
    if (this == PeriodoResumen.todo || !guia.estado.esCerrada) return true;
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final desde = switch (this) {
      PeriodoResumen.hoy => hoy,
      PeriodoResumen.semana => hoy.subtract(const Duration(days: 6)),
      PeriodoResumen.mes => DateTime(ahora.year, ahora.month),
      PeriodoResumen.todo => hoy,
    };
    final cierre = (guia.fechaCierre ?? guia.fechaActualizacion).toLocal();
    return !cierre.isBefore(desde);
  }
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

/// Selector compacto del periodo: Hoy · 7 días · Mes · Todo.
class SelectorPeriodo extends StatelessWidget {
  const SelectorPeriodo({
    super.key,
    required this.periodo,
    required this.onCambio,
  });

  final PeriodoResumen periodo;
  final ValueChanged<PeriodoResumen> onCambio;

  @override
  Widget build(BuildContext context) {
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
        children: [
          for (final p in PeriodoResumen.values) ...[
            if (p != PeriodoResumen.values.first)
              const VerticalDivider(width: 1, color: Ipesa.borde),
            Semantics(
              button: true,
              selected: p == periodo,
              child: Material(
                color: p == periodo ? Ipesa.petroleo : Colors.transparent,
                child: InkWell(
                  onTap: () => onCambio(p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: Text(
                        p.corta,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: p == periodo
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: p == periodo ? Colors.white : Ipesa.etiqueta,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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

class _TransportistaDetalleScreenState
    extends State<TransportistaDetalleScreen> {
  late PeriodoResumen _periodo = widget.periodoInicial;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final resumen = resumirPorTransportista(
      appState.guias,
      _periodo,
    ).where((r) => r.nombre == widget.nombre).firstOrNull;
    final ancha = MediaQuery.sizeOf(context).width >= 700;

    final contenido = <Widget>[
      Align(
        alignment: Alignment.centerLeft,
        child: SelectorPeriodo(
          periodo: _periodo,
          onCambio: (p) => setState(() => _periodo = p),
        ),
      ),
      const SizedBox(height: 16),
    ];

    if (resumen == null) {
      contenido.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Text(
            'No tiene guías en este periodo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Ipesa.textoSuave),
          ),
        ),
      );
    } else {
      final entregadas = resumen.cuantas(GrupoEstado.entregado);
      final cerradas = entregadas + resumen.cuantas(GrupoEstado.rechazado);
      final motivos = <String, int>{};
      for (final g in resumen.de([GrupoEstado.rechazado])) {
        final motivo = g.motivoRechazo.split(':').first.trim();
        final clave = motivo.isEmpty ? 'Sin motivo' : motivo;
        motivos[clave] = (motivos[clave] ?? 0) + 1;
      }

      contenido.addAll([
        GridView.count(
          crossAxisCount: ancha ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: ancha ? 1.9 : 1.7,
          children: [
            for (final g in GrupoEstado.values)
              _Cifra(grupo: g, cantidad: resumen.cuantas(g)),
          ],
        ),
        const SizedBox(height: 14),
        _Linea(
          icono: Icons.inventory_2_outlined,
          texto: resumen.guias.length == 1
              ? '1 guía en el periodo'
              : '${resumen.guias.length} guías en el periodo',
        ),
        if (cerradas > 0)
          _Linea(
            icono: Icons.verified_outlined,
            texto:
                'Entregó $entregadas de $cerradas cerradas '
                '(${(entregadas * 100 / cerradas).round()} %)',
          ),
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
        for (final (titulo, grupos) in [
          ('Pendientes', [GrupoEstado.enRuta, GrupoEstado.trasbordo]),
          ('Entregadas', [GrupoEstado.entregado]),
          ('Rechazadas', [GrupoEstado.rechazado]),
        ])
          if (resumen.de(grupos) case final guias when guias.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('$titulo · ${guias.length}', style: Ipesa.titulo(17)),
            const SizedBox(height: 8),
            for (final g in guias)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TarjetaGuiaAdmin(guia: g, mostrarTransportista: false),
              ),
          ],
      ]);
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.nombre)),
      body: RefreshIndicator(
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
      ),
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra({required this.grupo, required this.cantidad});

  final GrupoEstado grupo;
  final int cantidad;

  @override
  Widget build(BuildContext context) {
    final estado = _estadoDe(grupo);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _bordeTarjeta),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$cantidad', style: Ipesa.titulo(28, color: estado.color)),
          Text(
            grupo.etiqueta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: estado.color,
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
