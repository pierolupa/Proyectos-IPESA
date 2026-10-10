import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../models/tipo_entrega.dart';
import '../../services/archivo_imagen.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import 'admin_dashboard_screen.dart';
import 'transportistas.dart';

part 'analisis_agencias.dart';

const _colorEnRuta = Color(0xFF2459A8);
const _colorEntregado = Color(0xFF1D6B41);
const _colorRechazado = Color(0xFFB42318);

/// Una guía pendiente más de este tiempo se marca como atrasada.
const limiteAtraso = Duration(hours: 24);

/// Una columna del gráfico de entregas (una hora o un día).
class PuntoSerie {
  PuntoSerie(this.etiqueta, this.detalle);

  final String etiqueta;
  final String detalle;
  int entregadas = 0;
  int rechazadas = 0;

  /// Las guías que cerraron en este punto (para ver el detalle).
  final List<Guia> guias = [];

  int get total => entregadas + rechazadas;
}

/// Un transportista en el ranking del periodo.
class FilaRanking {
  FilaRanking(this.nombre);

  final String nombre;
  int entregadas = 0;
  int total = 0;

  /// Sus guías del periodo.
  final List<Guia> guias = [];

  double get cumplimiento => total == 0 ? 0 : entregadas / total;
}

/// Una agencia de transporte en el periodo: cuántos pedidos le dieron y
/// cuánto se le pagó (de los comprobantes pegados en las guías).
class FilaAgencia {
  FilaAgencia(this.nombre);

  final String nombre;
  String ruc = '';
  int pedidos = 0;
  double costo = 0;

  /// Las guías con comprobante de esta agencia.
  final List<Guia> guias = [];
}

/// Cuenta cada comprobante de agencia una vez aunque esté pegado en varias
/// guías (el monto es uno solo), y junta las guías de una misma agencia
/// aunque la IA haya leído su nombre de otra forma ("PerúBus" del logo y
/// "EMPRESA DE TRANSPORTES PERU BUS S.A" de la razón social): son la misma
/// si comparten RUC, N° de comprobante o el nombre sin palabras genéricas.
class ContadorComprobantes {
  ContadorComprobantes(Iterable<Guia> guias) {
    final conComprobante = guias.where((g) => g.tieneComprobanteAgencia);
    for (final g in conComprobante) {
      final nodos = _nodos(g);
      for (final n in nodos.skip(1)) {
        _unir(nodos.first, n);
      }
    }
    // El nombre de cada agencia: la razón social más completa leída.
    for (final g in conComprobante) {
      final grupo = grupoDe(g);
      final razon = g.agenciaRazonSocial.replaceAll(RegExp(r'\s+'), ' ').trim();
      final actual = _nombres[grupo] ?? '';
      if (razon.length > actual.length) _nombres[grupo] = razon;
      if (g.agenciaRuc.isNotEmpty) _rucs.putIfAbsent(grupo, () => g.agenciaRuc);
    }
    _delDiaConNumero = {
      for (final g in conComprobante)
        if (g.agenciaComprobante.isNotEmpty)
          _delDia(g): 'N|${g.agenciaComprobante}',
    };
    // El monto de cada comprobante: el primero leído en cualquiera de sus
    // guías (en algunas la IA no alcanza a leerlo).
    for (final g in conComprobante) {
      final clave = claveDe(g);
      if (clave != null && g.agenciaMonto != null) {
        _montos.putIfAbsent(clave, () => g.agenciaMonto!);
      }
    }
  }

  final _montos = <String, double>{};

  /// Lo que costó el comprobante de la guía, aunque en esta guía no se haya
  /// leído el monto.
  double? montoDe(Guia g) {
    final clave = claveDe(g);
    return clave == null ? null : _montos[clave];
  }

  final _padre = <String, String>{};
  final _nombres = <String, String>{};
  final _rucs = <String, String>{};

  /// Si en otra guía sí se leyó el número, la que no lo tiene es esa misma.
  late final Map<String, String> _delDiaConNumero;
  final _vistos = <String>{};

  /// Palabras que no distinguen a una agencia de otra.
  static const _genericas = {
    'EMPRESA',
    'DE',
    'DEL',
    'LA',
    'LAS',
    'EL',
    'LOS',
    'Y',
    'E',
    'EN',
    'TRANSPORTES',
    'TRANSPORTE',
    'TRANSPORTS',
    'TURISMO',
    'INTERNACIONAL',
    'SERVICIOS',
    'SERVICIO',
    'CORPORACION',
    'GRUPO',
    'CIA',
    'COMPANIA',
    'SA',
    'SAC',
    'SAA',
    'EIRL',
    'SRL',
    'SCRL',
  };

  /// "EMPRESA DE TRANSPORTES PERU BUS S.A" y "PerúBus" → "PERUBUS".
  static String nucleoNombre(String nombre) {
    const tildes = {'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U'};
    var t = nombre.toUpperCase();
    tildes.forEach((k, v) => t = t.replaceAll(k, v));
    return t
        .split(RegExp(r'[^A-Z0-9Ñ]+'))
        .where((p) => p.length > 1 && !_genericas.contains(p))
        .join();
  }

  static List<String> _nodos(Guia g) {
    final nucleo = nucleoNombre(g.agenciaRazonSocial);
    final nodos = [
      if (g.agenciaRuc.isNotEmpty) 'R|${g.agenciaRuc}',
      if (g.agenciaComprobante.isNotEmpty) 'N|${g.agenciaComprobante}',
      if (nucleo.isNotEmpty) 'M|$nucleo',
    ];
    return nodos.isEmpty ? ['?'] : nodos;
  }

