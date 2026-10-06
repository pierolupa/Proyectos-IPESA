import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../services/notificador.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/marca_rpa.dart';
import '../../widgets/actualizacion_automatica.dart';
import '../../widgets/avisos_novedades.dart';
import '../../widgets/carrusel_marcas.dart';
import '../../widgets/estado_badge.dart';
import '../../widgets/lugares_sucursal.dart';
import '../../widgets/mapa_ubicacion.dart';
import '../comercial/rastreo_screen.dart';
import 'admin_guia_edit_screen.dart';
import 'dashboard.dart';
import 'sucursal_edit_screen.dart';
import 'transportistas.dart';

const _anchoEscritorio = 900.0;

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _pestana = 0;
  final _scaffold = GlobalKey<ScaffoldState>();
  bool _notificacionesActivas = Notificador.permitido;
  final _novedades = CentroNovedades();

  @override
  void dispose() {
    _novedades.dispose();
    super.dispose();
  }

  static const _titulos = [
    'Operación',
    'Transportistas',
    'Dashboard',
    'Sucursales',
  ];

  Future<void> _activarNotificaciones() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!Notificador.soportado) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Este navegador no permite notificaciones. Los avisos se '
            'mostrarán solo dentro de la app.',
          ),
        ),
      );
      return;
    }
    final ok = await Notificador.pedirPermiso();
    if (!mounted) return;
    setState(() => _notificacionesActivas = ok);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Notificaciones activadas: te avisaremos aunque tengas otra '
                    'pestaña abierta.'
              : 'El navegador bloqueó las notificaciones. Actívalas desde el '
                    'candado junto a la dirección de la página.',
        ),
      ),
    );
  }

  void _avisarCambios(List<CambioGuia> cambios) {
    _novedades.agregar(cambios);
    if (!Notificador.paginaOculta) return;
    // Con la pestaña en segundo plano, también el aviso del sistema.
    if (cambios.length == 1) {
      final c = cambios.first;
      Notificador.mostrar(
        '${c.titulo} · ${c.guia.numeroGuia}',
        c.detalle,
        tag: 'ipesa-${c.guia.numeroGuia}',
      );
      return;
    }
    final lineas = [
      for (final c in cambios.take(4)) '${c.titulo} · ${c.guia.numeroGuia}',
      if (cambios.length > 4) 'y ${cambios.length - 4} más',
    ];
    Notificador.mostrar(
      'IPESA · ${cambios.length} novedades',
      lineas.join('\n'),
    );
  }

  void _abrirNovedades() {
    mostrarPanelNovedades(
      context,
      centro: _novedades,
      onAbrirGuia: (g) => abrirGuiaAdmin(context, g),
      avisosDelNavegador: _notificacionesActivas || !Notificador.soportado,
      onActivarNavegador: _activarNotificaciones,
    );
  }

  void _cerrarSesion() {
    context.read<AppState>().cerrarSesion();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /// La misma búsqueda del equipo comercial.
  void _abrirRastreo() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RastreoScreen(desdeAdmin: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancha = constraints.maxWidth >= _anchoEscritorio;
        final contenido = ActualizacionAutomatica(
          intervalo: const Duration(seconds: 15),
          // Con la pestaña oculta sigue, más espaciado, para las
          // notificaciones del navegador.
          intervaloOculta: const Duration(seconds: 60),
          onCambios: _avisarCambios,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Cabecera(
                titulo: _titulos[_pestana],
                novedades: _novedades,
                onNovedades: _abrirNovedades,
                onMenu: ancha
                    ? () => _scaffold.currentState?.openDrawer()
                    : null,
                onRastrear: ancha ? null : _abrirRastreo,
                onCerrarSesion: ancha ? null : _cerrarSesion,
              ),
              Expanded(
                child: switch (_pestana) {
                  0 => _PestanaGuias(ancha: ancha),
                  1 => const PestanaTransportistas(),
                  2 => const _PestanaDashboard(),
                  _ => const _PestanaSucursales(),
                },
              ),
            ],
          ),
        );

        return CapaAvisos(
          centro: _novedades,
          onAbrirGuia: (g) => abrirGuiaAdmin(context, g),
          onVerTodas: _abrirNovedades,
          child: Scaffold(
            key: _scaffold,
            // En computadora las secciones van en el menú ☰, para que el
            // contenido use todo el ancho.
            drawer: ancha
                ? _MenuAdmin(
                    seleccionado: _pestana,
                    onSeleccion: (i) => setState(() => _pestana = i),
                    onRastrear: _abrirRastreo,
                    onCerrarSesion: _cerrarSesion,
                  )
                : null,
            floatingActionButton: _pestana == 3
                ? FloatingActionButton.extended(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SucursalEditScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Nueva sucursal'),
                  )
                : null,
            bottomNavigationBar: ancha
                ? null
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BandaMarcas(),
                      NavigationBar(
                        selectedIndex: _pestana,
                        onDestinationSelected: (i) =>
                            setState(() => _pestana = i),
                        destinations: [
                          for (final (icono, etiqueta) in _secciones)
                            NavigationDestination(
                              icon: Icon(icono),
                              label: etiqueta,
                            ),
                        ],
                      ),
                    ],
                  ),
            body: SafeArea(
              child: ancha
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: contenido),
                        const BandaMarcas(),
                      ],
                    )
                  : contenido,
            ),
          ),
        );
      },
    );
  }
}

