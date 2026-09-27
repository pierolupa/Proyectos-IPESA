import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/filtros_rastreo.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/actualizacion_automatica.dart';
import '../../widgets/escena_ruta.dart';
import 'rastreo_resultados_screen.dart';

final _fecha = DateFormat('dd/MM/yyyy');

/// Rangos rápidos de fecha (además de elegir uno a mano en el calendario).
enum _Rango { todas, hoy, semana, mes, personalizado }

/// Inicio del equipo comercial: saludo, una tarjeta "Rastrea tus guías"
/// con los filtros (N° de guía, cliente, pedido, entrega y fechas) y el
/// paisaje animado con el camión IPESA al pie. "Buscar" abre los
/// resultados.
class RastreoScreen extends StatefulWidget {
  const RastreoScreen({super.key});

  @override
  State<RastreoScreen> createState() => _RastreoScreenState();
}

class _RastreoScreenState extends State<RastreoScreen> {
  final _guia = TextEditingController();
  final _cliente = TextEditingController();
  final _pedido = TextEditingController();
  final _entrega = TextEditingController();
  CampoFecha _campoFecha = CampoFecha.salida;
  _Rango _rango = _Rango.todas;
  DateTimeRange? _personalizado;
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
      campoFecha: _campoFecha,
      desde: desde,
      hasta: hasta,
    );
  }

  bool get _hayFiltros =>
      _campos.any((c) => c.text.trim().isNotEmpty) || _rango != _Rango.todas;

  void _limpiar() {
    for (final c in _campos) {
      c.clear();
    }
    setState(() {
      _rango = _Rango.todas;
      _personalizado = null;
    });
  }

  void _buscar({bool todas = false}) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RastreoResultadosScreen(
          filtros: todas ? const FiltrosRastreo() : _filtros,
        ),
      ),
    );
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
    final ancho = MediaQuery.sizeOf(context).width;
    final nombre = appState.transportistaActual.trim().split(RegExp(r'\s+'));
    final saludo = nombre.first.isEmpty ? '¡Hola!' : '¡Hola ${nombre.first}!';

    // Siempre el mismo árbol de widgets (con o sin teclado): si cambiara de
    // estructura al abrirse el teclado, el campo perdería el foco.
    return Scaffold(
      backgroundColor: cieloEscena,
      body: ActualizacionAutomatica(
        intervalo: const Duration(seconds: 60),
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
            final altoEscena = ancho < 600 ? 190.0 : 240.0;
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
                      padding: EdgeInsets.only(bottom: altoEscena - 56),
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
                                    12,
                                    12,
                                    ancho < 600 ? 18 : 28,
                                  ),
                                  child: _Cabecera(
                                    saludo: saludo,
                                    onActualizar: appState.cargarGuias,
                                    onCerrarSesion: _cerrarSesion,
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
                                  campoFecha: _campoFecha,
                                  rango: _rango,
                                  personalizado: _personalizado,
                                  hayFiltros: _hayFiltros,
                                  onTexto: () => setState(() {}),
                                  onCampoFecha: (c) =>
                                      setState(() => _campoFecha = c),
                                  onRango: (r) => r == _Rango.personalizado
                                      ? _elegirFechas()
                                      : setState(() => _rango = r),
                                  onLimpiar: _limpiar,
                                  onBuscar: _buscar,
                                  onVerTodas: () => _buscar(todas: true),
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
    required this.onActualizar,
    required this.onCerrarSesion,
  });

  final String saludo;
  final VoidCallback onActualizar;
  final VoidCallback onCerrarSesion;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.asset(
                'assets/brand/ipesa_blanco.png',
                height: 20,
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
        const SizedBox(height: 18),
        Text(saludo, style: Ipesa.titulo(30)),
        const SizedBox(height: 2),
        const Text(
          'Sigue el recorrido de tus guías en tiempo real.',
          style: TextStyle(fontSize: 16, color: Ipesa.textoSuave),
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
    required this.campoFecha,
    required this.rango,
    required this.personalizado,
    required this.hayFiltros,
    required this.onTexto,
    required this.onCampoFecha,
    required this.onRango,
    required this.onLimpiar,
    required this.onBuscar,
    required this.onVerTodas,
  });

  final TextEditingController guia;
  final TextEditingController cliente;
  final TextEditingController pedido;
  final TextEditingController entrega;
  final CampoFecha campoFecha;
  final _Rango rango;
  final DateTimeRange? personalizado;
  final bool hayFiltros;
  final VoidCallback onTexto;
  final ValueChanged<CampoFecha> onCampoFecha;
  final ValueChanged<_Rango> onRango;
  final VoidCallback onLimpiar;
  final VoidCallback onBuscar;
  final VoidCallback onVerTodas;

  Widget _campo(TextEditingController c, String etiqueta, IconData icono) =>
      TextField(
        controller: c,
        onChanged: (_) => onTexto(),
        onSubmitted: (_) => onBuscar(),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          labelText: etiqueta,
          prefixIcon: Icon(icono, size: 20),
          prefixIconConstraints: const BoxConstraints(minWidth: 42),
          isDense: true,
        ),
      );

  String _etiquetaRango(_Rango r) => switch (r) {
    _Rango.todas => 'Todas',
    _Rango.hoy => 'Hoy',
    _Rango.semana => 'Últimos 7 días',
    _Rango.mes => 'Este mes',
    _Rango.personalizado =>
      personalizado == null
          ? 'Elegir fechas'
          : '${_fecha.format(personalizado!.start)} – '
                '${_fecha.format(personalizado!.end)}',
  };

  @override
  Widget build(BuildContext context) {
    const separacion = SizedBox(height: 10);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Ipesa.menta,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  color: Ipesa.petroleo,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Rastrea tus guías', style: Ipesa.titulo(19)),
              ),
              if (hayFiltros)
                TextButton(onPressed: onLimpiar, child: const Text('Limpiar')),
            ],
          ),
          const SizedBox(height: 14),
          _campo(guia, 'N° de guía', Icons.receipt_long_outlined),
          separacion,
          _campo(cliente, 'Cliente', Icons.business_outlined),
          separacion,
          Row(
            children: [
              Expanded(
                child: _campo(pedido, 'N° pedido', Icons.shopping_bag_outlined),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _campo(
                  entrega,
                  'N° entrega',
                  Icons.inventory_2_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Fechas',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              SegmentedButton<CampoFecha>(
                segments: [
                  for (final c in CampoFecha.values)
                    ButtonSegment(
                      value: c,
                      label: Text(
                        c == CampoFecha.salida ? 'Salida' : 'Entrega',
                      ),
                    ),
                ],
                selected: {campoFecha},
                showSelectedIcon: false,
                onSelectionChanged: (s) => onCampoFecha(s.first),
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  selectedBackgroundColor: Ipesa.menta,
                  selectedForegroundColor: Ipesa.petroleo,
                  textStyle: const TextStyle(
                    fontFamily: Ipesa.fuenteTexto,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // En una sola fila (se desliza de lado en celulares angostos).
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final r in _Rango.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _ChipRango(
                      etiqueta: _etiquetaRango(r),
                      icono: r == _Rango.personalizado
                          ? Icons.date_range
                          : null,
                      seleccionado: rango == r,
                      onTap: () => onRango(r),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onBuscar,
            style: FilledButton.styleFrom(backgroundColor: Ipesa.petroleo),
            icon: const Icon(Icons.search),
            label: const Text('Buscar'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: onVerTodas,
            child: const Text('Ver todas las guías'),
          ),
        ],
      ),
    );
  }
}

class _ChipRango extends StatelessWidget {
  const _ChipRango({
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
