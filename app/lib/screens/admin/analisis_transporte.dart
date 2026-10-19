part of 'dashboard.dart';

// Análisis por transporte: cada transportista en el periodo (también los que
// no tuvieron guías), cuántas entregó, su promedio por día trabajado y
// rechazos. Con filtros de fechas, transportista, tipo de entrega y sucursal
// de salida. Sin tiempos de entrega: no reflejan la realidad (la entrega se
// registra cuando el transportista puede, no cuando ocurre).

/// Un transportista en el análisis por transporte.
class FilaTransporte {
  FilaTransporte(this.nombre);

  final String nombre;

  /// Sus guías del periodo (con los filtros aplicados).
  final List<Guia> guias = [];
  int entregadas = 0;
  int rechazadas = 0;
  int enRuta = 0;

  /// En ruta hace más de 24 h.
  int atrasadas = 0;

  /// Días del periodo en que registró o cerró alguna guía.
  final Set<DateTime> dias = {};
  DateTime? ultimaActividad;

  int get total => guias.length;

  /// Entregadas sobre todas sus guías.
  double get eficiencia => total == 0 ? 0 : entregadas / total;

  /// Entregas por día trabajado; null si no trabajó en el periodo.
  double? get promedioDiario => dias.isEmpty ? null : entregadas / dias.length;
}

/// Filtros de la vista; un conjunto vacío es "todos".
class FiltrosTransporte {
  const FiltrosTransporte({
    this.transportistas = const {},
    this.tipos = const {},
    this.sucursales = const {},
  });

  final Set<String> transportistas;

  /// Etiquetas de [TipoEntrega] ("Cliente final", "Agencia").
  final Set<String> tipos;

  /// Sucursal de salida (o [fueraDeSucursal]).
  final Set<String> sucursales;

  bool get vacios =>
      transportistas.isEmpty && tipos.isEmpty && sucursales.isEmpty;

  FiltrosTransporte copyWith({
    Set<String>? transportistas,
    Set<String>? tipos,
    Set<String>? sucursales,
  }) => FiltrosTransporte(
    transportistas: transportistas ?? this.transportistas,
    tipos: tipos ?? this.tipos,
    sucursales: sucursales ?? this.sucursales,
  );
}

enum OrdenTransporte { entregas, promedio, eficiencia, nombre }

const _diasSemana = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

class AnalisisTransporte {
  AnalisisTransporte._(this.periodo, this.filtros, this.diasDelRango);