  String _raiz(String n) {
    var r = _padre[n] ?? n;
    while (r != (_padre[r] ?? r)) {
      r = _padre[r]!;
    }
    _padre[n] = r;
    return r;
  }

  void _unir(String a, String b) {
    final ra = _raiz(a);
    final rb = _raiz(b);
    if (ra != rb) _padre[rb] = ra;
  }

  /// La agencia de la guía (la misma para todas sus formas de escribirla).
  String grupoDe(Guia g) => _raiz(_nodos(g).first);

  /// El nombre con el que se muestra la agencia de la guía.
  String nombreDe(Guia g) {
    final grupo = grupoDe(g);
    final nombre = _nombres[grupo] ?? '';
    if (nombre.isNotEmpty) return nombre;
    final ruc = _rucs[grupo] ?? '';
    return ruc.isNotEmpty ? 'RUC $ruc' : 'Sin nombre';
  }

  String rucDe(Guia g) => _rucs[grupoDe(g)] ?? '';

  /// Sin número leído: el mismo monto de la misma agencia, del mismo
  /// transportista y el mismo día se toma como el mismo comprobante.
  String _delDia(Guia g) {
    final creada = g.fechaCreacion.toLocal();
    return '${grupoDe(g)}|${g.agenciaMonto}'
        '|${g.transportista.trim().toLowerCase()}'
        '|${creada.year}-${creada.month}-${creada.day}';
  }

  /// El comprobante de la guía: el mismo para todas las guías que lo
  /// llevan pegado; null si la guía no tiene comprobante.
  String? claveDe(Guia g) {
    if (!g.tieneComprobanteAgencia) return null;
    if (g.agenciaComprobante.isNotEmpty) return 'N|${g.agenciaComprobante}';
    final clave = _delDia(g);
    return _delDiaConNumero[clave] ?? 'D|$clave';
  }

  /// ¿Es un comprobante que aún no se contó? (y lo marca como contado).
  bool esNuevo(Guia g) {
    final clave = claveDe(g);
    if (clave == null) return false;
    // Sin número pero del mismo día que uno con número: es ese, y ese se
    // cuenta en su propia guía.
    if (clave.startsWith('N|') && g.agenciaComprobante.isEmpty) return false;
    return _vistos.add(clave);
  }

  /// Cuántos comprobantes distintos hay en las guías y cuánto suman.
  static ({int comprobantes, double costo}) total(Iterable<Guia> guias) {
    final contador = ContadorComprobantes(guias);
    var comprobantes = 0;
    var costo = 0.0;
    for (final g in guias) {
      if (!contador.esNuevo(g)) continue;
      comprobantes++;
      costo += contador.montoDe(g) ?? 0;
    }
    return (comprobantes: comprobantes, costo: costo);
  }
}

/// "S/ 1,234.50".
String soles(double monto) => 'S/ ${NumberFormat('#,##0.00').format(monto)}';

/// Los números del dashboard, calculados de las guías del periodo con la
/// misma regla que la vista Transportistas (ver [PeriodoResumen.incluye]).
class IndicadoresOperacion {
  IndicadoresOperacion._(this.periodo);

  factory IndicadoresOperacion.calcular(
    Iterable<Guia> todas,
    PeriodoResumen periodo, {
    required DateTime ahora,
    Set<String> sucursales = const {},
  }) {
    final r = IndicadoresOperacion._(periodo);
    final ranking = <String, FilaRanking>{};
    final agencias = <String, FilaAgencia>{};
    // Cada comprobante suma una vez aunque esté pegado en varias guías.
    final contador = ContadorComprobantes(
      todas.where((g) => periodo.incluye(g, ahora)),
    );
    final tiempos = <Duration>[];
    final sucursalesMin = {for (final s in sucursales) s.toLowerCase()};

    for (final g in todas) {
      if (!periodo.incluye(g, ahora)) continue;
      r.guias.add(g);
      final grupo = g.estado.grupo;
      final nombre = g.transportista.trim().isEmpty
          ? 'Sin transportista'
          : g.transportista.trim();
      final fila = ranking.putIfAbsent(nombre, () => FilaRanking(nombre));
      fila.total++;
      fila.guias.add(g);
      switch (grupo) {
        case GrupoEstado.entregado:
          r.entregadas++;
          fila.entregadas++;
          final cierre = g.fechaCierre ?? g.fechaActualizacion;
          final demora = cierre.difference(g.fechaCreacion);
          if (!demora.isNegative) tiempos.add(demora);
          if (sucursalesMin.contains(g.destino.trim().toLowerCase())) {
            r.enSucursal++;
            r.entregadasEnSucursal.add(g);
          }
        case GrupoEstado.rechazado:
          r.rechazadas++;
        case GrupoEstado.enRuta:
        case GrupoEstado.trasbordo:
          r.pendientes++;
          if (ahora.difference(g.fechaCreacion) > limiteAtraso) {
            r.atrasadas.add(g);
          }
      }
      if (g.eliminacionPendiente) r.pidenEliminar.add(g);
      if (g.tieneComprobanteAgencia) {
        final fila = agencias.putIfAbsent(
          contador.grupoDe(g),
          () => FilaAgencia(contador.nombreDe(g))..ruc = contador.rucDe(g),
        );
        fila.pedidos++;
        fila.guias.add(g);
        if (contador.esNuevo(g)) {
          r.comprobantes++;
          if (contador.montoDe(g) case final m?) {
            fila.costo += m;
            r.costoAgencias += m;
          }
        }
        if (contador.montoDe(g) != null) r.pedidosConMonto++;
      }
      if (g.tipoEntrega == TipoEntrega.agencia) {
        r.agencia++;
      } else {
        r.clienteFinal++;
      }
    }

    if (tiempos.isNotEmpty) {
      final suma = tiempos.fold(Duration.zero, (a, b) => a + b);
      r.tiempoPromedio = suma ~/ tiempos.length;
    }
    r.transportistasActivos = ranking.keys
        .where((n) => n != 'Sin transportista')
        .length;
    r.ranking = ranking.values.toList()
      ..sort((a, b) {
        final porEntregas = b.entregadas.compareTo(a.entregadas);
        return porEntregas != 0 ? porEntregas : b.total.compareTo(a.total);
      });
    r.atrasadas.sort((a, b) => a.fechaCreacion.compareTo(b.fechaCreacion));
    r.agencias = agencias.values.toList()
      ..sort((a, b) {
        final porCosto = b.costo.compareTo(a.costo);
        return porCosto != 0 ? porCosto : b.pedidos.compareTo(a.pedidos);
      });
    r.serie = _serie(r.guias, periodo, ahora);
    return r;
  }