void abrirGuiaAdmin(BuildContext context, Guia guia) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AdminGuiaEditScreen(
        numeroGuia: guia.numeroGuia,
        fechaCreacion: guia.fechaCreacion,
      ),
    ),
  );
}

String haceCuanto(DateTime fecha) {
  final diff = DateTime.now().difference(fecha.toLocal());
  if (diff.inMinutes < 1) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  final dias = diff.inDays;
  return dias == 1 ? 'hace 1 día' : 'hace $dias días';
}

/// Las secciones del menú, en el orden de las pestañas.
const _secciones = [
  (Icons.description_sharp, 'Guías'),
  (Icons.local_shipping_sharp, 'Transportistas'),
  (Icons.bar_chart_sharp, 'Dashboard'),
  (Icons.store_sharp, 'Sucursales'),
];

/// Menú lateral del administrador en computadora (se abre con ☰ en la
/// cabecera y se esconde al elegir una opción).
class _MenuAdmin extends StatelessWidget {
  static const _fondoActivo = Color(0xFFEDF4F2);
  static const _iconoGris = Color(0xFF5B6B70);

  const _MenuAdmin({
    required this.seleccionado,
    required this.onSeleccion,
    required this.onRastrear,
    required this.onCerrarSesion,
  });

  final int seleccionado;
  final ValueChanged<int> onSeleccion;
  final VoidCallback onRastrear;
  final VoidCallback onCerrarSesion;