  /// [conocidos]: todos los transportistas (de la hoja "Usuarios"), para
  /// mostrar también a los que no tuvieron guías en el periodo.
  factory AnalisisTransporte.calcular(
    Iterable<Guia> todas,
    PeriodoResumen periodo, {
    required DateTime ahora,
    FiltrosTransporte filtros = const FiltrosTransporte(),
    Iterable<String> sucursales = const [],
    Iterable<String> conocidos = const [],
    bool conAnterior = true,
  }) {
    final (desde, hasta) = periodo.dias(ahora);
    final r = AnalisisTransporte._(
      periodo,
      filtros,
      hasta.difference(desde).inDays + 1,
    );
    final nombresSucursal = {
      for (final s in sucursales) s.trim().toLowerCase(): s.trim(),
    };
    String salidaDe(Guia g) =>
        nombresSucursal[g.origen.trim().toLowerCase()] ?? fueraDeSucursal;
    DateTime dia(DateTime f) {
      final l = f.toLocal();
      return DateTime(l.year, l.month, l.day);
    }

    bool enRango(DateTime d) => !d.isBefore(desde) && !d.isAfter(hasta);
    final elegidos = {for (final t in filtros.transportistas) t.toLowerCase()};
    bool pasa(String nombre) =>
        elegidos.isEmpty || elegidos.contains(nombre.toLowerCase());

    final filas = <String, FilaTransporte>{};
    FilaTransporte fila(String nombre) =>
        filas.putIfAbsent(nombre.toLowerCase(), () => FilaTransporte(nombre));
    final transportistas = <String>{};
    final tipos = <String>{};
    final salidas = <String>{};
    for (final n in conocidos) {
      final limpio = _sinEspacios(n);
      if (limpio.isEmpty) continue;
      transportistas.add(limpio);
      if (pasa(limpio)) fila(limpio);
    }
    final clientes = <String>{};

    for (final g in todas) {
      if (!periodo.incluye(g, ahora)) continue;
      final nombre = transportistaDe(g);
      final tipo = g.tipoEntrega.etiqueta;
      final salida = salidaDe(g);
      transportistas.add(nombre);
      tipos.add(tipo);
      salidas.add(salida);
      if (!pasa(nombre)) continue;
      if (filtros.tipos.isNotEmpty && !filtros.tipos.contains(tipo)) continue;
      if (filtros.sucursales.isNotEmpty &&
          !filtros.sucursales.contains(salida)) {
        continue;
      }
      r.guias.add(g);
      final f = fila(nombre);
      f.guias.add(g);
      final cierre = g.fechaCierre ?? g.fechaActualizacion;
      switch (g.estado.grupo) {
        case GrupoEstado.entregado:
          f.entregadas++;
          clientes.add(clienteDe(g).toLowerCase());
        case GrupoEstado.rechazado:
          f.rechazadas++;
        case GrupoEstado.enRuta:
        case GrupoEstado.trasbordo:
          f.enRuta++;
          if (ahora.difference(g.fechaCreacion) > limiteAtraso) {
            f.atrasadas++;
          }
      }
      // El día en que trabajó esa guía: el del cierre o, si aún no cierra
      // (o cerró fuera del periodo), el del registro.
      final diaCierre = g.estado.esCerrada ? dia(cierre) : null;
      final diaTrabajo = diaCierre != null && enRango(diaCierre)
          ? diaCierre
          : dia(g.fechaCreacion);
      if (enRango(diaTrabajo)) {
        f.dias.add(diaTrabajo);
        r.diasConActividad.add(diaTrabajo);
      }
      if (g.estado.grupo == GrupoEstado.entregado &&
          diaCierre != null &&
          enRango(diaCierre)) {
        r.entregasPorDiaSemana[diaCierre.weekday - 1]++;
      }
      final ultima = g.fechaActualizacion;
      if (f.ultimaActividad == null || ultima.isAfter(f.ultimaActividad!)) {
        f.ultimaActividad = ultima;
      }
    }

    for (
      var d = desde;
      !d.isAfter(hasta);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      r.vecesDiaSemana[d.weekday - 1]++;
    }
    for (final f in filas.values) {
      r.entregadas += f.entregadas;
      r.rechazadas += f.rechazadas;
      r.enRuta += f.enRuta;
      r.atrasadas += f.atrasadas;
      r.diasTransportista += f.dias.length;
    }
    r.clientesAtendidos = clientes.length;
    r.filas = filas.values.toList();
    r.ordenar(OrdenTransporte.entregas);
    int alfabetico(String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());
    r.opcionesTransportista = transportistas.toList()..sort(alfabetico);
    r.opcionesTipo = tipos.toList()..sort(alfabetico);
    r.opcionesSucursal = salidas.toList()..sort(alfabetico);
    r.indicadores = IndicadoresOperacion.calcular(
      r.guias,
      periodo,
      ahora: ahora,
      sucursales: nombresSucursal.values.toSet(),
    );

    if (conAnterior) {
      final anterior = AnalisisTransporte.calcular(
        todas,
        periodoAnterior(periodo, ahora),
        ahora: ahora,
        filtros: filtros,
        sucursales: sucursales,
        conAnterior: false,
      );
      r.entregadasAnterior = anterior.entregadas;
      r.promedioAnterior = anterior.promedioDiario;
    }
    return r;
  }

  final PeriodoResumen periodo;
  final FiltrosTransporte filtros;

  /// Días calendario del periodo.
  final int diasDelRango;

  /// Las guías del periodo con los filtros.
  final List<Guia> guias = [];
  List<FilaTransporte> filas = [];
  int entregadas = 0;
  int rechazadas = 0;
  int enRuta = 0;
  int atrasadas = 0;

  /// Clientes distintos que recibieron alguna entrega.
  int clientesAtendidos = 0;

  /// Días del periodo en que algún transportista trabajó.
  final Set<DateTime> diasConActividad = {};

  /// La suma, por transportista, de sus días trabajados.
  int diasTransportista = 0;