  final PeriodoResumen periodo;
  final List<Guia> guias = [];
  int entregadas = 0;
  int rechazadas = 0;
  int pendientes = 0;
  int clienteFinal = 0;
  int agencia = 0;
  int enSucursal = 0;
  final List<Guia> entregadasEnSucursal = [];
  int transportistasActivos = 0;
  Duration? tiempoPromedio;
  final List<Guia> atrasadas = [];
  final List<Guia> pidenEliminar = [];
  List<FilaRanking> ranking = [];
  List<PuntoSerie> serie = [];

  /// Comprobantes de agencia distintos del periodo y su total (cada
  /// comprobante una vez, aunque esté en varias guías); pedidos con monto.
  int comprobantes = 0;
  int pedidosConMonto = 0;
  double costoAgencias = 0;

  /// Por agencia, de la de más costo a la de menos.
  List<FilaAgencia> agencias = [];

  /// Lo que costó en promedio cada pedido enviado por agencia (un
  /// comprobante de dos pedidos cuenta la mitad para cada uno).
  double? get costoPromedioAgencia =>
      pedidosConMonto == 0 ? null : costoAgencias / pedidosConMonto;

  int get total => guias.length;

  List<Guia> de(Set<GrupoEstado> grupos) =>
      guias.where((g) => grupos.contains(g.estado.grupo)).toList();

  List<Guia> get conComprobante =>
      guias.where((g) => g.tieneComprobanteAgencia).toList();

  /// Cierre: las que ya terminaron (entregadas o rechazadas) sobre todas.
  double get cierre => total == 0 ? 0 : (entregadas + rechazadas) / total;

  /// Eficiencia: solo las entregadas sobre todas (un rechazo cierra la
  /// tarea, pero no es una entrega).
  double get eficiencia => total == 0 ? 0 : entregadas / total;

  double get tasaRechazo => total == 0 ? 0 : rechazadas / total;

  /// Un solo día (hoy u otro), por hora; si no, por día.
  bool get porHora => periodo.unDia;

  /// Un rango de más de dos meses, por mes.
  bool get porMes {
    if (periodo.unDia) return false;
    final (desde, hasta) = periodo.dias(DateTime.now());
    return hasta.difference(desde).inDays + 1 > 62;
  }
}

List<PuntoSerie> _serie(
  List<Guia> guias,
  PeriodoResumen periodo,
  DateTime ahora,
) {
  final cerradas = [
    for (final g in guias)
      if (g.estado.esCerrada) g,
  ];
  DateTime cierre(Guia g) => (g.fechaCierre ?? g.fechaActualizacion).toLocal();
  void sumar(PuntoSerie p, Guia g) {
    p.guias.add(g);
    if (g.estado.grupo == GrupoEstado.rechazado) {
      p.rechazadas++;
    } else {
      p.entregadas++;
    }
  }

  if (periodo.unDia) {
    // Solo los cierres de ese día (una guía del día pudo cerrarse después).
    final (dia, _) = periodo.dias(ahora);
    cerradas.retainWhere((g) {
      final c = cierre(g);
      return c.year == dia.year && c.month == dia.month && c.day == dia.day;
    });
    // De 7 a 19 h, estirando si hubo movimiento antes o después.
    var desde = 7;
    var hasta = 19;
    for (final g in cerradas) {
      final h = cierre(g).hour;
      if (h < desde) desde = h;
      if (h > hasta) hasta = h;
    }
    final puntos = {
      for (var h = desde; h <= hasta; h++)
        h: PuntoSerie(
          '$h h',
          '${h.toString().padLeft(2, '0')}:00 – '
              '${h.toString().padLeft(2, '0')}:59',
        ),
    };
    for (final g in cerradas) {
      sumar(puntos[cierre(g).hour]!, g);
    }
    return puntos.values.toList();
  }

  final (desde, hasta) = periodo.dias(ahora);
  final dias = hasta.difference(desde).inDays + 1;
  const dias3 = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  const diasLargos = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];
  const meses = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];
  // Un rango largo se resume por mes para que las barras se lean.
  if (dias > 62) {
    final porMes = <(int, int), PuntoSerie>{
      for (
        var m = DateTime(desde.year, desde.month);
        !m.isAfter(hasta);
        m = DateTime(m.year, m.month + 1)
      )
        (m.year, m.month): PuntoSerie(
          '${meses[m.month - 1].substring(0, 3)} ${m.year % 100}',
          '${meses[m.month - 1][0].toUpperCase()}'
              '${meses[m.month - 1].substring(1)} de ${m.year}',
        ),
    };
    for (final g in cerradas) {
      final c = cierre(g);
      final punto = porMes[(c.year, c.month)];
      if (punto != null && !c.isBefore(desde)) sumar(punto, g);
    }
    return porMes.values.toList();
  }
  final puntos = [
    for (var i = 0; i < dias; i++)
      () {
        final dia = DateTime(desde.year, desde.month, desde.day + i);
        return PuntoSerie(
          dias > 10 ? '${dia.day}' : '${dias3[dia.weekday - 1]} ${dia.day}',
          '${diasLargos[dia.weekday - 1]} ${dia.day} de ${meses[dia.month - 1]}',
        );
      }(),
  ];
  for (final g in cerradas) {
    final c = cierre(g);
    final i = DateTime(c.year, c.month, c.day).difference(desde).inDays;
    if (i >= 0 && i < dias) sumar(puntos[i], g);
  }
  return puntos;
}