  @override
  Widget build(BuildContext context) {
    // Cierra el menú y luego abre la opción.
    VoidCallback cerrarY(VoidCallback accion) => () {
      Navigator.of(context).pop();
      accion();
    };
    Widget opcion(
      IconData icono,
      String etiqueta,
      VoidCallback onTap, {
      bool activo = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: activo ? _fondoActivo : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          minLeadingWidth: 22,
          leading: Icon(
            icono,
            size: 22,
            color: activo ? Ipesa.petroleo : _iconoGris,
          ),
          title: Text(
            etiqueta,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: activo ? FontWeight.w700 : FontWeight.w600,
              color: activo ? Ipesa.petroleo : Ipesa.texto,
            ),
          ),
          onTap: cerrarY(onTap),
        ),
      ),
    );

    return Drawer(
      backgroundColor: Colors.white,
      width: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Ipesa.petroleo,
            padding: const EdgeInsets.fromLTRB(24, 28, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MarcaRpa(tamano: 44, claro: true, conEslogan: true),
                const SizedBox(height: 14),
                Image.asset(
                  'assets/brand/ipesa_blanco.png',
                  width: 60,
                  semanticLabel: 'IPESA',
                ),
                const SizedBox(height: 6),
                const Text(
                  'Administrador',
                  style: TextStyle(
                    fontSize: 13,
                    color: Ipesa.suaveSobrePetroleo,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final (i, (icono, etiqueta)) in _secciones.indexed)
            opcion(
              icono,
              etiqueta,
              () => onSeleccion(i),
              activo: i == seleccionado,
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Divider(height: 1),
          ),
          opcion(Icons.manage_search_sharp, 'Rastrear', onRastrear),
          const Spacer(),
          const Divider(height: 1),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 26),
            leading: const Icon(Icons.logout_sharp, color: Ipesa.textoSuave),
            title: const Text(
              'Cerrar sesión',
              style: TextStyle(fontSize: 15, color: Ipesa.textoSuave),
            ),
            onTap: cerrarY(onCerrarSesion),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.titulo,
    required this.novedades,
    required this.onNovedades,
    required this.onMenu,
    required this.onRastrear,
    required this.onCerrarSesion,
  });

  final String titulo;
  final CentroNovedades novedades;
  final VoidCallback onNovedades;
  final VoidCallback? onMenu;
  final VoidCallback? onRastrear;
  final VoidCallback? onCerrarSesion;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final angosta = MediaQuery.sizeOf(context).width < 600;
    Widget boton(String tooltip, IconData icono, VoidCallback? onPressed) =>
        Padding(
          padding: EdgeInsets.only(left: angosta ? 6 : 8),
          child: IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            style: IconButton.styleFrom(
              fixedSize: Size.square(angosta ? 40 : 44),
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
          // En celular: el logo de RPA y el título a la izquierda. En
          // pantallas anchas: la marca (logo, nombre y eslogan) a la
          // izquierda, junto al menú, y el título de la sección a la derecha.
          if (angosta)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: MarcaRpa(tamano: 38, conNombre: false),
            ),
          if (onMenu != null)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: IconButton(
                tooltip: 'Menú',
                onPressed: onMenu,
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(44),
                  backgroundColor: Ipesa.petroleo,
                ),
                icon: const Icon(Icons.menu_rounded, color: Colors.white),
              ),
            ),
          // La marca toma el espacio libre; si no alcanza, se achica (y
          // sin el eslogan en pantallas medianas).
          if (!angosta)
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: MarcaRpa(
                  tamano: 44,
                  conEslogan: MediaQuery.sizeOf(context).width >= 1100,
                ),
              ),
            ),
          // En celular el título ocupa el espacio; en computadora mide lo
          // que necesita y la marca toma el resto.
          Flexible(
            flex: angosta ? 1 : 0,
            fit: angosta ? FlexFit.tight : FlexFit.loose,
            child: Column(
              crossAxisAlignment: angosta
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                // En celular, con los botones al lado, el título se
                // achica en vez de partirse en dos líneas.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: angosta
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Text(
                    titulo,
                    maxLines: 1,
                    style: Ipesa.titulo(angosta ? 22 : 26),
                  ),
                ),
                Text(
                  angosta ? 'Cada 15 s' : 'Se actualiza solo cada 15 s',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Ipesa.textoSuave),
                ),
              ],
            ),
          ),
          if (!angosta) const SizedBox(width: 10),
          Padding(
            padding: EdgeInsets.only(left: angosta ? 6 : 8),
            child: BotonNovedades(
              centro: novedades,
              onPressed: onNovedades,
              tamano: angosta ? 40 : 44,
            ),
          ),
          boton(
            'Actualizar',
            Icons.refresh,
            appState.cargando
                ? null
                : () => context.read<AppState>().cargarGuias(),
          ),
          if (onRastrear != null)
            boton('Rastrear guía', Icons.manage_search, onRastrear),
          if (onCerrarSesion != null)
            boton('Cerrar sesión', Icons.logout, onCerrarSesion),
        ],
      ),
    );
  }
}

