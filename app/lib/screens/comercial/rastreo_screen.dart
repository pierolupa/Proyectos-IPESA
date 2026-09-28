import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/filtros_rastreo.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/actualizacion_automatica.dart';
import '../../widgets/escena_ruta.dart';
import 'rastreo_detalle_screen.dart';
import 'rastreo_resultados_screen.dart';

final _fecha = DateFormat('dd/MM/yyyy');

DateTime _hoy() => DateUtils.dateOnly(DateTime.now());

/// Inicio del equipo comercial: saludo, una tarjeta "Rastrea tus guías"
/// con los filtros (N° de guía, cliente, pedido y entrega) y la fecha de la
/// tarea (hoy, salvo que se elija otro rango), y el paisaje animado con el
/// camión IPESA al pie. Solo se busca dentro de esas fechas: al comercial
/// el servidor le manda solo las guías de ese rango. "Buscar" abre la guía
/// encontrada (o la lista, si hay varias).
class RastreoScreen extends StatefulWidget {
  const RastreoScreen({super.key, this.desdeAdmin = false});

  /// El administrador la abre desde su panel: vuelve con la flecha y la
  /// sesión se cierra desde el panel, no desde aquí.
  final bool desdeAdmin;

  @override
  State<RastreoScreen> createState() => _RastreoScreenState();
}

class _RastreoScreenState extends State<RastreoScreen> {
  final _guia = TextEditingController();
  final _cliente = TextEditingController();
  final _pedido = TextEditingController();
  final _entrega = TextEditingController();
  String? _error;
  DateTime _desde = _hoy();
  DateTime _hasta = _hoy();
  bool _buscando = false;
  double _altoSinTeclado = 0;
  double _anchoMedido = 0;

  List<TextEditingController> get _campos => [
    _guia,
    _cliente,
    _pedido,
    _entrega,
  ];