String formatoDuracion(Duration d) {
  if (d.inMinutes < 1) return 'menos de 1 min';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 24) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
  }
  final h = d.inHours % 24;
  return h == 0 ? '${d.inDays} d' : '${d.inDays} d $h h';
}

String _porcentaje(double v) => '${(v * 100).round()}%';

/// Pestaña "Dashboard" del administrador: los indicadores principales de la
/// operación en el periodo elegido.
class PestanaDashboard extends StatefulWidget {
  const PestanaDashboard({super.key});

  @override
  State<PestanaDashboard> createState() => _PestanaDashboardState();
}

class _PestanaDashboardState extends State<PestanaDashboard> {
  PeriodoResumen _periodo = PeriodoResumen.hoy;

  /// Viendo "Análisis de agencias" en vez del resumen general.
  bool _agencias = false;

  @override
  Widget build(BuildContext context) {
    final vista = _Segmentos(
      opciones: const ['General', 'Análisis de agencias'],
      iconos: const {
        0: Icons.bar_chart_rounded,
        1: Icons.local_shipping_outlined,
      },
      elegido: _agencias ? 1 : 0,
      onCambio: (i) => setState(() => _agencias = i == 1),
    );
    if (_agencias) {
      return RefreshIndicator(
        onRefresh: () => context.read<AppState>().cargarGuias(),
        child: VistaAnalisisAgencias(
          cabecera: Align(alignment: Alignment.centerLeft, child: vista),
          periodo: _periodo,
          onPeriodo: (p) => setState(() => _periodo = p),
        ),
      );
    }
    final appState = context.watch<AppState>();
    final datos = IndicadoresOperacion.calcular(
      appState.guias,
      _periodo,
      ahora: DateTime.now(),
      sucursales: {for (final s in appState.sucursales) s.nombre},
    );

    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().cargarGuias(),
      child: LayoutBuilder(
        builder: (context, c) {
          final ancho = c.maxWidth;
          final ancha = ancho >= 1000;
          const sep = 16.0;

          void ver(String titulo, List<Guia> guias) => mostrarGuiasDelDashboard(
            context,
            titulo,
            guias,
            periodo: datos.periodo.etiqueta,
          );
          final entregadas = datos.de({GrupoEstado.entregado});
          final cifras = [
            _Cifra(
              onTap: () => ver('Guías del periodo', datos.guias),
              etiqueta: 'Guías del periodo',
              valor: '${datos.total}',
              detalle:
                  '${datos.clienteFinal} cliente · ${datos.agencia} agencia',
            ),
            _Cifra(
              onTap: () => ver('Entregadas', entregadas),
              etiqueta: 'Entregadas',
              valor: '${datos.entregadas}',
              detalle: datos.enSucursal == 0
                  ? 'a cliente o agencia'
                  : '${datos.enSucursal} en sucursal',
              marca: _colorEntregado,
            ),
            _Cifra(
              onTap: () => ver(
                'En ruta',
                datos.de({GrupoEstado.enRuta, GrupoEstado.trasbordo}),
              ),
              etiqueta: 'En ruta',
              valor: '${datos.pendientes}',
              detalle: datos.atrasadas.isEmpty
                  ? 'ninguna atrasada'
                  : '${datos.atrasadas.length} con más de 24 h',
              marca: _colorEnRuta,
            ),
            _Cifra(
              onTap: () => ver('Rechazadas', datos.de({GrupoEstado.rechazado})),
              etiqueta: 'Rechazadas',
              valor: '${datos.rechazadas}',
              detalle: '${_porcentaje(datos.tasaRechazo)} del total',
              marca: _colorRechazado,
            ),
            _Cifra(
              onTap: () => ver('Entregadas', entregadas),
              etiqueta: 'Tiempo promedio',
              valor: datos.tiempoPromedio == null
                  ? '—'
                  : formatoDuracion(datos.tiempoPromedio!),
              detalle: 'hasta la entrega',
            ),
            _Cifra(
              onTap: () => ver('Guías de los transportistas', datos.guias),
              etiqueta: 'Transportistas',
              valor: '${datos.transportistasActivos}',
              detalle: datos.transportistasActivos == 0
                  ? 'sin movimiento'
                  : 'activos en el periodo',
            ),
            _Cifra(
              onTap: () => ver('Enviadas por agencia', datos.conComprobante),
              etiqueta: 'Costo de agencias',
              valor: soles(datos.costoAgencias),
              detalle: datos.comprobantes == 0
                  ? 'sin comprobantes'
                  : datos.comprobantes == 1
                  ? '1 comprobante'
                  : '${datos.comprobantes} comprobantes',
            ),
            _Cifra(
              onTap: () => ver('Enviadas por agencia', datos.conComprobante),
              etiqueta: 'Costo por pedido',
              valor: datos.costoPromedioAgencia == null
                  ? '—'
                  : soles(datos.costoPromedioAgencia!),
              detalle: 'promedio por pedido',
            ),
          ];

          // 8 cifras: 4 por fila en computadora, 2 en lo demás.
          final columnasCifras = ancha ? 4 : 2;
          final anchoGrilla = ancha ? (ancho - 48 - sep) * 0.64 : ancho - 48;
          final anchoCifra =
              (anchoGrilla - sep * (columnasCifras - 1)) / columnasCifras;
          final grilla = Wrap(
            spacing: sep,
            runSpacing: sep,
            children: [
              for (final cifra in cifras)
                SizedBox(width: anchoCifra, child: cifra),
            ],
          );
          final hero = _Tocable(
            onTap: () => ver('Guías del periodo', datos.guias),
            child: _Cumplimiento(datos: datos),
          );
          final grafico = _GraficoEntregas(datos: datos);
          final estados = _Estados(datos: datos);
          final ranking = _Ranking(datos: datos);
          // Con el mismo cálculo que "Análisis de agencias".
          final agencias = _Agencias(
            analisis: AnalisisAgencias.calcular(
              appState.guias,
              _periodo,
              ahora: DateTime.now(),
              sucursales: [for (final s in appState.sucursales) s.nombre],
              conAnterior: false,
            ),
            onAnalisis: () => setState(() => _agencias = true),
          );

          Widget fila(List<Widget> hijos, List<int> flex) => IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < hijos.length; i++) ...[
                  if (i > 0) const SizedBox(width: sep),
                  Expanded(flex: flex[i], child: hijos[i]),
                ],
              ],
            ),
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  vista,
                  SelectorPeriodo(
                    periodo: _periodo,
                    onCambio: (p) => setState(() => _periodo = p),
                  ),
                ],
              ),
              const SizedBox(height: sep),
              if (ancha) ...[
                fila([hero, grilla], [36, 64]),
                const SizedBox(height: sep),
                fila([grafico, estados], [62, 38]),
                const SizedBox(height: sep),
                // Agencias donde estaba "Requiere atención" (las atrasadas
                // siguen en la cifra "En ruta").
                fila([ranking, agencias], [50, 50]),
              ] else ...[
                hero,
                const SizedBox(height: sep),
                grilla,
                const SizedBox(height: sep),
                grafico,
                const SizedBox(height: sep),
                estados,
                const SizedBox(height: sep),
                ranking,
                const SizedBox(height: sep),
                agencias,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.child,
    this.titulo,
    this.subtitulo,
    this.onTap,
  });

  final String? titulo;
  final String? subtitulo;
  final Widget child;

  /// Si se puede tocar: abre el detalle (las guías detrás del número).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tarjeta = _cuerpo();
    if (onTap == null) return tarjeta;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: tarjeta),
    );
  }

  Widget _cuerpo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Ipesa.borde),
        borderRadius: BorderRadius.circular(16),
        boxShadow: Ipesa.sombraSuave,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (titulo != null) ...[
            Text(titulo!, style: Ipesa.titulo(17, color: Ipesa.texto)),
            if (subtitulo != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitulo!,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Ipesa.textoSuave,
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],
          child,
        ],
      ),
    );
  }
}