  /// Entregas por día de la semana (lunes = 0) y cuántas veces cae cada
  /// día de la semana en el periodo.
  final List<int> entregasPorDiaSemana = List.filled(7, 0);
  final List<int> vecesDiaSemana = List.filled(7, 0);

  /// Para el gráfico de cierres (el mismo del resumen General).
  late final IndicadoresOperacion indicadores;

  List<String> opcionesTransportista = [];
  List<String> opcionesTipo = [];
  List<String> opcionesSucursal = [];

  /// En el periodo anterior de igual largo (mismos filtros).
  int? entregadasAnterior;
  double? promedioAnterior;

  int get total => guias.length;
  int get activos => filas.where((f) => f.total > 0).length;

  /// Entregadas sobre todas las guías.
  double get eficiencia => total == 0 ? 0 : entregadas / total;

  /// Entregas por día trabajado (días en que hubo actividad).
  double? get promedioDiario =>
      diasConActividad.isEmpty ? null : entregadas / diasConActividad.length;

  /// Entregas que hace, en promedio, un transportista en un día trabajado.
  double? get promedioPorTransportista =>
      diasTransportista == 0 ? null : entregadas / diasTransportista;

  /// Promedio de entregas de cada día de la semana (null si no cae en el
  /// periodo).
  double? promedioDiaSemana(int i) => vecesDiaSemana[i] == 0
      ? null
      : entregasPorDiaSemana[i] / vecesDiaSemana[i];

  void ordenar(OrdenTransporte orden) {
    int porNombre(FilaTransporte a, FilaTransporte b) =>
        a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    // Los que no tuvieron guías, siempre al final.
    int conGuias(FilaTransporte a, FilaTransporte b) =>
        (b.total > 0 ? 1 : 0).compareTo(a.total > 0 ? 1 : 0);
    filas.sort((a, b) {
      final primero = orden == OrdenTransporte.nombre ? 0 : conGuias(a, b);
      if (primero != 0) return primero;
      final c = switch (orden) {
        OrdenTransporte.entregas => b.entregadas.compareTo(a.entregadas),
        OrdenTransporte.promedio => (b.promedioDiario ?? -1).compareTo(
          a.promedioDiario ?? -1,
        ),
        OrdenTransporte.eficiencia => b.eficiencia.compareTo(a.eficiencia),
        OrdenTransporte.nombre => 0,
      };
      return c != 0 ? c : porNombre(a, b);
    });
  }
}

final _decimal = NumberFormat('0.#');

/// La tabla como hoja de cálculo (Excel), una fila por transportista.
Uint8List hojaTransporte(AnalisisTransporte a) {
  final fecha = DateFormat('dd/MM/yyyy HH:mm');
  return hojaDeCalculo([
    [
      'Transportista',
      'Guías',
      'Entregadas',
      'Rechazadas',
      'En ruta',
      '% entregadas',
      'Días trabajados',
      'Entregas por día trabajado',
      'Última actividad',
    ],
    for (final f in a.filas)
      [
        f.nombre,
        f.total,
        f.entregadas,
        f.rechazadas,
        f.enRuta,
        f.total == 0 ? '' : (f.eficiencia * 100).round(),
        f.dias.length,
        f.promedioDiario == null ? '' : _decimal.format(f.promedioDiario),
        f.ultimaActividad == null
            ? ''
            : fecha.format(f.ultimaActividad!.toLocal()),
      ],
  ]);
}

// ---------------------------------------------------------------------------
// Vista

/// "Análisis por transporte", dentro de Dashboard.
class VistaAnalisisTransporte extends StatefulWidget {
  const VistaAnalisisTransporte({
    super.key,
    required this.cabecera,
    required this.periodo,
    required this.onPeriodo,
  });

  /// Va arriba de todo (el selector de vistas del Dashboard).
  final Widget cabecera;

  /// El mismo periodo de las otras vistas del Dashboard.
  final PeriodoResumen periodo;
  final ValueChanged<PeriodoResumen> onPeriodo;

  @override
  State<VistaAnalisisTransporte> createState() =>
      _VistaAnalisisTransporteState();
}

class _VistaAnalisisTransporteState extends State<VistaAnalisisTransporte> {
  FiltrosTransporte _filtros = const FiltrosTransporte();
  OrdenTransporte _orden = OrdenTransporte.entregas;

