import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../services/notificador.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/actualizacion_automatica.dart';
import '../../widgets/estado_badge.dart';
import '../../widgets/mapa_ubicacion.dart';
import 'admin_guia_edit_screen.dart';
import 'recorrido_timeline.dart';
import 'sucursal_edit_screen.dart';

const _anchoEscritorio = 900.0;

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _pestana = 0;
  bool _notificacionesActivas = Notificador.permitido;

  static const _titulos = [
    'Operación de hoy',
    'Recorrido de hoy',
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
    final titulo = cambios.length == 1
        ? 'IPESA · Novedad'
        : 'IPESA · ${cambios.length} novedades';
    final cuerpo = cambios.map((c) => c.mensaje).join('\n');
    if (Notificador.paginaOculta) Notificador.mostrar(titulo, cuerpo);

    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Row(
          children: [
            const Icon(Icons.notifications_active, color: Ipesa.menta),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                cambios.length == 1
                    ? cambios.first.mensaje
                    : '${cambios.length} novedades:\n$cuerpo',
              ),
            ),
          ],
        ),
        action: cambios.length == 1
            ? SnackBarAction(
                label: 'Ver',
                textColor: Ipesa.menta,
                onPressed: () => abrirGuiaAdmin(context, cambios.first.guia),
              )
            : null,
      ),
    );
  }

  void _cerrarSesion() {
    context.read<AppState>().cerrarSesion();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancha = constraints.maxWidth >= _anchoEscritorio;
        final contenido = ActualizacionAutomatica(
          intervalo: const Duration(seconds: 15),
          onCambios: _avisarCambios,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Cabecera(
                titulo: _titulos[_pestana],
                notificacionesActivas: _notificacionesActivas,
                onActivarNotificaciones: _activarNotificaciones,
                onCerrarSesion: ancha ? null : _cerrarSesion,
              ),
              Expanded(
                child: switch (_pestana) {
                  0 => _PestanaGuias(ancha: ancha),
                  1 => const _PestanaRecorrido(),
                  _ => const _PestanaSucursales(),
                },
              ),
            ],
          ),
        );

        return Scaffold(
          floatingActionButton: _pestana == 2
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
              : NavigationBar(
                  selectedIndex: _pestana,
                  onDestinationSelected: (i) => setState(() => _pestana = i),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      label: 'Guías',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.timeline),
                      label: 'Recorrido',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.storefront_outlined),
                      label: 'Sucursales',
                    ),
                  ],
                ),
          body: SafeArea(
            child: ancha
                ? Row(
                    children: [
                      _Riel(
                        seleccionado: _pestana,
                        onSeleccion: (i) => setState(() => _pestana = i),
                        onCerrarSesion: _cerrarSesion,
                      ),
                      Expanded(child: contenido),
                    ],
                  )
                : contenido,
          ),
        );
      },
    );
  }
}

void abrirGuiaAdmin(BuildContext context, Guia guia) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AdminGuiaEditScreen(numeroGuia: guia.numeroGuia),
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

class _Riel extends StatelessWidget {
  const _Riel({
    required this.seleccionado,
    required this.onSeleccion,
    required this.onCerrarSesion,
  });

  final int seleccionado;
  final ValueChanged<int> onSeleccion;
  final VoidCallback onCerrarSesion;

  @override
  Widget build(BuildContext context) {
    Widget item(int i, IconData icono, String etiqueta) {
      final activo = i == seleccionado;
      return Tooltip(
        message: etiqueta,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Material(
            color: activo ? Ipesa.turquesa : Colors.transparent,
            borderRadius: BorderRadius.circular(Ipesa.radioCampo),
            child: InkWell(
              borderRadius: BorderRadius.circular(Ipesa.radioCampo),
              onTap: () => onSeleccion(i),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icono,
                      size: 22,
                      color: activo ? Colors.white : Ipesa.suaveSobrePetroleo,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      etiqueta,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: activo ? Colors.white : Ipesa.suaveSobrePetroleo,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 84,
      color: Ipesa.petroleo,
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            'IPESA',
            style: Ipesa.titulo(
              13,
              color: Colors.white,
            ).copyWith(letterSpacing: 2),
          ),
          const SizedBox(height: 24),
          item(0, Icons.receipt_long_outlined, 'Guías'),
          item(1, Icons.timeline, 'Recorrido'),
          item(2, Icons.storefront_outlined, 'Sucursales'),
          const Spacer(),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: onCerrarSesion,
            style: IconButton.styleFrom(
              fixedSize: const Size(44, 44),
              backgroundColor: Ipesa.menta,
            ),
            icon: const Icon(Icons.logout, color: Ipesa.petroleo, size: 20),
          ),
        ],
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.titulo,
    required this.notificacionesActivas,
    required this.onActivarNotificaciones,
    required this.onCerrarSesion,
  });