/// Una cifra: etiqueta, valor y una línea de contexto.
class _Cifra extends StatelessWidget {
  const _Cifra({
    required this.etiqueta,
    required this.valor,
    required this.detalle,
    this.marca,
    this.onTap,
  });

  final VoidCallback? onTap;

  final String etiqueta;
  final String valor;
  final String detalle;

  /// Punto de color del estado (la cifra sigue en tinta de texto).
  final Color? marca;

  @override
  Widget build(BuildContext context) {
    return _Tarjeta(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (marca != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: marca,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Text(
                  etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Ipesa.textoSuave,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor, style: Ipesa.titulo(28, color: Ipesa.texto)),
          ),
          const SizedBox(height: 4),
          Text(
            detalle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Ipesa.textoSuave),
          ),
        ],
      ),
    );
  }
}

/// La cifra principal: qué parte de las guías del periodo ya se entregó.
class _Cumplimiento extends StatelessWidget {
  const _Cumplimiento({required this.datos});

  final IndicadoresOperacion datos;

  static const _verde = Color(0xFF7FD6C8);
  static const _rojo = Color(0xFFF2A39B);

  @override
  Widget build(BuildContext context) {
    final vacio = datos.total == 0;
    Widget cifra(String etiqueta, double valor, String detalle) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiqueta,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Ipesa.suaveSobrePetroleo,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              vacio ? '—' : _porcentaje(valor),
              style: Ipesa.titulo(48, color: Colors.white),
            ),
          ),
          Text(
            detalle,
            style: const TextStyle(fontSize: 14, color: Colors.white),
          ),
        ],
      ),
    );
    Widget muestra(Color color, String texto) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(texto, style: const TextStyle(fontSize: 13, color: Colors.white)),
      ],
    );
    final cerradas = datos.entregadas + datos.rechazadas;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14606F), Ipesa.petroleo],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            datos.periodo.etiqueta,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: Ipesa.suaveSobrePetroleo,
            ),
          ),
          const SizedBox(height: 12),
          if (vacio)
            const Text(
              'Aún no hay guías en este periodo.',
              style: TextStyle(fontSize: 15, color: Colors.white),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cifra(
                  'Cierre',
                  datos.cierre,
                  '$cerradas de ${datos.total} finalizadas',
                ),
                const SizedBox(width: 16),
                cifra(
                  'Eficiencia',
                  datos.eficiencia,
                  '${datos.entregadas} de ${datos.total} entregadas',
                ),
              ],
            ),
          const SizedBox(height: 18),
          // Entregadas y rechazadas llenan la barra; lo que falta sigue en
          // ruta.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  if (datos.entregadas > 0)
                    Expanded(
                      flex: datos.entregadas,
                      child: Container(color: _verde),
                    ),
                  if (datos.entregadas > 0 && datos.rechazadas > 0)
                    const SizedBox(width: 2),
                  if (datos.rechazadas > 0)
                    Expanded(
                      flex: datos.rechazadas,
                      child: Container(color: _rojo),
                    ),
                  if (datos.pendientes > 0 || vacio)
                    Expanded(
                      flex: vacio ? 1 : datos.pendientes,
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!vacio) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                muestra(
                  _verde,
                  datos.entregadas == 1
                      ? '1 entregada'
                      : '${datos.entregadas} entregadas',
                ),
                muestra(
                  _rojo,
                  datos.rechazadas == 1
                      ? '1 rechazada'
                      : '${datos.rechazadas} rechazadas',
                ),
                muestra(
                  Colors.white.withValues(alpha: 0.35),
                  '${datos.pendientes} en ruta',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Entregas y rechazos por hora (hoy) o por día.
class _GraficoEntregas extends StatelessWidget {
  const _GraficoEntregas({required this.datos});

  final IndicadoresOperacion datos;

  static const _alto = 180.0;

  @override
  Widget build(BuildContext context) {
    final serie = datos.serie;
    final maximo = serie.fold(0, (m, p) => p.total > m ? p.total : m);
    final tope = _topeRedondo(maximo);
    final marcas = [for (var i = 0; i <= 2; i++) tope * i ~/ 2];
    final etiquetaCada = serie.length > 16 ? 5 : (serie.length > 10 ? 2 : 1);

    return _Tarjeta(
      titulo: datos.porHora
          ? 'Cierres por hora'
          : datos.porMes
          ? 'Cierres por mes'
          : 'Cierres por día',
      subtitulo: 'Guías entregadas y rechazadas en el periodo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            spacing: 16,
            children: [
              _Muestra(color: _colorEntregado, texto: 'Entregadas'),
              _Muestra(color: _colorRechazado, texto: 'Rechazadas'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: _alto + 34,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Eje: tres marcas redondas.
                SizedBox(
                  width: 28,
                  height: _alto + 34,
                  child: Stack(
                    children: [
                      for (final m in marcas)
                        Positioned(
                          right: 6,
                          bottom: 24 + _alto * m / tope - 8,
                          child: Text(
                            '$m',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Ipesa.textoSuave,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      for (final m in marcas)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 24 + _alto * m / tope,
                          child: Container(
                            height: 1,
                            color: m == 0 ? Ipesa.borde : Ipesa.segmento,
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < serie.length; i++)
                            Expanded(
                              child: _Columna(
                                onTap: () => mostrarGuiasDelDashboard(
                                  context,
                                  'Cierres · ${serie[i].detalle}',
                                  serie[i].guias,
                                ),
                                punto: serie[i],
                                tope: tope,
                                alto: _alto,
                                conEtiqueta:
                                    i % etiquetaCada == 0 ||
                                    i == serie.length - 1,
                              ),
                            ),
                        ],
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

  static int _topeRedondo(int maximo) {
    if (maximo <= 4) return 4;
    for (final paso in [2, 5, 10, 20, 25, 50, 100, 200, 500]) {
      if (maximo <= paso * 2) return paso * 2;
    }
    return ((maximo + 999) ~/ 1000) * 1000;
  }
}

class _Columna extends StatelessWidget {
  const _Columna({
    required this.punto,
    required this.tope,
    required this.alto,
    required this.conEtiqueta,
    this.onTap,
  });

  final VoidCallback? onTap;
  final PuntoSerie punto;
  final int tope;
  final double alto;
  final bool conEtiqueta;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) => _columna(c.maxWidth));
  }

  Widget _columna(double ancho) {
    final mensaje = punto.total == 0
        ? '${punto.detalle}\nSin cierres'
        : '${punto.detalle}\n'
              '${punto.entregadas} entregada${punto.entregadas == 1 ? '' : 's'} · '
              '${punto.rechazadas} rechazada${punto.rechazadas == 1 ? '' : 's'}';
    return Tooltip(
      message: mensaje,
      waitDuration: Duration.zero,
      child: _Tocable(
        onTap: punto.total == 0 ? null : onTap,
        child: _barra(ancho),
      ),
    );
  }

  Widget _barra(double ancho) {
    // El separador de 2 px entre los dos tramos sale del mismo alto, para
    // que la barra más alta no se pase de la columna.
    final hueco = punto.rechazadas > 0 && punto.entregadas > 0 ? 2.0 : 0.0;
    final altoEntregadas = (alto - hueco) * punto.entregadas / tope;
    final altoRechazadas = (alto - hueco) * punto.rechazadas / tope;
    const extremo = Radius.circular(4);
    return Container(
      // Zona de toque de todo el alto, más ancha que la barra.
      color: Colors.transparent,
      height: alto + 24,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Center(
            child: SizedBox(
              // Hasta 22 px, dejando siempre aire entre columnas.
              width: math.min(22, math.max(4, ancho - 6)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (punto.rechazadas > 0)
                    Container(
                      height: altoRechazadas,
                      decoration: const BoxDecoration(
                        color: _colorRechazado,
                        borderRadius: BorderRadius.vertical(top: extremo),
                      ),
                    ),
                  if (hueco > 0) SizedBox(height: hueco),
                  if (punto.entregadas > 0)
                    Container(
                      height: altoEntregadas,
                      decoration: BoxDecoration(
                        color: _colorEntregado,
                        borderRadius: punto.rechazadas > 0
                            ? null
                            : const BorderRadius.vertical(top: extremo),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 24,
            child: conEtiqueta
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        punto.etiqueta,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Ipesa.textoSuave,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _Muestra extends StatelessWidget {
  const _Muestra({required this.color, required this.texto});

  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          texto,
          style: const TextStyle(fontSize: 13, color: Ipesa.etiqueta),
        ),
      ],
    );
  }
}

/// Cómo se reparten las guías del periodo: una barra al 100 % y el detalle.
class _Estados extends StatelessWidget {
  const _Estados({required this.datos});

  final IndicadoresOperacion datos;

  @override
  Widget build(BuildContext context) {
    final partes = [
      ('Entregadas', datos.entregadas, _colorEntregado),
      ('En ruta', datos.pendientes, _colorEnRuta),
      ('Rechazadas', datos.rechazadas, _colorRechazado),
    ];
    final grupos = {
      'Entregadas': {GrupoEstado.entregado},
      'En ruta': {GrupoEstado.enRuta, GrupoEstado.trasbordo},
      'Rechazadas': {GrupoEstado.rechazado},
    };
    void ver(String titulo, List<Guia> guias) => mostrarGuiasDelDashboard(
      context,
      titulo,
      guias,
      periodo: datos.periodo.etiqueta,
    );
    final conValor = [
      for (final p in partes)
        if (p.$2 > 0) p,
    ];
    return _Tarjeta(
      titulo: 'Estado de las guías',
      subtitulo: '${datos.total} en el periodo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 14,
              child: conValor.isEmpty
                  ? Container(color: Ipesa.segmento)
                  : Row(
                      children: [
                        for (var i = 0; i < conValor.length; i++) ...[
                          if (i > 0) const SizedBox(width: 2),
                          Expanded(
                            flex: conValor[i].$2,
                            child: Container(color: conValor[i].$3),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 18),
          for (final (nombre, n, color) in partes)
            _Tocable(
              onTap: n == 0
                  ? null
                  : () => ver(nombre, datos.de(grupos[nombre]!)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        nombre,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Ipesa.etiqueta,
                        ),
                      ),
                    ),
                    Text(
                      '$n',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Ipesa.texto,
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(
                        datos.total == 0 ? '' : _porcentaje(n / datos.total),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Ipesa.textoSuave,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 20, color: Ipesa.segmento),
          const Text(
            'Por tipo de entrega',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Ipesa.textoSuave,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Dato(
                valor: datos.clienteFinal,
                texto: 'Cliente final',
                onTap: () => ver(
                  'Cliente final',
                  datos.guias
                      .where((g) => g.tipoEntrega != TipoEntrega.agencia)
                      .toList(),
                ),
              ),
              _Dato(
                valor: datos.agencia,
                texto: 'Agencia',
                onTap: () => ver(
                  'Entrega en agencia',
                  datos.guias
                      .where((g) => g.tipoEntrega == TipoEntrega.agencia)
                      .toList(),
                ),
              ),
              _Dato(
                valor: datos.enSucursal,
                texto: 'Entregadas en sucursal',
                onTap: () =>
                    ver('Entregadas en sucursal', datos.entregadasEnSucursal),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.valor, required this.texto, this.onTap});

  final int valor;
  final String texto;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: _Tocable(
        onTap: valor == 0 ? null : onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$valor', style: Ipesa.titulo(20, color: Ipesa.texto)),
            Text(
              texto,
              style: const TextStyle(fontSize: 13, color: Ipesa.textoSuave),
            ),
          ],
        ),
      ),
    );
  }
}

/// Los transportistas del periodo, del que más entregó al que menos.
class _Ranking extends StatelessWidget {
  const _Ranking({required this.datos});

  final IndicadoresOperacion datos;

  static const _visibles = 6;

  @override
  Widget build(BuildContext context) {
    final filas = datos.ranking.take(_visibles).toList();
    return _Tarjeta(
      titulo: 'Ranking de transportistas',
      subtitulo: 'Entregadas sobre sus guías del periodo',
      child: filas.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Sin guías en este periodo.',
                style: TextStyle(color: Ipesa.textoSuave),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < filas.length; i++)
                  _Tocable(
                    onTap: () => mostrarGuiasDelDashboard(
                      context,
                      filas[i].nombre,
                      filas[i].guias,
                      periodo: datos.periodo.etiqueta,
                    ),
                    child: _FilaTransportista(puesto: i + 1, fila: filas[i]),
                  ),
                if (datos.ranking.length > _visibles)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'y ${datos.ranking.length - _visibles} más en '
                      'Transportistas',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Ipesa.textoSuave,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _FilaTransportista extends StatelessWidget {
  const _FilaTransportista({required this.puesto, required this.fila});

  final int puesto;
  final FilaRanking fila;

  @override
  Widget build(BuildContext context) {
    final iniciales = fila.nombre
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$puesto',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Ipesa.textoSuave,
              ),
            ),
          ),
          CircleAvatar(
            radius: 17,
            backgroundColor: puesto == 1
                ? const Color(0xFFFDE7CF)
                : Ipesa.menta,
            child: Text(
              iniciales,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: puesto == 1 ? const Color(0xFF9A4A0B) : Ipesa.petroleo,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        fila.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Ipesa.texto,
                        ),
                      ),
                    ),
                    Text(
                      '${fila.entregadas} de ${fila.total}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Ipesa.etiqueta,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: SizedBox(
                          height: 6,
                          child: Stack(
                            children: [
                              Container(color: Ipesa.menta),
                              FractionallySizedBox(
                                widthFactor: fila.cumplimiento,
                                child: Container(color: Ipesa.turquesa),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        _porcentaje(fila.cumplimiento),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Ipesa.etiqueta,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pedidos y costo por agencia de transporte (de los comprobantes leídos de
/// las fotos), igual que el ranking de "Análisis de agencias": una barra
/// por agencia, larga según lo que se le pagó.
class _Agencias extends StatelessWidget {
  const _Agencias({required this.analisis, this.onAnalisis});

  final AnalisisAgencias analisis;

  /// Abre "Análisis de agencias".
  final VoidCallback? onAnalisis;

  static const _visibles = 8;

  @override
  Widget build(BuildContext context) {
    final todas = analisis.agencias;
    // Más de [_visibles]: las de menos costo se juntan en "Otras".
    final filas = todas.length <= _visibles
        ? todas
        : [
            ...todas.take(_visibles - 1),
            todas
                .skip(_visibles - 1)
                .fold(
                  FilaAnalisis(
                    'Otras ${todas.length - _visibles + 1} agencias',
                  ),
                  (otras, a) => otras
                    ..costo += a.costo
                    ..guias.addAll(a.guias)
                    ..comprobantes.addAll(a.comprobantes),
                ),
          ];
    final maximo = filas.fold<double>(0, (m, a) => math.max(m, a.costo));
    return _Tarjeta(
      titulo: 'Agencias',
      subtitulo: 'Pedidos enviados y costo pagado a cada agencia en el periodo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (filas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Sin comprobantes de agencia en este periodo.',
                style: TextStyle(color: Ipesa.textoSuave),
              ),
            ),
          for (final a in filas)
            _Tocable(
              onTap: () => mostrarGuiasDelDashboard(
                context,
                a.nombre,
                a.guias,
                periodo: analisis.periodo.etiqueta,
              ),
              child: _FilaBarra(
                nombre: a.nombre,
                tooltip: [
                  a.nombre,
                  if (a.ruc.isNotEmpty) 'RUC ${a.ruc}',
                ].join('\n'),
                derecha: soles(a.costo),
                detalle:
                    '${_plural(a.guias.length, 'guía')} · '
                    '${_plural(a.comprobantes.length, 'comprobante')}',
                fraccion: maximo == 0 ? 0 : a.costo / maximo,
              ),
            ),
          if (onAnalisis != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onAnalisis,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Ver análisis de agencias'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Algo del dashboard que se puede tocar para ver su detalle.
class _Tocable extends StatelessWidget {
  const _Tocable({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }
}

/// Las guías detrás de un número o gráfico del dashboard, de la más
/// reciente a la más antigua; tocar una abre su detalle.
void mostrarGuiasDelDashboard(
  BuildContext context,
  String titulo,
  List<Guia> guias, {
  String? periodo,
}) {
  final ordenadas = [...guias]
    ..sort((a, b) => b.fechaActualizacion.compareTo(a.fechaActualizacion));
  final cuantas = ordenadas.length == 1
      ? '1 guía'
      : '${ordenadas.length} guías';
  final pagado = ContadorComprobantes.total(ordenadas);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Ipesa.fondo,
    constraints: const BoxConstraints(maxWidth: 760),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, style: Ipesa.titulo(19, color: Ipesa.texto)),
                      Text(
                        periodo == null ? cuantas : '$cuantas · $periodo',
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Ipesa.textoSuave,
                        ),
                      ),
                      // Lo pagado a agencias: cada comprobante una vez.
                      if (pagado.comprobantes > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Total pagado: ${soles(pagado.costo)} · '
                            '${pagado.comprobantes == 1 ? '1 comprobante' : '${pagado.comprobantes} comprobantes'}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Ipesa.petroleo,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ordenadas.isEmpty
                ? const Center(
                    child: Text(
                      'Sin guías.',
                      style: TextStyle(color: Ipesa.textoSuave),
                    ),
                  )
                : ListView.separated(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: ordenadas.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => TarjetaGuiaAdmin(guia: ordenadas[i]),
                  ),
          ),
        ],
      ),
    ),
  );
}