  /// Todos los transportistas dados de alta (también los sin guías).
  List<String> _conocidos = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _asegurarGuias(widget.periodo);
      _cargarConocidos();
    });
  }

  Future<void> _cargarConocidos() async {
    try {
      final lista = await context.read<AppState>().listarTransportistas();
      if (mounted) setState(() => _conocidos = lista);
    } catch (_) {
      // Sin la lista se ven solo los que tuvieron guías en el periodo.
    }
  }

  /// Trae las guías del periodo y del anterior (para comparar) si son más
  /// antiguas que lo cargado.
  void _asegurarGuias(PeriodoResumen periodo) {
    final ahora = DateTime.now();
    final (desde, _) = periodoAnterior(periodo, ahora).dias(ahora);
    context.read<AppState>().asegurarDesde(desde);
  }

  void _filtrar(FiltrosTransporte f) => setState(() => _filtros = f);

  Future<void> _exportar(AnalisisTransporte a) async {
    final mensajero = ScaffoldMessenger.of(context);
    final (desde, hasta) = a.periodo.dias(DateTime.now());
    final f = DateFormat('yyyy-MM-dd');
    try {
      await descargarArchivo(
        hojaTransporte(a),
        'transporte_${f.format(desde)}_${f.format(hasta)}.csv',
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
    final a = AnalisisTransporte.calcular(
      app.guias,
      widget.periodo,
      ahora: DateTime.now(),
      filtros: _filtros,
      sucursales: [for (final s in app.sucursales) s.nombre],
      conocidos: _conocidos,
    )..ordenar(_orden);
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

        final filtros = _FiltrosTransporte(
          periodo: widget.periodo,
          onPeriodo: (p) {
            widget.onPeriodo(p);
            _asegurarGuias(p);
          },
          analisis: a,
          onFiltros: _filtrar,
          onExportar: a.filas.isEmpty ? null : () => _exportar(a),
        );

        final cifras = _cifras(a, ver);
        // Las 6 cifras en una fila en pantallas grandes.
        final columnas = ancho >= 1300 ? 6 : (ancha ? 3 : 2);
        final anchoGrilla = ancho - 48;
        final anchoCifra = (anchoGrilla - sep * (columnas - 1)) / columnas;
        final grilla = Wrap(
          spacing: sep,
          runSpacing: sep,
          children: [
            for (final cifra in cifras)
              SizedBox(width: anchoCifra, child: cifra),
          ],
        );
        final semana = _PorDiaSemana(analisis: a);
        final grafico = _GraficoEntregas(datos: a.indicadores);
        final tabla = _TablaTransporte(
          analisis: a,
          orden: _orden,
          onOrden: (o) => setState(() => _orden = o),
          onVer: (f) => ver(f.nombre, f.guias),
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
            grilla,
            const SizedBox(height: sep),
            tabla,
            const SizedBox(height: sep),
            if (ancha)
              fila([grafico, semana], [62, 38])
            else ...[
              grafico,
              const SizedBox(height: sep),
              semana,
            ],
          ],
        );
      },
    );
  }

  List<Widget> _cifras(
    AnalisisTransporte a,
    void Function(String, List<Guia>) ver,
  ) {
    final entregadas = [
      for (final g in a.guias)
        if (g.estado.grupo == GrupoEstado.entregado) g,
    ];
    final dias = a.diasConActividad.length;
    return [
      _Cifra(
        onTap: () => ver('Entregadas', entregadas),
        etiqueta: 'Entregadas',
        valor: '${a.entregadas}',
        detalle: _variacion(a.entregadas, a.entregadasAnterior, a),
        marca: _colorEntregado,
      ),
      _Cifra(
        onTap: () => ver('Entregadas', entregadas),
        etiqueta: 'Promedio diario',
        valor: a.promedioDiario == null
            ? '—'
            : _decimal.format(a.promedioDiario),
        // Entregas por día trabajado: los días en que hubo actividad.
        detalle: dias == 0
            ? 'sin días trabajados'
            : 'en $dias de ${_plural(a.diasDelRango, 'día')}',
      ),
      _Cifra(
        onTap: () => ver('Entregadas', entregadas),
        etiqueta: 'Por transportista',
        valor: a.promedioPorTransportista == null
            ? '—'
            : _decimal.format(a.promedioPorTransportista),
        detalle: 'por día, cada uno',
      ),
      _Cifra(
        onTap: () => ver('Guías del periodo', a.guias),
        etiqueta: 'Eficiencia',
        valor: _porcentaje(a.eficiencia),
        detalle: '${a.entregadas} de ${_plural(a.total, 'guía')}',
      ),
      _Cifra(
        onTap: () => ver('Rechazadas', [
          for (final g in a.guias)
            if (g.estado.grupo == GrupoEstado.rechazado) g,
        ]),
        etiqueta: 'Rechazadas',
        valor: '${a.rechazadas}',
        detalle: a.total == 0
            ? 'sin guías'
            : '${_porcentaje(a.rechazadas / a.total)} del total',
        marca: _colorRechazado,
      ),
      _Cifra(
        onTap: () => ver('Entregadas', entregadas),
        etiqueta: 'Clientes atendidos',
        valor: '${a.clientesAtendidos}',
        detalle: 'con alguna entrega',
      ),
    ];
  }

  static String _variacion(int actual, int? anterior, AnalisisTransporte a) {
    if (anterior == null) return '';
    // Corto: en celular la cifra mide la mitad de la pantalla.
    final dias = a.diasDelRango;
    final frente = dias == 1 ? 'día previo' : '$dias días antes';
    if (anterior == 0) {
      return actual == 0 ? 'igual que antes' : 'antes: sin entregas';
    }
    final cambio = ((actual - anterior) / anterior * 100).round();
    if (cambio == 0) return 'igual que antes';
    return '${cambio > 0 ? '▲' : '▼'} ${cambio.abs()}% vs. $frente';
  }
}

