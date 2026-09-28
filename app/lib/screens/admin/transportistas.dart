import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/actualizacion_automatica.dart';
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

class _ChipsPeriodo extends StatelessWidget {
  const _ChipsPeriodo({required this.periodo, required this.onCambio});

  final PeriodoResumen periodo;
  final ValueChanged<PeriodoResumen> onCambio;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in PeriodoResumen.values)
          ChoiceChip(
            label: Text(p.etiqueta),
            selected: p == periodo,
            showCheckmark: false,
            onSelected: (_) => onCambio(p),
            backgroundColor: Colors.white,
            selectedColor: Ipesa.menta,
            side: BorderSide(
              color: p == periodo ? Ipesa.petroleo : Ipesa.borde,
            ),
            labelStyle: TextStyle(
              fontFamily: Ipesa.fuenteTexto,
              color: p == periodo ? Ipesa.petroleo : Ipesa.texto,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
      ],
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
        final cabecera = Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                onChanged: (v) => setState(() => _busqueda = v),
                decoration: const InputDecoration(
                  hintText: 'Buscar transportista',
                  prefixIcon: Icon(Icons.search),
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 10),
              _ChipsPeriodo(
                periodo: _periodo,
                onCambio: (p) => setState(() => _periodo = p),
              ),
            ],
          ),
        );

        Widget tarjeta(ResumenTransportista r) => _TarjetaTransportista(
          resumen: r,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TransportistaDetalleScreen(
                nombre: r.nombre,
                periodoInicial: _periodo,
              ),
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
        } else if (ancha) {
          lista = GridView.builder(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 440,
              mainAxisExtent: 150,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: resumenes.length,
            itemBuilder: (_, i) => tarjeta(resumenes[i]),
          );
        } else {
          lista = ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            itemCount: resumenes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => tarjeta(resumenes[i]),
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

class _TarjetaTransportista extends StatelessWidget {
  const _TarjetaTransportista({required this.resumen, required this.onTap});

  final ResumenTransportista resumen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = resumen;
    final total = r.guias.length;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Ipesa.menta,
                    child: Text(_iniciales(r.nombre), style: Ipesa.titulo(15)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Ipesa.titulo(16),
                        ),
                        Text(
                          '${total == 1 ? '1 guía' : '$total guías'} · '
                          '${haceCuanto(r.ultimaActividad!)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Ipesa.textoSuave,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Ipesa.textoSuave),
                ],
              ),
              const SizedBox(height: 12),
              _BarraEstados(resumen: r),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final g in GrupoEstado.values)
                    if (r.cuantas(g) > 0)
                      Text(
                        _conteo(g, r.cuantas(g)),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _estadoDe(g).color,
                        ),
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra con la proporción de guías en cada estado.
class _BarraEstados extends StatelessWidget {
  const _BarraEstados({required this.resumen});

  final ResumenTransportista resumen;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final g in GrupoEstado.values)
              if (resumen.cuantas(g) > 0)
                Expanded(
                  flex: resumen.cuantas(g),
                  child: ColoredBox(color: _estadoDe(g).color),
                ),
          ],
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
      _ChipsPeriodo(
        periodo: _periodo,
        onCambio: (p) => setState(() => _periodo = p),
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
      body: ActualizacionAutomatica(
        intervalo: const Duration(seconds: 15),
        child: RefreshIndicator(
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
        color: estado.colorFondo,
        borderRadius: BorderRadius.circular(16),
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