Widget _conCarga(BuildContext context, AppState appState, Widget contenido) {
  if (appState.cargando && appState.guias.isEmpty) {
    return const Center(child: CircularProgressIndicator());
  }
  if (appState.error != null && appState.guias.isEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: Ipesa.textoSuave, size: 40),
            const SizedBox(height: 12),
            Text(
              'No se pudo cargar: ${appState.error}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.read<AppState>().cargarGuias(),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
  return contenido;
}

class _PestanaGuias extends StatefulWidget {
  const _PestanaGuias({required this.ancha});

  final bool ancha;

  @override
  State<_PestanaGuias> createState() => _PestanaGuiasState();
}

enum _Periodo { hoy, fechas }

class _PestanaGuiasState extends State<_PestanaGuias> {
  GrupoEstado? _filtro;
  String _busqueda = '';
  _Periodo _periodo = _Periodo.hoy;
  DateTimeRange? _fechas;

  static DateTime _dia(DateTime f) => DateTime(f.year, f.month, f.day);

  /// Días de la tarea (fecha de registro) que se muestran, inclusive.
  (DateTime, DateTime) get _rango {
    final hoy = _dia(DateTime.now());
    return switch (_periodo) {
      _Periodo.hoy => (hoy, hoy),
      _Periodo.fechas => (
        _dia(_fechas?.start ?? hoy),
        _dia(_fechas?.end ?? hoy),
      ),
    };
  }

  bool _enRango(Guia g) {
    final (desde, hasta) = _rango;
    final dia = _dia(g.fechaCreacion.toLocal());
    return !dia.isBefore(desde) && !dia.isAfter(hasta);
  }

  bool _coincide(Guia g) {
    if (_filtro != null && g.estado.grupo != _filtro) return false;
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return true;
    return g.numeroGuia.toLowerCase().contains(q) ||
        g.destinatario.toLowerCase().contains(q) ||
        g.transportista.toLowerCase().contains(q);
  }

  Future<void> _elegirFechas() async {
    final hoy = _dia(DateTime.now());
    final elegido = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: hoy,
      initialDateRange: _fechas ?? DateTimeRange(start: hoy, end: hoy),
      helpText: 'Fechas de las tareas',
      saveText: 'Ver',
    );
    if (elegido == null) return;
    setState(() {
      _fechas = elegido;
      _periodo = _Periodo.fechas;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final todas = appState.guias.where(_enRango).toList();
    final guias = todas.where(_coincide).toList()
      ..sort((a, b) => b.fechaActualizacion.compareTo(a.fechaActualizacion));
    final formato = DateFormat('dd/MM');
    final etiquetaFechas = _periodo == _Periodo.fechas && _fechas != null
        ? (_dia(_fechas!.start) == _dia(_fechas!.end)
              ? formato.format(_fechas!.start)
              : '${formato.format(_fechas!.start)} – '
                    '${formato.format(_fechas!.end)}')
        : 'Fechas';

    Widget segmento(
      String texto,
      bool activo,
      VoidCallback onTap, {
      IconData? icono,
    }) => Material(
      color: activo ? Ipesa.petroleo : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
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
    );

    final periodo = Container(
      height: 42,
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
          segmento(
            'Hoy',
            _periodo == _Periodo.hoy,
            () => setState(() => _periodo = _Periodo.hoy),
          ),
          const VerticalDivider(width: 1, color: Ipesa.borde),
          segmento(
            etiquetaFechas,
            _periodo == _Periodo.fechas,
            _elegirFechas,
            icono: Icons.calendar_month_outlined,
          ),
        ],
      ),
    );

    // Estado: lista desplegable con cuántas hay de cada uno. El trasbordo
    // no se filtra aparte (sus guías siguen en "Todas").
    final opcionesEstado = <(String, String, Color)>[
      ('todas', 'Todas · ${todas.length}', Ipesa.petroleo),
      for (final grupo in GrupoEstado.values)
        if (grupo != GrupoEstado.trasbordo)
          (
            grupo.name,
            '${grupo.etiqueta} · '
                '${todas.where((g) => g.estado.grupo == grupo).length}',
            _estadoDeGrupo(grupo).color,
          ),
    ];
    final estados = Container(
      height: 42,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Ipesa.borde),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const ValueKey('filtro_estado'),
          value: _filtro?.name ?? 'todas',
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.expand_more_rounded, color: Ipesa.etiqueta),
          items: [
            for (final (valor, texto, color) in opcionesEstado)
              DropdownMenuItem(
                value: valor,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      texto,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Ipesa.texto,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (v) => setState(
            () => _filtro = GrupoEstado.values
                .where((g) => g.name == v)
                .firstOrNull,
          ),
        ),
      ),
    );

    final filtros = Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [periodo, estados],
      ),
    );

    final lista = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            widget.ancha ? 0 : 24,
            0,
            widget.ancha ? 0 : 24,
            10,
          ),
          child: TextField(
            onChanged: (v) => setState(() => _busqueda = v),
            decoration: const InputDecoration(
              hintText: 'Buscar guía, cliente o transportista',
              prefixIcon: Icon(Icons.search),
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => context.read<AppState>().cargarGuias(),
            child: guias.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 100),
                      Center(
                        child: Text(
                          'No hay guías en estas fechas con este filtro.',
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      widget.ancha ? 0 : 24,
                      0,
                      widget.ancha ? 0 : 24,
                      24,
                    ),
                    itemCount: guias.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) =>
                        TarjetaGuiaAdmin(guia: guias[i]),
                  ),
          ),
        ),
      ],
    );

    return _conCarga(
      context,
      appState,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          filtros,
          Expanded(
            child: widget.ancha
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 400, child: lista),
                        const SizedBox(width: 18),
                        Expanded(child: MapaGuias(guias: guias)),
                      ],
                    ),
                  )
                : lista,
          ),
        ],
      ),
    );
  }

  static EstadoGuia _estadoDeGrupo(GrupoEstado g) => switch (g) {
    GrupoEstado.enRuta => EstadoGuia.enRuta,
    GrupoEstado.trasbordo => EstadoGuia.enProcesoTrasbordo,
    GrupoEstado.entregado => EstadoGuia.entregado,
    GrupoEstado.rechazado => EstadoGuia.rechazado,
  };
}