  final String titulo;
  final bool notificacionesActivas;
  final VoidCallback onActivarNotificaciones;
  final VoidCallback? onCerrarSesion;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    Widget boton(String tooltip, IconData icono, VoidCallback? onPressed) =>
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
                  titulo,
                  style: Ipesa.titulo(
                    MediaQuery.sizeOf(context).width < 600 ? 22 : 26,
                  ),
                ),
                const Text(
                  'Se actualiza solo cada 15 s',
                  style: TextStyle(fontSize: 14, color: Ipesa.textoSuave),
                ),
              ],
            ),
          ),
          boton(
            notificacionesActivas
                ? 'Notificaciones activadas'
                : 'Activar notificaciones',
            notificacionesActivas
                ? Icons.notifications_active
                : Icons.notifications_none,
            notificacionesActivas ? null : onActivarNotificaciones,
          ),
          boton(
            'Actualizar',
            Icons.refresh,
            appState.cargando
                ? null
                : () => context.read<AppState>().cargarGuias(),
          ),
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

class _PestanaGuiasState extends State<_PestanaGuias> {
  GrupoEstado? _filtro;
  String _busqueda = '';

  bool _coincide(Guia g) {
    if (_filtro != null && g.estado.grupo != _filtro) return false;
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return true;
    return g.numeroGuia.toLowerCase().contains(q) ||
        g.destinatario.toLowerCase().contains(q) ||
        g.transportista.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final todas = appState.guias;
    final guias = todas.where(_coincide).toList()
      ..sort((a, b) => b.fechaActualizacion.compareTo(a.fechaActualizacion));

    final filtros = Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _Filtro(
            etiqueta: 'Todas · ${todas.length}',
            seleccionado: _filtro == null,
            onTap: () => setState(() => _filtro = null),
          ),
          for (final grupo in GrupoEstado.values)
            _Filtro(
              etiqueta:
                  '${grupo.etiqueta} · '
                  '${todas.where((g) => g.estado.grupo == grupo).length}',
              seleccionado: _filtro == grupo,
              estado: _estadoDeGrupo(grupo),
              onTap: () => setState(() => _filtro = grupo),
            ),
        ],
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
                      Center(child: Text('No hay guías con este filtro.')),
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
                        _TarjetaGuiaAdmin(guia: guias[i]),
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
                        Expanded(child: _MapaGuias(guias: guias)),
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
  };
}

class _Filtro extends StatelessWidget {
  const _Filtro({
    required this.etiqueta,
    required this.seleccionado,
    required this.onTap,
    this.estado,
  });

  final String etiqueta;
  final bool seleccionado;
  final VoidCallback onTap;
  final EstadoGuia? estado;

  @override
  Widget build(BuildContext context) {
    final fondo = estado?.colorFondo ?? Ipesa.menta;
    final texto = estado?.color ?? Ipesa.petroleo;
    return ChoiceChip(
      label: Text(etiqueta),
      selected: seleccionado,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      backgroundColor: Colors.white,
      selectedColor: fondo,
      side: BorderSide(color: seleccionado ? texto : Ipesa.borde),
      labelStyle: TextStyle(
        fontFamily: Ipesa.fuenteTexto,
        color: seleccionado ? texto : Ipesa.texto,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    );
  }
}

class _TarjetaGuiaAdmin extends StatelessWidget {
  const _TarjetaGuiaAdmin({required this.guia});

  final Guia guia;

  @override
  Widget build(BuildContext context) {
    final detalle = guia.estado.esFinal && guia.tieneUbicacionCierre
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
                '${guia.transportista} · $detalle',
                style: const TextStyle(fontSize: 13, color: Ipesa.textoSuave),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mapa con la última ubicación de cada guía (o donde se cerró) y el
/// perímetro de las sucursales.
class _MapaGuias extends StatelessWidget {
  const _MapaGuias({required this.guias});

  final List<Guia> guias;

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

    final opciones = puntos.length >= 2
        ? MapOptions(
            initialCameraFit: CameraFit.coordinates(
              coordinates: puntos,
              padding: const EdgeInsets.all(56),
              maxZoom: 15,
            ),
          )
        : MapOptions(
            initialCenter: puntos.isEmpty
                ? const LatLng(-12.0464, -77.0428)
                : puntos.first,
            initialZoom: puntos.isEmpty ? 11 : 14,
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
                          child: Icon(
                            Icons.location_pin,
                            size: 40,
                            color: g.estado.color,
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
              child: const Wrap(
                spacing: 16,
                children: [
                  _Leyenda(color: Color(0xFF2459A8), texto: 'En ruta'),
                  _Leyenda(color: Color(0xFF8A4F00), texto: 'Trasbordo'),
                  _Leyenda(color: Color(0xFF1D6B41), texto: 'Entregado'),
                  _Leyenda(
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

class _PestanaRecorrido extends StatelessWidget {
  const _PestanaRecorrido();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return _conCarga(
      context,
      appState,
      RefreshIndicator(
        onRefresh: () => context.read<AppState>().cargarGuias(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            RecorridoTimeline(
              guias: appState.guias,
              onGuia: (g) => abrirGuiaAdmin(context, g),
            ),
          ],
        ),
      ),
    );
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
