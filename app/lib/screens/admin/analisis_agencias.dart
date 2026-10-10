part of 'dashboard.dart';

// Análisis de Agencias: solo los envíos por agencia de transporte, con
// filtros de fechas, agencia, cliente, transportista y sucursal de salida.
// Un comprobante puede venir pegado en varias guías: se cuenta una vez y su
// monto se reparte en partes iguales entre esas guías (para el costo por
// cliente, transportista o sucursal).

/// ¿Es un envío por agencia? Con comprobante leído, o marcada como agencia
/// (aunque la IA aún no lea su comprobante) y no rechazada.
bool esEnvioPorAgencia(Guia g) =>
    g.tieneComprobanteAgencia ||
    (g.tipoEntrega == TipoEntrega.agencia &&
        g.estado.grupo != GrupoEstado.rechazado);

String _sinEspacios(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

String clienteDe(Guia g) {
  final c = _sinEspacios(g.destinatario);
  return c.isEmpty ? 'Sin cliente' : c;
}

String transportistaDe(Guia g) {
  final t = _sinEspacios(g.transportista);
  return t.isEmpty ? 'Sin transportista' : t;
}

const fueraDeSucursal = 'Fuera de sucursal';

/// Un comprobante de agencia y las guías que lo llevan pegado.
class ComprobanteAgencia {
  ComprobanteAgencia(this.clave, this.agencia, this.ruc);

  final String clave;
  final String agencia;
  final String ruc;

  /// El monto leído (el primero que se leyó, si hay varios).
  double? monto;

  /// Los montos distintos leídos en sus guías (más de uno: hay que revisar).
  final Set<double> montosLeidos = {};

  /// Todas sus guías del periodo, aunque un filtro oculte algunas.
  final List<Guia> todas = [];

  /// Sus guías que pasan los filtros.
  final List<Guia> guias = [];

  /// N° del comprobante; vacío si la IA no lo leyó.
  String get numero => clave.startsWith('N|') ? clave.substring(2) : '';

  bool get sinMonto => monto == null || monto == 0;

  /// La parte del monto que corresponde a cada una de sus guías.
  double get porGuia =>
      monto == null || todas.isEmpty ? 0 : monto! / todas.length;

  /// Lo pagado por las guías que se ven (todo, si no hay filtros que
  /// oculten alguna de sus guías).
  double get pagado => porGuia * guias.length;

  /// El día del envío: el de su guía más antigua.
  DateTime get fecha => guias
      .map((g) => g.fechaCreacion.toLocal())
      .reduce((a, b) => a.isBefore(b) ? a : b);
}

/// Una agencia, cliente, transportista o sucursal en el análisis.
class FilaAnalisis {
  FilaAnalisis(this.nombre);

  final String nombre;
  String ruc = '';
  final List<Guia> guias = [];
  final Set<String> comprobantes = {};
  final Set<String> agencias = {};
  double costo = 0;

  double? get porComprobante =>
      comprobantes.isEmpty ? null : costo / comprobantes.length;
}

/// Los filtros elegidos; un conjunto vacío es "todos".
class FiltrosAgencias {
  const FiltrosAgencias({
    this.agencias = const {},
    this.clientes = const {},
    this.transportistas = const {},
    this.sucursales = const {},
  });

  final Set<String> agencias;
  final Set<String> clientes;
  final Set<String> transportistas;
  final Set<String> sucursales;

  bool get vacios =>
      agencias.isEmpty &&
      clientes.isEmpty &&
      transportistas.isEmpty &&
      sucursales.isEmpty;

  FiltrosAgencias copyWith({
    Set<String>? agencias,
    Set<String>? clientes,
    Set<String>? transportistas,
    Set<String>? sucursales,
  }) => FiltrosAgencias(
    agencias: agencias ?? this.agencias,
    clientes: clientes ?? this.clientes,
    transportistas: transportistas ?? this.transportistas,
    sucursales: sucursales ?? this.sucursales,
  );
}

/// Una columna del gráfico de gasto (una hora, un día o un mes).
class PuntoGasto {
  PuntoGasto(this.etiqueta, this.detalle);

  final String etiqueta;
  final String detalle;
  double costo = 0;
  final Set<String> comprobantes = {};
  final List<Guia> guias = [];
  final Map<String, double> porAgencia = {};
}

/// El periodo de igual largo justo antes de [periodo] (ayer, si es hoy).
PeriodoResumen periodoAnterior(PeriodoResumen periodo, DateTime ahora) {
  final (desde, hasta) = periodo.dias(ahora);
  final dias = hasta.difference(desde).inDays + 1;
  return PeriodoResumen.fechas(
    DateTime(desde.year, desde.month, desde.day - dias),
    DateTime(desde.year, desde.month, desde.day - 1),
  );
}

class AnalisisAgencias {
  AnalisisAgencias._(this.periodo, this.filtros);

  factory AnalisisAgencias.calcular(
    Iterable<Guia> todas,
    PeriodoResumen periodo, {
    required DateTime ahora,
    FiltrosAgencias filtros = const FiltrosAgencias(),
    Iterable<String> sucursales = const [],
    bool conAnterior = true,
  }) {
    final r = AnalisisAgencias._(periodo, filtros);
    final delPeriodo = [
      for (final g in todas)
        if (periodo.incluye(g, ahora)) g,
    ];
    r.guiasDelPeriodo = delPeriodo.length;
    final envios = delPeriodo.where(esEnvioPorAgencia).toList();
    final contador = ContadorComprobantes(envios);
    final nombresSucursal = {
      for (final s in sucursales) s.trim().toLowerCase(): s.trim(),
    };
    String salidaDe(Guia g) =>
        nombresSucursal[g.origen.trim().toLowerCase()] ?? fueraDeSucursal;
    r.salidaDe = salidaDe;
    String? agenciaDe(Guia g) =>
        g.tieneComprobanteAgencia ? contador.nombreDe(g) : null;

    // Los comprobantes con todas sus guías, antes de filtrar.
    final porClave = <String, ComprobanteAgencia>{};
    for (final g in envios) {
      final clave = contador.claveDe(g);
      if (clave == null) continue;
      final c = porClave.putIfAbsent(
        clave,
        () =>
            ComprobanteAgencia(clave, contador.nombreDe(g), contador.rucDe(g)),
      );
      c.todas.add(g);
      if (g.agenciaMonto case final m?) {
        c.monto ??= m;
        c.montosLeidos.add(m);
      }
    }

    // Opciones de cada filtro: lo que hay en el periodo.
    List<String> opciones(Iterable<String?> valores) =>
        ({for (final v in valores) ?v}.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
    r.opcionesAgencia = opciones(envios.map(agenciaDe));
    r.opcionesCliente = opciones(envios.map(clienteDe));
    r.opcionesTransportista = opciones(envios.map(transportistaDe));
    r.opcionesSucursal = opciones(envios.map(salidaDe));

    bool pasa(Set<String> elegidos, String? valor) =>
        elegidos.isEmpty || (valor != null && elegidos.contains(valor));
    for (final g in envios) {
      if (!pasa(filtros.agencias, agenciaDe(g)) ||
          !pasa(filtros.clientes, clienteDe(g)) ||
          !pasa(filtros.transportistas, transportistaDe(g)) ||
          !pasa(filtros.sucursales, salidaDe(g))) {
        continue;
      }
      r.guias.add(g);
    }

    final agencias = <String, FilaAnalisis>{};
    final clientes = <String, FilaAnalisis>{};
    final transportistas = <String, FilaAnalisis>{};
    final salidas = <String, FilaAnalisis>{};
    void sumar(
      Map<String, FilaAnalisis> filas,
      String nombre,
      Guia g,
      ComprobanteAgencia? c, {
      String? clave,
    }) {
      final fila = filas.putIfAbsent(
        (clave ?? nombre).toUpperCase(),
        () => FilaAnalisis(nombre),
      );
      fila.guias.add(g);
      if (c != null) {
        fila.comprobantes.add(c.clave);
        fila.agencias.add(c.agencia);
        fila.costo += c.porGuia;
      }
    }

    for (final g in r.guias) {
      final clave = contador.claveDe(g);
      final c = clave == null ? null : porClave[clave]!;
      if (c == null) {
        r.sinComprobante.add(g);
      } else {
        c.guias.add(g);
        sumar(agencias, c.agencia, g, c);
        agencias[c.agencia.toUpperCase()]!.ruc = c.ruc;
      }
      sumar(clientes, clienteDe(g), g, c);
      sumar(transportistas, transportistaDe(g), g, c);
      sumar(salidas, salidaDe(g), g, c);
    }

    r.comprobantes = porClave.values.where((c) => c.guias.isNotEmpty).toList()
      ..sort((a, b) => b.fecha.compareTo(a.fecha));
    for (final c in r.comprobantes) {
      r.gasto += c.pagado;
    }

    int porCosto(FilaAnalisis a, FilaAnalisis b) {
      final c = b.costo.compareTo(a.costo);
      return c != 0 ? c : b.guias.length.compareTo(a.guias.length);
    }

    r.agencias = agencias.values.toList()..sort(porCosto);
    r.clientes = clientes.values.toList()..sort(porCosto);
    r.transportistas = transportistas.values.toList()..sort(porCosto);
    r.salidas = salidas.values.toList()..sort(porCosto);

    // Para revisar.
    r.sinMonto = r.comprobantes.where((c) => c.sinMonto).toList();
    r.montosDistintos = r.comprobantes
        .where((c) => c.montosLeidos.length > 1)
        .toList();
    final montosPorAgencia = <String, List<double>>{};
    for (final c in r.comprobantes) {
      if (!c.sinMonto) {
        montosPorAgencia.putIfAbsent(c.agencia, () => []).add(c.monto!);
      }
    }
    r.montoInusual = r.comprobantes.where((c) {
      final montos = montosPorAgencia[c.agencia] ?? const [];
      if (c.sinMonto || montos.length < 3) return false;
      return c.monto! > 2 * _mediana(montos);
    }).toList();

    r.serie = _serieGasto(r, periodo, ahora);

    if (conAnterior) {
      final anterior = AnalisisAgencias.calcular(
        todas,
        periodoAnterior(periodo, ahora),
        ahora: ahora,
        filtros: filtros,
        sucursales: sucursales,
        conAnterior: false,
      );
      r.gastoAnterior = anterior.gasto;
    }
    return r;
  }

  final PeriodoResumen periodo;
  final FiltrosAgencias filtros;

  /// La sucursal de donde salió la guía, o [fueraDeSucursal].
  String Function(Guia) salidaDe = (_) => fueraDeSucursal;

  /// Todas las guías del periodo (de agencia o no), sin filtros.
  int guiasDelPeriodo = 0;

  /// Los envíos por agencia que pasan los filtros.
  final List<Guia> guias = [];

  /// De la más reciente a la más antigua.
  List<ComprobanteAgencia> comprobantes = [];
  double gasto = 0;

  /// Lo gastado en el periodo anterior de igual largo (mismos filtros).
  double? gastoAnterior;

  List<FilaAnalisis> agencias = [];
  List<FilaAnalisis> clientes = [];
  List<FilaAnalisis> transportistas = [];
  List<FilaAnalisis> salidas = [];
  List<PuntoGasto> serie = [];

  /// Marcadas como agencia pero sin comprobante leído.
  final List<Guia> sinComprobante = [];
  List<ComprobanteAgencia> sinMonto = [];
  List<ComprobanteAgencia> montoInusual = [];
  List<ComprobanteAgencia> montosDistintos = [];

  List<String> opcionesAgencia = [];
  List<String> opcionesCliente = [];
  List<String> opcionesTransportista = [];
  List<String> opcionesSucursal = [];

  int get conMonto => comprobantes.where((c) => !c.sinMonto).length;

  /// Guías cubiertas por un comprobante.
  int get guiasConComprobante =>
      comprobantes.fold(0, (n, c) => n + c.guias.length);

  double? get porComprobante => conMonto == 0 ? null : gasto / conMonto;

  double? get porGuia {
    final guias = comprobantes
        .where((c) => !c.sinMonto)
        .fold(0, (n, c) => n + c.guias.length);
    return guias == 0 ? null : gasto / guias;
  }

  double? get guiasPorComprobante =>
      comprobantes.isEmpty ? null : guiasConComprobante / comprobantes.length;

  int get porRevisar =>
      sinComprobante.length +
      sinMonto.length +
      montoInusual.length +
      montosDistintos.length;

  /// Las guías de varios comprobantes, sin repetir.
  static List<Guia> guiasDe(Iterable<ComprobanteAgencia> comprobantes) => [
    for (final c in comprobantes) ...c.guias,
  ];
}

double _mediana(List<double> valores) {
  final v = [...valores]..sort();
  final m = v.length ~/ 2;
  return v.length.isOdd ? v[m] : (v[m - 1] + v[m]) / 2;
}

const _meses = [
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
const _diasCortos = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const _diasLargos = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

/// El gasto por hora (un día), por día o por mes (más de dos meses). Cada
/// guía suma su parte del comprobante en su día: el de la entrega si es un
/// solo día, si no el de su registro (como el filtro del periodo).
List<PuntoGasto> _serieGasto(
  AnalisisAgencias a,
  PeriodoResumen periodo,
  DateTime ahora,
) {
  final porGuia = <Guia, ComprobanteAgencia>{
    for (final c in a.comprobantes)
      for (final g in c.guias) g: c,
  };
  final (desde, hasta) = periodo.dias(ahora);
  final List<PuntoGasto> puntos;
  final int Function(DateTime) indice;
  DateTime fechaDe(Guia g) => periodo.unDia && g.estado.esCerrada
      ? (g.fechaCierre ?? g.fechaActualizacion).toLocal()
      : g.fechaCreacion.toLocal();

  if (periodo.unDia) {
    var primera = 7;
    var ultima = 19;
    for (final g in porGuia.keys) {
      final h = fechaDe(g).hour;
      primera = math.min(primera, h);
      ultima = math.max(ultima, h);
    }
    puntos = [
      for (var h = primera; h <= ultima; h++)
        PuntoGasto(
          '$h h',
          '${h.toString().padLeft(2, '0')}:00 – '
              '${h.toString().padLeft(2, '0')}:59',
        ),
    ];
    indice = (f) => f.hour - primera;
  } else if (hasta.difference(desde).inDays + 1 > 62) {
    final inicio = DateTime(desde.year, desde.month);
    puntos = [
      for (var m = inicio; !m.isAfter(hasta); m = DateTime(m.year, m.month + 1))
        PuntoGasto(
          '${_meses[m.month - 1].substring(0, 3)} ${m.year % 100}',
          '${_meses[m.month - 1][0].toUpperCase()}'
              '${_meses[m.month - 1].substring(1)} de ${m.year}',
        ),
    ];
    indice = (f) => (f.year - inicio.year) * 12 + f.month - inicio.month;
  } else {
    final dias = hasta.difference(desde).inDays + 1;
    puntos = [
      for (var i = 0; i < dias; i++)
        () {
          final dia = DateTime(desde.year, desde.month, desde.day + i);
          return PuntoGasto(
            dias > 10
                ? '${dia.day}'
                : '${_diasCortos[dia.weekday - 1]} ${dia.day}',
            '${_diasLargos[dia.weekday - 1]} ${dia.day} de '
            '${_meses[dia.month - 1]}',
          );
        }(),
    ];
    indice = (f) => DateTime(f.year, f.month, f.day).difference(desde).inDays;
  }

  for (final MapEntry(key: g, value: c) in porGuia.entries) {
    final i = indice(fechaDe(g));
    if (i < 0 || i >= puntos.length) continue;
    final p = puntos[i];
    p.costo += c.porGuia;
    p.comprobantes.add(c.clave);
    p.guias.add(g);
    p.porAgencia.update(
      c.agencia,
      (v) => v + c.porGuia,
      ifAbsent: () => c.porGuia,
    );
  }
  return puntos;
}

/// Los comprobantes como hoja de cálculo: texto separado por tabulaciones
/// en UTF-16 con BOM, que Excel abre en columnas y con tildes sin importar
/// la configuración regional. Una fila por comprobante (sumar la columna
/// del monto da lo pagado).
Uint8List hojaComprobantes(AnalisisAgencias a) {
  String celda(Object? v) =>
      '${v ?? ''}'.replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();
  final fecha = DateFormat('dd/MM/yyyy');
  final filas = [
    [
      'Fecha',
      'Agencia',
      'RUC',
      'N° comprobante',
      'Monto (S/)',
      'N° de guías',
      'Guías',
      'Clientes',
      'Transportista',
      'Sucursal de salida',
    ],
    for (final c in a.comprobantes)
      [
        fecha.format(c.fecha),
        c.agencia,
        c.ruc,
        c.numero.isEmpty ? 'Sin número leído' : c.numero,
        c.monto?.toStringAsFixed(2) ?? '',
        c.todas.length,
        c.todas.map((g) => g.numeroGuia).join(', '),
        {for (final g in c.todas) clienteDe(g)}.join(', '),
        {for (final g in c.todas) transportistaDe(g)}.join(', '),
        {for (final g in c.todas) a.salidaDe(g)}.join(', '),
      ],
  ];
  final texto = filas.map((f) => f.map(celda).join('\t')).join('\r\n');
  final unidades = texto.codeUnits;
  final bytes = ByteData(2 + unidades.length * 2)
    ..setUint16(0, 0xFEFF, Endian.little);
  for (var i = 0; i < unidades.length; i++) {
    bytes.setUint16(2 + i * 2, unidades[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

// ---------------------------------------------------------------------------
// Vista

enum _Orden { gasto, guias, comprobantes }

/// "Análisis de Agencias", dentro de Dashboard.
class VistaAnalisisAgencias extends StatefulWidget {
  const VistaAnalisisAgencias({
    super.key,
    required this.cabecera,
    required this.periodo,
    required this.onPeriodo,
  });

  /// Va arriba de todo (el selector General / Análisis de agencias).
  final Widget cabecera;

  /// El mismo periodo del resumen General: los números coinciden.
  final PeriodoResumen periodo;
  final ValueChanged<PeriodoResumen> onPeriodo;

  @override
  State<VistaAnalisisAgencias> createState() => _VistaAnalisisAgenciasState();
}

DateTime _hoyDia() {
  final a = DateTime.now();
  return DateTime(a.year, a.month, a.day);
}

PeriodoResumen _ultimos7() {
  final hoy = _hoyDia();
  return PeriodoResumen.fechas(DateTime(hoy.year, hoy.month, hoy.day - 6), hoy);
}

PeriodoResumen _esteMes() {
  final hoy = _hoyDia();
  return PeriodoResumen.fechas(DateTime(hoy.year, hoy.month), hoy);
}

class _VistaAnalisisAgenciasState extends State<VistaAnalisisAgencias> {
  FiltrosAgencias _filtros = const FiltrosAgencias();
  _Orden _orden = _Orden.gasto;
  bool _porSucursal = false;
  int _visibles = 20;

  void _filtrar(FiltrosAgencias f) => setState(() {
    _filtros = f;
    _visibles = 20;
  });

  /// Tocar una fila de un ranking filtra por ella (o quita el filtro).
  Set<String> _alternar(Set<String> elegidos, String valor) =>
      elegidos.length == 1 && elegidos.contains(valor) ? {} : {valor};

  Future<void> _exportar(AnalisisAgencias a) async {
    final mensajero = ScaffoldMessenger.of(context);
    final (desde, hasta) = a.periodo.dias(DateTime.now());
    final f = DateFormat('yyyy-MM-dd');
    try {
      await descargarArchivo(
        hojaComprobantes(a),
        'agencias_${f.format(desde)}_${f.format(hasta)}.csv',
        'text/csv',
      );
    } catch (_) {
      mensajero.showSnackBar(
        const SnackBar(content: Text('No se pudo descargar el archivo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final a = AnalisisAgencias.calcular(
      app.guias,
      widget.periodo,
      ahora: DateTime.now(),
      filtros: _filtros,
      sucursales: [for (final s in app.sucursales) s.nombre],
    );
    void ver(String titulo, List<Guia> guias) => mostrarGuiasDelDashboard(
      context,
      titulo,
      guias,
      periodo: a.periodo.etiqueta,
    );

    return LayoutBuilder(
      builder: (context, c) {
        final ancho = c.maxWidth;
        final ancha = ancho >= 1000;
        const sep = 16.0;

        final filtros = _BarraFiltros(
          periodo: widget.periodo,
          onPeriodo: (p) {
            setState(() => _visibles = 20);
            widget.onPeriodo(p);
          },
          analisis: a,
          onFiltros: _filtrar,
          onExportar: a.comprobantes.isEmpty ? null : () => _exportar(a),
        );

        final cifras = _cifras(a, ver);
        final columnas = ancha ? 3 : 2;
        final anchoGrilla = ancha ? (ancho - 48 - sep) * 0.64 : ancho - 48;
        final anchoCifra = (anchoGrilla - sep * (columnas - 1)) / columnas;
        final grilla = Wrap(
          spacing: sep,
          runSpacing: sep,
          children: [
            for (final cifra in cifras)
              SizedBox(width: anchoCifra, child: cifra),
          ],
        );
        final revisar = _PorRevisar(analisis: a, ver: ver);
        final ranking = _RankingAgencias(
          analisis: a,
          orden: _orden,
          onOrden: (o) => setState(() => _orden = o),
          onElegir: (nombre) => _filtrar(
            _filtros.copyWith(agencias: _alternar(_filtros.agencias, nombre)),
          ),
        );
        final gasto = _GastoEnElTiempo(analisis: a, ver: ver);
        final clientes = _Lista(
          titulo: 'Clientes',
          subtitulo: 'A quién se le envía por agencia y lo que cuesta',
          filas: a.clientes,
          elegidos: _filtros.clientes,
          conAgencias: true,
          onElegir: (n) => _filtrar(
            _filtros.copyWith(clientes: _alternar(_filtros.clientes, n)),
          ),
        );
        final desglose = _Lista(
          titulo: _porSucursal ? 'Sucursal de salida' : 'Transportistas',
          subtitulo: _porSucursal
              ? 'De dónde salieron los envíos'
              : 'Quién llevó los envíos a la agencia',
          filas: _porSucursal ? a.salidas : a.transportistas,
          elegidos: _porSucursal
              ? _filtros.sucursales
              : _filtros.transportistas,
          cambio: _Segmentos(
            opciones: const ['Transportista', 'Sucursal'],
            elegido: _porSucursal ? 1 : 0,
            onCambio: (i) => setState(() => _porSucursal = i == 1),
          ),
          onElegir: (n) => _filtrar(
            _porSucursal
                ? _filtros.copyWith(
                    sucursales: _alternar(_filtros.sucursales, n),
                  )
                : _filtros.copyWith(
                    transportistas: _alternar(_filtros.transportistas, n),
                  ),
          ),
        );
        final tabla = _TablaComprobantes(
          analisis: a,
          visibles: _visibles,
          onMas: () => setState(() => _visibles += 30),
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
            widget.cabecera,
            const SizedBox(height: sep),
            filtros,
            const SizedBox(height: sep),
            if (ancha) ...[
              fila([grilla, revisar], [64, 36]),
              const SizedBox(height: sep),
              fila([ranking, gasto], [52, 48]),
              const SizedBox(height: sep),
              fila([clientes, desglose], [50, 50]),
            ] else ...[
              grilla,
              const SizedBox(height: sep),
              revisar,
              const SizedBox(height: sep),
              ranking,
              const SizedBox(height: sep),
              gasto,
              const SizedBox(height: sep),
              clientes,
              const SizedBox(height: sep),
              desglose,
            ],
            const SizedBox(height: sep),
            tabla,
          ],
        );
      },
    );
  }

  List<Widget> _cifras(
    AnalisisAgencias a,
    void Function(String, List<Guia>) ver,
  ) {
    final conComprobante = AnalisisAgencias.guiasDe(a.comprobantes);
    final principal = a.agencias.isEmpty ? null : a.agencias.first;
    String porcentaje(double parte, double total) =>
        total == 0 ? '0%' : '${(parte / total * 100).round()}%';
    final x = NumberFormat('0.#');
    return [
      _Cifra(
        onTap: () => ver('Envíos con comprobante', conComprobante),
        etiqueta: 'Gasto en agencias',
        valor: soles(a.gasto),
        detalle: _variacion(a),
      ),
      _Cifra(
        onTap: () => ver('Envíos con comprobante', conComprobante),
        etiqueta: 'Comprobantes',
        valor: '${a.comprobantes.length}',
        detalle: a.comprobantes.isEmpty
            ? 'sin comprobantes'
            : 'cubren ${_plural(a.guiasConComprobante, 'guía')} · '
                  '${x.format(a.guiasPorComprobante)} c/u',
      ),
      _Cifra(
        onTap: () => ver('Envíos por agencia', a.guias),
        etiqueta: 'Guías por agencia',
        valor: '${a.guias.length}',
        detalle:
            '${porcentaje(a.guias.length.toDouble(), a.guiasDelPeriodo.toDouble())}'
            ' de ${_plural(a.guiasDelPeriodo, 'guía')} del periodo',
      ),
      _Cifra(
        onTap: () => ver('Envíos con comprobante', conComprobante),
        etiqueta: 'Por comprobante',
        valor: a.porComprobante == null ? '—' : soles(a.porComprobante!),
        detalle: a.porGuia == null
            ? 'promedio'
            : '${soles(a.porGuia!)} por guía',
      ),
      _Cifra(
        onTap: principal == null
            ? null
            : () => ver(principal.nombre, principal.guias),
        etiqueta: 'Agencias usadas',
        valor: '${a.agencias.length}',
        detalle: principal == null
            ? 'ninguna en el periodo'
            : 'más usada: ${principal.nombre} '
                  '(${porcentaje(principal.costo, a.gasto)})',
      ),
      _Cifra(
        onTap: () => ver('Envíos por agencia', a.guias),
        etiqueta: 'Clientes',
        valor: '${a.clientes.length}',
        detalle: a.clientes.isEmpty
            ? 'ninguno en el periodo'
            : 'más gasto: ${a.clientes.first.nombre}',
      ),
    ];
  }

  static String _variacion(AnalisisAgencias a) {
    final anterior = a.gastoAnterior;
    if (anterior == null) return '';
    final (desde, hasta) = a.periodo.dias(DateTime.now());
    final dias = hasta.difference(desde).inDays + 1;
    final frente = dias == 1 ? 'el día anterior' : 'los $dias días previos';
    if (anterior == 0) {
      return a.gasto == 0 ? 'igual que $frente' : 'sin gasto $frente';
    }
    final cambio = ((a.gasto - anterior) / anterior * 100).round();
    if (cambio == 0) return 'igual que $frente';
    return '${cambio > 0 ? '▲' : '▼'} ${cambio.abs()}% vs. $frente';
  }
}

/// Fechas, filtros y exportar.
class _BarraFiltros extends StatelessWidget {
  const _BarraFiltros({
    required this.periodo,
    required this.onPeriodo,
    required this.analisis,
    required this.onFiltros,
    required this.onExportar,
  });

  final PeriodoResumen periodo;
  final ValueChanged<PeriodoResumen> onPeriodo;
  final AnalisisAgencias analisis;
  final ValueChanged<FiltrosAgencias> onFiltros;
  final VoidCallback? onExportar;

  Future<void> _elegirFechas(BuildContext context) async {
    final hoy = _hoyDia();
    final (desde, hasta) = periodo.dias(DateTime.now());
    final elegido = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: hoy,
      initialDateRange: DateTimeRange(start: desde, end: hasta),
      helpText: 'Fecha de inicio y fin',
      saveText: 'Ver',
    );
    if (elegido == null) return;
    onPeriodo(PeriodoResumen.fechas(elegido.start, elegido.end));
  }

  @override
  Widget build(BuildContext context) {
    final f = analisis.filtros;
    final rapidos = [
      ('Hoy', PeriodoResumen.hoy),
      ('7 días', _ultimos7()),
      ('Este mes', _esteMes()),
    ];
    // A inicios de mes "7 días" y "Este mes" pueden coincidir: gana el mes.
    final rapido = rapidos.lastIndexWhere((r) => r.$2 == periodo);

    Future<void> elegir(
      String titulo,
      List<String> opciones,
      Set<String> elegidos,
      FiltrosAgencias Function(Set<String>) aplicar,
    ) async {
      final nuevos = await _elegirVarios(context, titulo, opciones, elegidos);
      if (nuevos != null) onFiltros(aplicar(nuevos));
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Segmentos(
          opciones: [
            for (final r in rapidos) r.$1,
            rapido == -1 ? periodo.corta : 'Fechas',
          ],
          iconos: const {3: Icons.calendar_month_outlined},
          elegido: rapido == -1 ? 3 : rapido,
          onCambio: (i) =>
              i == 3 ? _elegirFechas(context) : onPeriodo(rapidos[i].$2),
        ),
        _BotonFiltro(
          etiqueta: 'Agencia',
          todos: 'Todas',
          elegidos: f.agencias,
          onTap: () => elegir(
            'Agencias',
            analisis.opcionesAgencia,
            f.agencias,
            (s) => f.copyWith(agencias: s),
          ),
        ),
        _BotonFiltro(
          etiqueta: 'Cliente',
          todos: 'Todos',
          elegidos: f.clientes,
          onTap: () => elegir(
            'Clientes',
            analisis.opcionesCliente,
            f.clientes,
            (s) => f.copyWith(clientes: s),
          ),
        ),
        _BotonFiltro(
          etiqueta: 'Transportista',
          todos: 'Todos',
          elegidos: f.transportistas,
          onTap: () => elegir(
            'Transportistas',
            analisis.opcionesTransportista,
            f.transportistas,
            (s) => f.copyWith(transportistas: s),
          ),
        ),
        _BotonFiltro(
          etiqueta: 'Sucursal',
          todos: 'Todas',
          elegidos: f.sucursales,
          onTap: () => elegir(
            'Sucursal de salida',
            analisis.opcionesSucursal,
            f.sucursales,
            (s) => f.copyWith(sucursales: s),
          ),
        ),
        if (!f.vacios)
          TextButton.icon(
            onPressed: () => onFiltros(const FiltrosAgencias()),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
            label: const Text('Limpiar'),
          ),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: onExportar,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Exportar a Excel'),
        ),
      ],
    );
  }
}

/// Elegir uno o varios valores de un filtro; null si se cancela.
Future<Set<String>?> _elegirVarios(
  BuildContext context,
  String titulo,
  List<String> opciones,
  Set<String> elegidos,
) {
  // Lo elegido sigue en la lista aunque no haya en el periodo nuevo.
  final todas = {...opciones, ...elegidos}.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  final seleccion = {...elegidos};
  var busqueda = '';
  return showDialog<Set<String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final visibles = todas
            .where((o) => o.toLowerCase().contains(busqueda.toLowerCase()))
            .toList();
        return AlertDialog(
          title: Text(titulo),
          content: SizedBox(
            width: 440,
            height: 420,
            child: Column(
              children: [
                if (todas.length > 6)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Buscar',
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => busqueda = v),
                    ),
                  ),
                Expanded(
                  child: visibles.isEmpty
                      ? const Center(
                          child: Text(
                            'Nada que elegir en este periodo.',
                            style: TextStyle(color: Ipesa.textoSuave),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final o in visibles)
                              CheckboxListTile(
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: seleccion.contains(o),
                                title: Text(o),
                                onChanged: (v) => setState(
                                  () => v == true
                                      ? seleccion.add(o)
                                      : seleccion.remove(o),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(<String>{}),
              child: const Text('Ver todos'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(seleccion),
              child: const Text('Aplicar'),
            ),
          ],
        );
      },
    ),
  );
}

class _BotonFiltro extends StatelessWidget {
  const _BotonFiltro({
    required this.etiqueta,
    required this.todos,
    required this.elegidos,
    required this.onTap,
  });

  final String etiqueta;
  final String todos;
  final Set<String> elegidos;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activo = elegidos.isNotEmpty;
    final valor = elegidos.isEmpty
        ? todos
        : elegidos.length == 1
        ? elegidos.first
        : '${elegidos.length}';
    return Material(
      color: activo ? Ipesa.menta : Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: activo ? Ipesa.turquesa : Ipesa.borde),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280, minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$etiqueta: ',
                  style: const TextStyle(fontSize: 14, color: Ipesa.textoSuave),
                ),
                Flexible(
                  child: Text(
                    valor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: activo ? Ipesa.petroleo : Ipesa.etiqueta,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_drop_down_rounded,
                  color: Ipesa.etiqueta,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Botones pegados, uno elegido (como el selector de periodo).
class _Segmentos extends StatelessWidget {
  const _Segmentos({
    required this.opciones,
    required this.elegido,
    required this.onCambio,
    this.iconos = const {},
  });

  final List<String> opciones;
  final int elegido;
  final ValueChanged<int> onCambio;
  final Map<int, IconData> iconos;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < opciones.length; i++) ...[
            if (i > 0) const VerticalDivider(width: 1, color: Ipesa.borde),
            Semantics(
              button: true,
              selected: i == elegido,
              child: Material(
                color: i == elegido ? Ipesa.petroleo : Colors.transparent,
                child: InkWell(
                  onTap: () => onCambio(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (iconos[i] case final icono?) ...[
                          Icon(
                            icono,
                            size: 16,
                            color: i == elegido ? Colors.white : Ipesa.etiqueta,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          opciones[i],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: i == elegido
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: i == elegido ? Colors.white : Ipesa.etiqueta,
                          ),
                        ),
                      ],
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

/// Las alertas: lo que conviene revisar antes de cerrar cuentas.
class _PorRevisar extends StatelessWidget {
  const _PorRevisar({required this.analisis, required this.ver});

  final AnalisisAgencias analisis;
  final void Function(String, List<Guia>) ver;

  @override
  Widget build(BuildContext context) {
    final a = analisis;
    final items = [
      (
        Icons.receipt_long_outlined,
        'Sin comprobante leído',
        'Marcadas como agencia, pero no se leyó su comprobante.',
        a.sinComprobante.length,
        a.sinComprobante,
      ),
      (
        Icons.money_off_rounded,
        'Sin monto o en S/ 0.00',
        'Comprobantes sin el total pagado.',
        a.sinMonto.length,
        AnalisisAgencias.guiasDe(a.sinMonto),
      ),
      (
        Icons.trending_up_rounded,
        'Monto fuera de lo normal',
        'Más del doble de lo usual en esa agencia.',
        a.montoInusual.length,
        AnalisisAgencias.guiasDe(a.montoInusual),
      ),
      (
        Icons.difference_outlined,
        'Mismo comprobante, montos distintos',
        'En sus guías se leyeron montos diferentes.',
        a.montosDistintos.length,
        AnalisisAgencias.guiasDe(a.montosDistintos),
      ),
    ].where((i) => i.$4 > 0).toList();

    return _Tarjeta(
      titulo: 'Por revisar',
      subtitulo: 'Envíos con datos incompletos o raros',
      child: items.isEmpty
          ? const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: _colorEntregado),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Todo en orden: cada envío tiene su comprobante y monto.',
                    style: TextStyle(color: Ipesa.etiqueta),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                for (final (icono, titulo, texto, cuantos, guias) in items)
                  _Tocable(
                    onTap: () => ver(titulo, guias),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDECEA),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              icono,
                              size: 19,
                              color: _colorRechazado,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  titulo,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: Ipesa.texto,
                                  ),
                                ),
                                Text(
                                  texto,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Ipesa.textoSuave,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$cuantos',
                            style: Ipesa.titulo(20, color: Ipesa.texto),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Ipesa.textoSuave,
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

/// Las agencias, ordenables por gasto, guías o comprobantes.
class _RankingAgencias extends StatelessWidget {
  const _RankingAgencias({
    required this.analisis,
    required this.orden,
    required this.onOrden,
    required this.onElegir,
  });

  final AnalisisAgencias analisis;
  final _Orden orden;
  final ValueChanged<_Orden> onOrden;
  final ValueChanged<String> onElegir;

  double _valor(FilaAnalisis f) => switch (orden) {
    _Orden.gasto => f.costo,
    _Orden.guias => f.guias.length.toDouble(),
    _Orden.comprobantes => f.comprobantes.length.toDouble(),
  };

  @override
  Widget build(BuildContext context) {
    final a = analisis;
    final filas = [...a.agencias]
      ..sort((x, y) {
        final c = _valor(y).compareTo(_valor(x));
        return c != 0 ? c : y.costo.compareTo(x.costo);
      });
    final maximo = filas.fold<double>(0, (m, f) => math.max(m, _valor(f)));
    return _Tarjeta(
      titulo: 'Agencias',
      subtitulo: 'Toca una para ver solo esa',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Segmentos(
            opciones: const ['Gasto', 'Guías', 'Comprobantes'],
            elegido: orden.index,
            onCambio: (i) => onOrden(_Orden.values[i]),
          ),
          const SizedBox(height: 16),
          if (filas.isEmpty)
            const Text(
              'Sin comprobantes de agencia con estos filtros.',
              style: TextStyle(color: Ipesa.textoSuave),
            ),
          for (final f in filas)
            _Tocable(
              onTap: () => onElegir(f.nombre),
              child: _FilaBarra(
                nombre: f.nombre,
                tooltip: [
                  f.nombre,
                  if (f.ruc.isNotEmpty) 'RUC ${f.ruc}',
                ].join('\n'),
                elegido: a.filtros.agencias.contains(f.nombre),
                derecha: switch (orden) {
                  _Orden.gasto => soles(f.costo),
                  _Orden.guias => _plural(f.guias.length, 'guía'),
                  _Orden.comprobantes => _plural(
                    f.comprobantes.length,
                    'comprobante',
                  ),
                },
                detalle: [
                  _plural(f.guias.length, 'guía'),
                  _plural(f.comprobantes.length, 'comprobante'),
                  if (f.porComprobante case final p?)
                    '${soles(p)} por comprobante',
                  if (a.gasto > 0)
                    '${(f.costo / a.gasto * 100).round()}% del gasto',
                ].join(' · '),
                fraccion: maximo == 0 ? 0 : _valor(f) / maximo,
              ),
            ),
        ],
      ),
    );
  }
}

String _plural(int n, String palabra) =>
    n == 1 ? '1 $palabra' : '$n ${palabra}s';

/// Una fila con nombre, valor a la derecha, detalle y barra.
class _FilaBarra extends StatelessWidget {
  const _FilaBarra({
    required this.nombre,
    required this.derecha,
    required this.detalle,
    required this.fraccion,
    this.elegido = false,
    this.tooltip,
  });

  final String nombre;
  final String derecha;
  final String detalle;
  final double fraccion;
  final bool elegido;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final fila = Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (elegido) ...[
                const Icon(
                  Icons.filter_alt_rounded,
                  size: 16,
                  color: Ipesa.turquesa,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: elegido ? Ipesa.petroleo : Ipesa.texto,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                derecha,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Ipesa.texto,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            detalle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Ipesa.textoSuave),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: Ipesa.menta),
                  FractionallySizedBox(
                    widthFactor: fraccion.clamp(0, 1).toDouble(),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Ipesa.turquesa,
                        borderRadius: BorderRadius.circular(4),
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
    return tooltip == null ? fila : Tooltip(message: tooltip, child: fila);
  }
}

/// Clientes, transportistas o sucursales: los de más gasto o más guías.
class _Lista extends StatelessWidget {
  const _Lista({
    required this.titulo,
    required this.subtitulo,
    required this.filas,
    required this.elegidos,
    required this.onElegir,
    this.conAgencias = false,
    this.cambio,
  });

  final String titulo;
  final String subtitulo;
  final List<FilaAnalisis> filas;
  final Set<String> elegidos;
  final ValueChanged<String> onElegir;
  final bool conAgencias;
  final Widget? cambio;

  static const _visibles = 8;

  @override
  Widget build(BuildContext context) {
    final maximo = filas.fold<double>(0, (m, f) => math.max(m, f.costo));
    return _Tarjeta(
      titulo: titulo,
      subtitulo: '$subtitulo · toca uno para filtrar',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cambio != null) ...[cambio!, const SizedBox(height: 16)],
          if (filas.isEmpty)
            const Text(
              'Sin envíos con estos filtros.',
              style: TextStyle(color: Ipesa.textoSuave),
            ),
          for (final f in filas.take(_visibles))
            _Tocable(
              onTap: () => onElegir(f.nombre),
              child: _FilaBarra(
                nombre: f.nombre,
                elegido: elegidos.contains(f.nombre),
                derecha: soles(f.costo),
                detalle: [
                  _plural(f.guias.length, 'guía'),
                  _plural(f.comprobantes.length, 'comprobante'),
                  if (conAgencias && f.agencias.isNotEmpty)
                    (f.agencias.toList()..sort()).join(', '),
                ].join(' · '),
                fraccion: maximo == 0 ? 0 : f.costo / maximo,
              ),
            ),
          if (filas.length > _visibles)
            Text(
              'y ${filas.length - _visibles} más',
              style: const TextStyle(fontSize: 13, color: Ipesa.textoSuave),
            ),
        ],
      ),
    );
  }
}

/// Lo pagado a agencias por hora, día o mes.
class _GastoEnElTiempo extends StatelessWidget {
  const _GastoEnElTiempo({required this.analisis, required this.ver});

  final AnalisisAgencias analisis;
  final void Function(String, List<Guia>) ver;

  static const _alto = 180.0;

  @override
  Widget build(BuildContext context) {
    final a = analisis;
    final serie = a.serie;
    final maximo = serie.fold<double>(0, (m, p) => math.max(m, p.costo));
    final tope = _GraficoEntregas._topeRedondo(maximo.ceil());
    final marcas = [for (var i = 0; i <= 2; i++) tope * i ~/ 2];
    final etiquetaCada = serie.length > 16 ? 5 : (serie.length > 10 ? 2 : 1);
    final unidad = a.periodo.unDia
        ? 'hora'
        : serie.isNotEmpty && serie.first.detalle.contains(' de 20')
        ? 'mes'
        : 'día';
    final f = NumberFormat('#,##0');

    return _Tarjeta(
      titulo: 'Gasto por $unidad',
      subtitulo: 'Lo pagado a las agencias en el periodo',
      child: SizedBox(
        height: _alto + 34,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 48,
              height: _alto + 34,
              child: Stack(
                children: [
                  for (final m in marcas)
                    Positioned(
                      right: 6,
                      bottom: 24 + _alto * m / tope - 8,
                      child: Text(
                        f.format(m),
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
                          child: _ColumnaGasto(
                            punto: serie[i],
                            tope: tope,
                            alto: _alto,
                            conEtiqueta:
                                i % etiquetaCada == 0 || i == serie.length - 1,
                            onTap: () => ver(
                              'Gasto · ${serie[i].detalle}',
                              serie[i].guias,
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
      ),
    );
  }
}

class _ColumnaGasto extends StatelessWidget {
  const _ColumnaGasto({
    required this.punto,
    required this.tope,
    required this.alto,
    required this.conEtiqueta,
    required this.onTap,
  });

  final PuntoGasto punto;
  final int tope;
  final double alto;
  final bool conEtiqueta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final agencias = punto.porAgencia.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final mensaje = punto.guias.isEmpty
        ? '${punto.detalle}\nSin envíos'
        : [
            punto.detalle,
            '${soles(punto.costo)} · '
                '${_plural(punto.comprobantes.length, 'comprobante')} · '
                '${_plural(punto.guias.length, 'guía')}',
            for (final e in agencias.take(4)) '${e.key}: ${soles(e.value)}',
            if (agencias.length > 4) 'y ${agencias.length - 4} más',
          ].join('\n');
    return Tooltip(
      message: mensaje,
      waitDuration: Duration.zero,
      child: _Tocable(
        onTap: punto.guias.isEmpty ? null : onTap,
        child: LayoutBuilder(
          builder: (context, c) => Container(
            color: Colors.transparent,
            height: alto + 24,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Center(
                  child: Container(
                    width: math.min(22, math.max(4, c.maxWidth - 6)),
                    height: tope == 0 ? 0 : alto * punto.costo / tope,
                    decoration: const BoxDecoration(
                      color: Ipesa.turquesa,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
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
                              maxLines: 1,
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
          ),
        ),
      ),
    );
  }
}

/// Un comprobante por fila, con sus guías y la foto.
class _TablaComprobantes extends StatelessWidget {
  const _TablaComprobantes({
    required this.analisis,
    required this.visibles,
    required this.onMas,
  });

  final AnalisisAgencias analisis;
  final int visibles;
  final VoidCallback onMas;

  @override
  Widget build(BuildContext context) {
    final todos = analisis.comprobantes;
    final filas = todos.take(visibles).toList();
    return _Tarjeta(
      titulo: 'Comprobantes',
      subtitulo:
          '${_plural(todos.length, 'comprobante')} · cada uno puede cubrir '
          'varias guías; toca una guía o la foto para ver el detalle',
      child: LayoutBuilder(
        builder: (context, c) {
          final ancha = c.maxWidth >= 860;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (todos.isEmpty)
                const Text(
                  'Sin comprobantes con estos filtros.',
                  style: TextStyle(color: Ipesa.textoSuave),
                )
              else if (ancha) ...[
                const _FilaTabla(encabezado: true),
                for (final comp in filas) _FilaTabla(comprobante: comp),
              ] else
                for (final comp in filas) _TarjetaComprobante(comp),
              if (todos.length > filas.length)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Center(
                    child: OutlinedButton(
                      onPressed: onMas,
                      child: Text(
                        'Ver más (${todos.length - filas.length} restantes)',
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

String _monto(ComprobanteAgencia c) =>
    c.sinMonto ? 'Sin monto' : soles(c.monto!);

String _numero(ComprobanteAgencia c) =>
    c.numero.isEmpty ? 'Sin número leído' : c.numero;

class _FilaTabla extends StatelessWidget {
  const _FilaTabla({this.comprobante, this.encabezado = false});

  final ComprobanteAgencia? comprobante;
  final bool encabezado;

  @override
  Widget build(BuildContext context) {
    final c = comprobante;
    const estiloEncabezado = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: Ipesa.textoSuave,
    );
    const estilo = TextStyle(fontSize: 14, color: Ipesa.texto);
    Widget texto(String t, {TextStyle? style, TextAlign? align}) => Text(
      t,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: encabezado ? estiloEncabezado : (style ?? estilo),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ipesa.segmento)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 92,
            child: texto(
              c == null ? 'FECHA' : DateFormat('dd/MM/yy').format(c.fecha),
            ),
          ),
          Expanded(
            flex: 3,
            child: texto(
              c?.agencia ?? 'AGENCIA',
              style: estilo.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: texto(
              c == null ? 'N° COMPROBANTE' : _numero(c),
              style: c != null && c.numero.isEmpty
                  ? estilo.copyWith(color: Ipesa.textoSuave)
                  : estilo,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: c == null ? texto('GUÍAS') : _GuiasDe(c)),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: texto(
              c == null
                  ? 'CLIENTE'
                  : {for (final g in c.guias) clienteDe(g)}.join(', '),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: texto(
              c == null
                  ? 'TRANSPORTISTA'
                  : {for (final g in c.guias) transportistaDe(g)}.join(', '),
            ),
          ),
          SizedBox(
            width: 100,
            child: texto(
              c == null ? 'MONTO' : _monto(c),
              align: TextAlign.right,
              style: estilo.copyWith(
                fontWeight: FontWeight.w700,
                color: c != null && c.sinMonto ? _colorRechazado : null,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: c == null
                ? null
                : IconButton(
                    tooltip: 'Ver la foto del comprobante',
                    onPressed: () => abrirGuiaAdmin(context, c.guias.first),
                    icon: const Icon(
                      Icons.image_outlined,
                      size: 20,
                      color: Ipesa.turquesa,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Las guías de un comprobante, cada una se toca para abrirla.
class _GuiasDe extends StatelessWidget {
  const _GuiasDe(this.comprobante);

  final ComprobanteAgencia comprobante;

  @override
  Widget build(BuildContext context) {
    final ocultas = comprobante.todas.length - comprobante.guias.length;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final g in comprobante.guias)
          ActionChip(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            backgroundColor: Ipesa.menta,
            side: BorderSide.none,
            label: Text(
              g.numeroGuia,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Ipesa.petroleo,
              ),
            ),
            onPressed: () => abrirGuiaAdmin(context, g),
          ),
        if (ocultas > 0)
          Tooltip(
            message:
                'El comprobante también cubre guías que no entran en '
                'los filtros; su monto se reparte entre todas.',
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '+$ocultas fuera del filtro',
                style: const TextStyle(fontSize: 12.5, color: Ipesa.textoSuave),
              ),
            ),
          ),
      ],
    );
  }
}

/// En celular: un comprobante por tarjeta.
class _TarjetaComprobante extends StatelessWidget {
  const _TarjetaComprobante(this.comprobante);

  final ComprobanteAgencia comprobante;

  @override
  Widget build(BuildContext context) {
    final c = comprobante;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Ipesa.fondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Ipesa.segmento),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.agencia,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Ipesa.texto,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _monto(c),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: c.sinMonto ? _colorRechazado : Ipesa.texto,
                ),
              ),
              IconButton(
                tooltip: 'Ver la foto del comprobante',
                visualDensity: VisualDensity.compact,
                onPressed: () => abrirGuiaAdmin(context, c.guias.first),
                icon: const Icon(
                  Icons.image_outlined,
                  size: 20,
                  color: Ipesa.turquesa,
                ),
              ),
            ],
          ),
          Text(
            '${_numero(c)} · ${DateFormat('dd/MM/yyyy').format(c.fecha)}',
            style: const TextStyle(fontSize: 13, color: Ipesa.textoSuave),
          ),
          const SizedBox(height: 8),
          _GuiasDe(c),
          const SizedBox(height: 6),
          Text(
            '${{for (final g in c.guias) clienteDe(g)}.join(', ')} · '
            '${{for (final g in c.guias) transportistaDe(g)}.join(', ')}',
            style: const TextStyle(fontSize: 13, color: Ipesa.etiqueta),
          ),
        ],
      ),
    );
  }
}