/// Fechas, filtros y exportar.
class _FiltrosTransporte extends StatelessWidget {
  const _FiltrosTransporte({
    required this.periodo,
    required this.onPeriodo,
    required this.analisis,
    required this.onFiltros,
    required this.onExportar,
  });

  final PeriodoResumen periodo;
  final ValueChanged<PeriodoResumen> onPeriodo;
  final AnalisisTransporte analisis;
  final ValueChanged<FiltrosTransporte> onFiltros;
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
    final rapido = rapidos.lastIndexWhere((r) => r.$2 == periodo);

    Future<void> elegir(
      String titulo,
      List<String> opciones,
      Set<String> elegidos,
      FiltrosTransporte Function(Set<String>) aplicar,
    ) async {
      final nuevos = await _elegirVarios(context, titulo, opciones, elegidos);
      if (nuevos != null) onFiltros(aplicar(nuevos));
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // En celulares angostos los cuatro no caben: se desplazan de lado.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _Segmentos(
            opciones: [
              for (final r in rapidos) r.$1,
              rapido == -1 ? periodo.corta : 'Fechas',
            ],
            iconos: const {3: Icons.calendar_month_outlined},
            elegido: rapido == -1 ? 3 : rapido,
            onCambio: (i) =>
                i == 3 ? _elegirFechas(context) : onPeriodo(rapidos[i].$2),
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
          etiqueta: 'Tipo',
          todos: 'Todos',
          elegidos: f.tipos,
          onTap: () => elegir(
            'Tipo de entrega',
            analisis.opcionesTipo,
            f.tipos,
            (s) => f.copyWith(tipos: s),
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
            onPressed: () => onFiltros(const FiltrosTransporte()),
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

/// Promedio de entregas de cada día de la semana en el periodo.
class _PorDiaSemana extends StatelessWidget {
  const _PorDiaSemana({required this.analisis});

  final AnalisisTransporte analisis;

  @override
  Widget build(BuildContext context) {
    final a = analisis;
    final promedios = [for (var i = 0; i < 7; i++) a.promedioDiaSemana(i)];
    final maximo = promedios.fold<double>(
      0,
      (m, p) => p != null && p > m ? p : m,
    );
    return _Tarjeta(
      titulo: 'Por día de la semana',
      subtitulo: 'Promedio de entregas de cada día en el periodo',
      child: Column(
        children: [
          for (var i = 0; i < 7; i++)
            if (promedios[i] case final promedio?)
              Tooltip(
                message:
                    '${_plural(a.entregasPorDiaSemana[i], 'entrega')} en '
                    '${a.vecesDiaSemana[i]} '
                    '${a.vecesDiaSemana[i] == 1 ? _diasSemana[i].toLowerCase() : _pluralDia(_diasSemana[i])}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(
                          _diasSemana[i],
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: Ipesa.texto,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            height: 10,
                            child: Stack(
                              children: [
                                Container(color: Ipesa.menta),
                                FractionallySizedBox(
                                  widthFactor: maximo == 0
                                      ? 0
                                      : promedio / maximo,
                                  child: Container(color: Ipesa.turquesa),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 52,
                        child: Text(
                          _decimal.format(promedio),
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                            color: Ipesa.texto,
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

  /// "Lunes" → "lunes"; "Sábado" → "sábados".
  static String _pluralDia(String dia) {
    final d = dia.toLowerCase();
    return d.endsWith('s') ? d : '${d}s';
  }
}

/// Todos los transportistas, con sus números del periodo.
class _TablaTransporte extends StatelessWidget {
  const _TablaTransporte({
    required this.analisis,
    required this.orden,
    required this.onOrden,
    required this.onVer,
  });

  final AnalisisTransporte analisis;
  final OrdenTransporte orden;
  final ValueChanged<OrdenTransporte> onOrden;
  final ValueChanged<FilaTransporte> onVer;

  // Ancho de cada columna numérica; el nombre toma el resto.
  static const _columnas = <(String, double, OrdenTransporte?)>[
    ('Guías', 64, null),
    ('Entregadas', 96, OrdenTransporte.entregas),
    ('Rechaz.', 76, null),
    ('En ruta', 72, null),
    ('% entrega', 90, OrdenTransporte.eficiencia),
    ('Prom./día', 90, OrdenTransporte.promedio),
    ('Días', 56, null),
    ('Última act.', 112, null),
  ];
  static const _anchoNombre = 220.0;
  static double get _anchoMinimo =>
      _anchoNombre + _columnas.fold(0.0, (s, c) => s + c.$2) + 32;

  @override
  Widget build(BuildContext context) {
    final a = analisis;
    final maximo = a.filas.fold(
      0,
      (m, f) => f.entregadas > m ? f.entregadas : m,
    );
    final sinGuias = a.filas.length - a.activos;
    return _Tarjeta(
      titulo: 'Todos los transportistas',
      subtitulo:
          '${_plural(a.activos, 'transportista')} con guías'
          '${sinGuias == 0 ? '' : ' · $sinGuias sin guías en el periodo'}'
          ' · toca uno para ver sus guías',
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth < 640) return _compacta(maximo);
          final ancho = math.max(c.maxWidth, _anchoMinimo);
          final tabla = SizedBox(
            width: ancho,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _encabezado(),
                const Divider(height: 1, color: Ipesa.borde),
                if (a.filas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No hay transportistas con estos filtros.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Ipesa.textoSuave),
                    ),
                  ),
                for (final f in a.filas) _fila(f, maximo),
              ],
            ),
          );
          return c.maxWidth >= _anchoMinimo
              ? tabla
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: tabla,
                );
        },
      ),
    );
  }

  /// En celular: una fila por transportista, con lo principal a la vista.
  Widget _compacta(int maximo) {
    const nombres = {
      OrdenTransporte.entregas: 'Entregadas',
      OrdenTransporte.promedio: 'Promedio por día',
      OrdenTransporte.eficiencia: '% entregadas',
      OrdenTransporte.nombre: 'Nombre',
    };
    final fecha = DateFormat('dd/MM HH:mm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<OrdenTransporte>(
            initialValue: orden,
            onSelected: onOrden,
            itemBuilder: (_) => [
              for (final o in OrdenTransporte.values)
                PopupMenuItem(value: o, child: Text(nombres[o]!)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.sort_rounded,
                    size: 18,
                    color: Ipesa.etiqueta,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Ordenar: ${nombres[orden]}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Ipesa.petroleo,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: Ipesa.etiqueta,
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: Ipesa.borde),
        if (analisis.filas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No hay transportistas con estos filtros.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Ipesa.textoSuave),
            ),
          ),
        for (final f in analisis.filas)
          InkWell(
            onTap: f.total == 0 ? null : () => onVer(f),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Ipesa.borde)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          f.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: f.total == 0
                                ? Ipesa.textoSuave
                                : Ipesa.texto,
                          ),
                        ),
                      ),
                      Text(
                        '${f.entregadas}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: f.total == 0
                              ? Ipesa.textoSuave
                              : _colorEntregado,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 6,
                      child: Stack(
                        children: [
                          Container(color: Ipesa.menta),
                          FractionallySizedBox(
                            widthFactor: maximo == 0
                                ? 0
                                : f.entregadas / maximo,
                            child: Container(color: _colorEntregado),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    f.total == 0
                        ? 'Sin guías en el periodo'
                        : [
                            '${_decimal.format(f.promedioDiario ?? 0)} por día',
                            '${_porcentaje(f.eficiencia)} de ${f.total}',
                            if (f.rechazadas > 0) '${f.rechazadas} rechaz.',
                            if (f.enRuta > 0) '${f.enRuta} en ruta',
                          ].join(' · '),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Ipesa.etiqueta,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (f.ultimaActividad case final u?)
                    Text(
                      'Última actividad ${fecha.format(u.toLocal())}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Ipesa.textoSuave,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _encabezado() {
    Widget celda(String texto, double? ancho, OrdenTransporte? o) {
      final activo = o != null && o == orden;
      final etiqueta = Text(
        activo ? '$texto ↓' : texto,
        textAlign: ancho == null ? TextAlign.start : TextAlign.end,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: activo ? Ipesa.petroleo : Ipesa.textoSuave,
        ),
      );
      final contenido = Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: etiqueta,
      );
      final tocable = o == null
          ? contenido
          : InkWell(
              onTap: () => onOrden(o),
              borderRadius: BorderRadius.circular(6),
              child: contenido,
            );
      return ancho == null
          ? Expanded(child: tocable)
          : SizedBox(width: ancho, child: tocable);
    }

    return Row(
      children: [
        celda('Transportista', null, OrdenTransporte.nombre),
        for (final (t, w, o) in _columnas) celda(t, w, o),
      ],
    );
  }

  Widget _fila(FilaTransporte f, int maximo) {
    final vacio = f.total == 0;
    final suave = vacio ? Ipesa.textoSuave : Ipesa.texto;
    Widget numero(
      String texto,
      double ancho, {
      Color? color,
      bool fuerte = false,
    }) => SizedBox(
      width: ancho,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          texto,
          textAlign: TextAlign.end,
          style: TextStyle(
            fontSize: 14,
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: fuerte ? FontWeight.w700 : FontWeight.w500,
            color: color ?? suave,
          ),
        ),
      ),
    );
    final anchos = [for (final c in _columnas) c.$2];
    final fecha = DateFormat('dd/MM HH:mm');
    return InkWell(
      onTap: vacio ? null : () => onVer(f),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Ipesa.borde)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: suave,
                      ),
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: 6,
                        child: Stack(
                          children: [
                            Container(color: Ipesa.menta),
                            FractionallySizedBox(
                              widthFactor: maximo == 0
                                  ? 0
                                  : f.entregadas / maximo,
                              child: Container(color: _colorEntregado),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            numero('${f.total}', anchos[0]),
            numero(
              '${f.entregadas}',
              anchos[1],
              color: vacio ? null : _colorEntregado,
              fuerte: true,
            ),
            numero(
              '${f.rechazadas}',
              anchos[2],
              color: f.rechazadas > 0 ? _colorRechazado : null,
            ),
            numero(
              f.atrasadas > 0 ? '${f.enRuta} (${f.atrasadas}!)' : '${f.enRuta}',
              anchos[3],
              color: f.enRuta > 0 ? _colorEnRuta : null,
            ),
            numero(vacio ? '—' : _porcentaje(f.eficiencia), anchos[4]),
            numero(
              f.promedioDiario == null
                  ? '—'
                  : _decimal.format(f.promedioDiario),
              anchos[5],
              fuerte: !vacio,
            ),
            numero('${f.dias.length}', anchos[6]),
            numero(
              f.ultimaActividad == null
                  ? '—'
                  : fecha.format(f.ultimaActividad!.toLocal()),
              anchos[7],
            ),
          ],
        ),
      ),
    );
  }
}