/// Una guía en las listas del administrador; tocarla abre su detalle.
class TarjetaGuiaAdmin extends StatelessWidget {
  const TarjetaGuiaAdmin({
    super.key,
    required this.guia,
    this.mostrarTransportista = true,
  });

  final Guia guia;

  /// En el desglose de un transportista su nombre sobra.
  final bool mostrarTransportista;

  @override
  Widget build(BuildContext context) {
    // La sucursal y la fecha de entrega van en sus propias líneas
    // (LugaresSucursal); aquí solo cuánto hace.
    final enSucursal = sucursalDeEntrega(context, guia) != null;
    final detalle = enSucursal
        ? haceCuanto(guia.fechaActualizacion)
        : guia.estado.esFinal && guia.tieneUbicacionCierre
        ? 'cerrada ${haceCuanto(guia.fechaActualizacion)} · ver en el mapa'
        : haceCuanto(guia.fechaActualizacion);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => abrirGuiaAdmin(context, guia),
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
              Text(
                mostrarTransportista
                    ? '${guia.transportista} · $detalle'
                    : detalle,
                style: const TextStyle(fontSize: 13, color: Ipesa.textoSuave),
              ),
              LugaresSucursal(guia: guia, conCierre: true),
              if (guia.enDespachoCorte)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 15,
                        color: Ipesa.petroleo,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Despacho Corte ${guia.despachoCorte}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Ipesa.petroleo,
                        ),
                      ),
                    ],
                  ),
                ),
              if (guia.tieneComprobanteAgencia)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.receipt_long_outlined,
                        size: 15,
                        color: Ipesa.petroleo,
                      ),
                      const SizedBox(width: 4),
                      Expanded(child: _LineasComprobante(guia: guia)),
                    ],
                  ),
                ),
              if (guia.resumenTransbordo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.swap_horiz_rounded,
                        size: 16,
                        color: guia.transbordoRechazado
                            ? EstadoGuia.rechazado.color
                            : EstadoGuia.enRuta.color,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          guia.resumenTransbordo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: guia.transbordoRechazado
                                ? EstadoGuia.rechazado.color
                                : EstadoGuia.enRuta.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (guia.eliminacionPendiente)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Pide eliminarla'
                    '${guia.motivoEliminacion.trim().isEmpty ? '' : ': ${guia.motivoEliminacion.trim()}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: EstadoGuia.rechazado.color,
                    ),
                  ),
                ),
              if (guia.estado == EstadoGuia.rechazado &&
                  guia.motivoRechazo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Motivo: ${guia.motivoRechazo}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: EstadoGuia.rechazado.color,
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

/// Mapa con la última ubicación de cada guía (o donde se cerró) y el
/// perímetro de las sucursales. Con [recorrido] (las guías de un solo
/// transportista) une además esos puntos en orden de hora y marca con un
/// camión el último.
class MapaGuias extends StatelessWidget {
  const MapaGuias({super.key, required this.guias, this.recorrido = false});

  final List<Guia> guias;
  final bool recorrido;

  static LatLng? _punto(Guia g) {
    if (g.tieneUbicacionCierre) return LatLng(g.cierreLat!, g.cierreLng!);
    if (g.ultimaLat != null && g.ultimaLng != null) {
      return LatLng(g.ultimaLat!, g.ultimaLng!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sucursales = context.watch<AppState>().sucursales;
    final conPunto = [
      for (final g in guias)
        if (_punto(g) case final p?) (g, p),
    ];
    final puntos = [for (final (_, p) in conPunto) p];
    // Los eventos conocidos del transportista, del más antiguo al último.
    final camino = recorrido
        ? ([...conPunto]..sort(
                (a, b) =>
                    a.$1.fechaActualizacion.compareTo(b.$1.fechaActualizacion),
              ))
              .map((e) => e.$2)
              .toList()
        : const <LatLng>[];

    final opciones = puntos.length >= 2
        ? MapOptions(
            initialCameraFit: CameraFit.coordinates(
              coordinates: puntos,
              padding: const EdgeInsets.all(56),
              maxZoom: 15,
            ),
            backgroundColor: fondoMapa,
          )
        : MapOptions(
            initialCenter: puntos.isEmpty
                ? const LatLng(-12.0464, -77.0428)
                : puntos.first,
            initialZoom: puntos.isEmpty ? 11 : 14,
            backgroundColor: fondoMapa,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(Ipesa.radio),
      child: Stack(
        children: [
          FlutterMap(
            key: ValueKey(puntos.length),
            options: opciones,
            children: [
              ...capasBaseMapa(),
              for (final s in sucursales) capaPerimetro(s),
              if (camino.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: camino,
                      strokeWidth: 3,
                      color: _colorRecorrido,
                      pattern: StrokePattern.dashed(segments: const [10, 7]),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final (g, p) in conPunto)
                    Marker(
                      point: p,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: Tooltip(
                        message:
                            '${g.numeroGuia} · ${g.estado.etiqueta} · '
                            '${g.transportista}',
                        child: GestureDetector(
                          onTap: () => abrirGuiaAdmin(context, g),
                          child: pinMapa(g.estado.color),
                        ),
                      ),
                    ),
                  if (camino.isNotEmpty)
                    Marker(
                      point: camino.last,
                      width: 34,
                      height: 34,
                      child: Tooltip(
                        message: 'Última ubicación conocida',
                        child: Container(
                          decoration: BoxDecoration(
                            color: Ipesa.petroleo,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                          ),
                          child: const Icon(
                            Icons.local_shipping_rounded,
                            size: 17,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              atribucionMapa,
            ],
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(Ipesa.radioCampo),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  const _Leyenda(color: Color(0xFF2459A8), texto: 'En ruta'),
                  const _Leyenda(color: Color(0xFF1D6B41), texto: 'Entregado'),
                  if (recorrido)
                    const _Leyenda(color: _colorRecorrido, texto: 'Recorrido')
                  else
                    const _Leyenda(
                      color: Ipesa.turquesa,
                      texto: 'Perímetro de sucursal',
                      anillo: true,
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

// Se ve sobre el mapa oscuro.
const _colorRecorrido = Color(0xFF7FD1C7);

class _Leyenda extends StatelessWidget {
  const _Leyenda({
    required this.color,
    required this.texto,
    this.anillo = false,
  });

  final Color color;
  final String texto;
  final bool anillo;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: anillo ? Colors.transparent : color,
            border: anillo ? Border.all(color: color, width: 2) : null,
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

class _PestanaDashboard extends StatelessWidget {
  const _PestanaDashboard();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return _conCarga(context, appState, const PestanaDashboard());
  }
}

class _PestanaSucursales extends StatelessWidget {
  const _PestanaSucursales();

  @override
  Widget build(BuildContext context) {
    final sucursales = context.watch<AppState>().sucursales;

    if (sucursales.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aún no hay sucursales. Crea una con "Nueva sucursal" y marca su '
            'perímetro en el mapa: los traslados entre sucursales solo pueden '
            'registrar su llegada dentro de ese perímetro.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Ipesa.textoSuave),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
      itemCount: sucursales.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final s = sucursales[i];
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Ipesa.menta,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.storefront, color: Ipesa.petroleo),
            ),
            title: Text(s.nombre, style: Ipesa.titulo(16)),
            subtitle: Text('Perímetro de ${s.radioM.round()} m'),
            trailing: const Icon(Icons.chevron_right, color: Ipesa.textoSuave),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SucursalEditScreen(sucursal: s),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// El comprobante de agencia de la guía: primero el N° y el monto (lo que
/// se busca), debajo la agencia y su RUC.
class _LineasComprobante extends StatelessWidget {
  const _LineasComprobante({required this.guia});

  final Guia guia;

  @override
  Widget build(BuildContext context) {
    final principal = [
      if (guia.agenciaComprobante.isNotEmpty) 'N° ${guia.agenciaComprobante}',
      if (guia.agenciaMonto case final m?) 'S/ ${m.toStringAsFixed(2)}',
    ];
    final agencia = [
      if (guia.agenciaRazonSocial.isNotEmpty) guia.agenciaRazonSocial,
      if (guia.agenciaRuc.isNotEmpty) 'RUC ${guia.agenciaRuc}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (principal.isNotEmpty)
          Text(
            principal.join(' · '),
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: Ipesa.texto,
            ),
          ),
        if (agencia.isNotEmpty)
          Text(
            agencia.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Ipesa.etiqueta,
            ),
          ),
      ],
    );
  }
}