  @override
  void dispose() {
    for (final c in _campos) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _hayFiltros => _campos.any((c) => c.text.trim().isNotEmpty);

  void _limpiar() {
    for (final c in _campos) {
      c.clear();
    }
    setState(() => _error = null);
  }

  @override
  void initState() {
    super.initState();
    // Siempre empieza en hoy. Para el comercial, pide al servidor solo
    // las guías de hoy (si no son las que ya tiene).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AppState>().asegurarRangoTareas(_desde, _hasta);
      }
    });
  }

  bool get _esHoy => _desde == _hoy() && _hasta == _hoy();

  void _cambiarRango(DateTime desde, DateTime hasta) {
    setState(() {
      _desde = DateUtils.dateOnly(desde);
      _hasta = DateUtils.dateOnly(hasta);
      _error = null;
    });
    // Se adelanta la carga; "Buscar" la espera si aún no terminó.
    context.read<AppState>().asegurarRangoTareas(_desde, _hasta);
  }

  /// Fecha inicio o fin de la tarea. Si quedan al revés, la otra se
  /// ajusta para que el rango siga siendo válido.
  Future<void> _elegirFecha({required bool inicio}) async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: inicio ? _desde : _hasta,
      firstDate: DateTime(2024),
      lastDate: _hoy(),
      helpText: inicio ? 'Fecha inicio' : 'Fecha fin',
      // En computadora, una ventana del tamaño de un celular en vez de
      // ocupar toda la pantalla.
      builder: (context, child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 680),
          child: child,
        ),
      ),
    );
    if (elegida == null || !mounted) return;
    final dia = DateUtils.dateOnly(elegida);
    if (inicio) {
      _cambiarRango(dia, _hasta.isBefore(dia) ? dia : _hasta);
    } else {
      _cambiarRango(_desde.isAfter(dia) ? dia : _desde, dia);
    }
  }

  /// Una sola guía coincide: se abre de frente. Varias: la lista para
  /// elegir. Ninguna: se avisa aquí mismo. Solo cuentan las tareas
  /// creadas en las fechas elegidas.
  Future<void> _buscar() async {
    if (_buscando) return;
    if (!_hayFiltros) {
      setState(() => _error = 'Escribe al menos un dato para buscar.');
      return;
    }
    final filtros = FiltrosRastreo(
      numeroGuia: _guia.text,
      cliente: _cliente.text,
      numeroEntrega: _entrega.text,
      numeroPedido: _pedido.text,
      campoFecha: CampoFecha.salida,
      desde: _desde,
      hasta: _hasta,
    );
    FocusScope.of(context).unfocus();
    final appState = context.read<AppState>();
    setState(() => _buscando = true);
    try {
      await appState.asegurarRangoTareas(_desde, _hasta);
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
    if (!mounted) return;
    final sinDatos = appState.guias.isEmpty && appState.error != null;
    final encontradas = filtros.aplicar(appState.guias);
    if (!sinDatos && encontradas.isEmpty) {
      setState(
        () => _error = _esHoy
            ? 'No encontramos ninguna guía de hoy con esos datos. Si es de '
                  'otro día, cambia las fechas.'
            : 'No encontramos ninguna guía con esos datos en esas fechas.',
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => !sinDatos && encontradas.length == 1
            ? RastreoDetalleScreen(numeroGuia: encontradas.single.numeroGuia)
            : RastreoResultadosScreen(filtros: filtros),
      ),
    );
  }

  void _cerrarSesion() {
    context.read<AppState>().cerrarSesion();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final ancho = MediaQuery.sizeOf(context).width;
    final nombre = appState.transportistaActual.trim().split(RegExp(r'\s+'));
    final saludo = nombre.first.isEmpty ? '¡Hola!' : '¡Hola ${nombre.first}!';

    // Siempre el mismo árbol de widgets (con o sin teclado): si cambiara de
    // estructura al abrirse el teclado, el campo perdería el foco.
    return Scaffold(
      backgroundColor: cieloEscena,
      body: ActualizacionAutomatica(
        intervalo: const Duration(seconds: 60),
        // Abierta desde el panel del administrador, el panel de abajo ya
        // actualiza.
        activa: !widget.desdeAdmin,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Alto de la pantalla sin teclado: el paisaje se queda donde
            // estaba y el formulario solo se desplaza.
            final alto =
                constraints.maxHeight + MediaQuery.viewInsetsOf(context).bottom;
            if (constraints.maxWidth != _anchoMedido) {
              _anchoMedido = constraints.maxWidth;
              _altoSinTeclado = alto;
            } else if (alto > _altoSinTeclado) {
              _altoSinTeclado = alto;
            }
            // En celulares bajitos el paisaje se achica para que todo
            // entre en una sola vista.
            final altoEscena = ancho >= 600
                ? 240.0
                : _altoSinTeclado < 720
                ? 164.0
                : 190.0;
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: _altoSinTeclado),
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: EscenaRuta(alto: altoEscena),
                    ),
                    Padding(
                      // Solo se reserva el suelo del paisaje: la tarjeta puede
                      // tapar un poco de cielo.
                      padding: EdgeInsets.only(
                        bottom: math.max(altoEscena - 56, 112),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SafeArea(
                            bottom: false,
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 560,
                                ),
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    20,
                                    8,
                                    8,
                                    ancho < 600 ? 14 : 28,
                                  ),
                                  child: _Cabecera(
                                    saludo: saludo,
                                    onVolver: widget.desdeAdmin
                                        ? () => Navigator.of(context).pop()
                                        : null,
                                    onActualizar: appState.cargarGuias,
                                    onCerrarSesion: widget.desdeAdmin
                                        ? null
                                        : _cerrarSesion,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: _TarjetaBusqueda(
                                  guia: _guia,
                                  cliente: _cliente,
                                  pedido: _pedido,
                                  entrega: _entrega,
                                  hayFiltros: _hayFiltros,
                                  error: _error,
                                  fechaInicio: _fecha.format(_desde),
                                  fechaFin: _fecha.format(_hasta),
                                  buscando: _buscando,
                                  onFechaInicio: () =>
                                      _elegirFecha(inicio: true),
                                  onFechaFin: () => _elegirFecha(inicio: false),
                                  onHoy: _esHoy
                                      ? null
                                      : () => _cambiarRango(_hoy(), _hoy()),
                                  onTexto: () => setState(() => _error = null),
                                  onLimpiar: _limpiar,
                                  onBuscar: _buscar,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.saludo,
    required this.onVolver,
    required this.onActualizar,
    required this.onCerrarSesion,
  });

  final String saludo;
  final VoidCallback? onVolver;
  final VoidCallback onActualizar;
  final VoidCallback? onCerrarSesion;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (onVolver != null) ...[
              IconButton(
                tooltip: 'Volver al panel',
                onPressed: onVolver,
                icon: const Icon(Icons.arrow_back, color: Ipesa.petroleo),
              ),
              const SizedBox(width: 4),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.asset(
                'assets/brand/ipesa_blanco.png',
                height: 18,
                semanticLabel: 'IPESA',
              ),
            ),
            const Spacer(),
            PopupMenuButton<VoidCallback>(
              tooltip: 'Opciones',
              icon: const Icon(Icons.more_vert, color: Ipesa.petroleo),
              color: Colors.white,
              onSelected: (accion) => accion(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: onActualizar,
                  child: const ListTile(
                    leading: Icon(Icons.refresh),
                    title: Text('Actualizar'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (onCerrarSesion != null)
                  PopupMenuItem(
                    value: onCerrarSesion,
                    child: const ListTile(
                      leading: Icon(Icons.logout),
                      title: Text('Cerrar sesión'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(saludo, style: Ipesa.titulo(28)),
        const Text(
          'Sigue el recorrido de tus guías en tiempo real.',
          style: TextStyle(fontSize: 15, color: Ipesa.textoSuave),
        ),
      ],
    );
  }
}

class _TarjetaBusqueda extends StatelessWidget {
  const _TarjetaBusqueda({
    required this.guia,
    required this.cliente,
    required this.pedido,
    required this.entrega,
    required this.hayFiltros,
    required this.error,
    required this.fechaInicio,
    required this.fechaFin,
    required this.buscando,
    required this.onFechaInicio,
    required this.onFechaFin,
    required this.onHoy,
    required this.onTexto,
    required this.onLimpiar,
    required this.onBuscar,
  });

  final TextEditingController guia;
  final TextEditingController cliente;
  final TextEditingController pedido;
  final TextEditingController entrega;
  final bool hayFiltros;
  final String? error;
  final String fechaInicio;
  final String fechaFin;
  final bool buscando;
  final VoidCallback onFechaInicio;
  final VoidCallback onFechaFin;

  /// Volver a hoy (null si ya es hoy).
  final VoidCallback? onHoy;
  final VoidCallback onTexto;
  final VoidCallback onLimpiar;
  final VoidCallback onBuscar;

  Widget _campo(TextEditingController c, String etiqueta, IconData icono) =>
      TextField(
        controller: c,
        onChanged: (_) => onTexto(),
        onSubmitted: (_) => onBuscar(),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          labelText: etiqueta,
          prefixIcon: Icon(icono, size: 18),
          prefixIconConstraints: const BoxConstraints(minWidth: 38),
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(0, 14, 10, 14),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const separacion = SizedBox(width: 10, height: 10);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            child: Row(
              children: [
                Expanded(
                  child: Text('Rastrea tus guías', style: Ipesa.titulo(19)),
                ),
                if (onHoy != null)
                  TextButton(onPressed: onHoy, child: const Text('Hoy')),
                if (hayFiltros)
                  TextButton(
                    onPressed: onLimpiar,
                    child: const Text('Limpiar'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Los cuatro campos en dos filas, para que todo entre en la
          // pantalla del celular sin deslizar.
          Row(
            children: [
              Expanded(
                child: _campo(guia, 'N° de guía', Icons.receipt_long_outlined),
              ),
              separacion,
              Expanded(
                child: _campo(cliente, 'Cliente', Icons.business_outlined),
              ),
            ],
          ),
          separacion,
          Row(
            children: [
              Expanded(
                child: _campo(pedido, 'N° pedido', Icons.shopping_bag_outlined),
              ),
              separacion,
              Expanded(
                child: _campo(
                  entrega,
                  'N° entrega',
                  Icons.inventory_2_outlined,
                ),
              ),
            ],
          ),
          separacion,
          // Fecha de la tarea: por defecto hoy en las dos.
          Row(
            children: [
              Expanded(
                child: _CampoFecha(
                  etiqueta: 'Fecha inicio',
                  valor: fechaInicio,
                  onTap: onFechaInicio,
                ),
              ),
              separacion,
              Expanded(
                child: _CampoFecha(
                  etiqueta: 'Fecha fin',
                  valor: fechaFin,
                  onTap: onFechaFin,
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: Color(0xFFB42318))),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: buscando ? null : onBuscar,
            style: FilledButton.styleFrom(
              backgroundColor: Ipesa.petroleo,
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            icon: buscando
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.search),
            label: Text(buscando ? 'Buscando…' : 'Buscar'),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// Campo de fecha con el mismo aspecto que los de texto; tocarlo abre el
/// calendario.
class _CampoFecha extends StatelessWidget {
  const _CampoFecha({
    required this.etiqueta,
    required this.valor,
    required this.onTap,
  });

  final String etiqueta;
  final String valor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$etiqueta: $valor',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Ipesa.radioCampo),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: etiqueta,
            prefixIcon: const Icon(Icons.event_outlined, size: 18),
            prefixIconConstraints: const BoxConstraints(minWidth: 38),
            isDense: true,
            contentPadding: const EdgeInsets.fromLTRB(0, 14, 10, 14),
          ),
          child: Text(
            valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, color: Ipesa.texto),
          ),
        ),
      ),
    );
  }
}
