import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../services/notificador.dart';
import '../../state/app_state.dart';
import '../../widgets/actualizacion_automatica.dart';
import '../../widgets/guia_card.dart';
import 'admin_guia_edit_screen.dart';
import 'sucursal_edit_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _pestana = 0;
  bool _notificacionesActivas = Notificador.permitido;

  static const _titulos = ['Guías', 'Tareas por transportista', 'Sucursales'];

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
            const Icon(Icons.notifications_active, color: Colors.amber),
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
                onPressed: () => _abrirGuia(context, cambios.first.guia),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_titulos[_pestana]),
        actions: [
          IconButton(
            tooltip: _notificacionesActivas
                ? 'Notificaciones activadas'
                : 'Activar notificaciones',
            icon: Icon(
              _notificacionesActivas
                  ? Icons.notifications_active
                  : Icons.notifications_off_outlined,
            ),
            onPressed: _notificacionesActivas ? null : _activarNotificaciones,
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: appState.cargando
                ? null
                : () => context.read<AppState>().cargarGuias(),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<AppState>().cerrarSesion();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
        ],
      ),
      body: ActualizacionAutomatica(
        intervalo: const Duration(seconds: 15),
        onCambios: _avisarCambios,
        child: switch (_pestana) {
          0 => const _PestanaGuias(),
          1 => const _PestanaTareas(),
          _ => const _PestanaSucursales(),
        },
      ),
      floatingActionButton: _pestana == 2
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SucursalEditScreen()),
              ),
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Nueva sucursal'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pestana,
        onDestinationSelected: (i) => setState(() => _pestana = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Guías'),
          NavigationDestination(icon: Icon(Icons.groups), label: 'Tareas'),
          NavigationDestination(icon: Icon(Icons.store), label: 'Sucursales'),
        ],
      ),
    );
  }
}

void _abrirGuia(BuildContext context, Guia guia) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AdminGuiaEditScreen(numeroGuia: guia.numeroGuia),
    ),
  );
}

/// Envuelve el contenido con los estados comunes de carga/error.
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
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
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
  return RefreshIndicator(
    onRefresh: () => context.read<AppState>().cargarGuias(),
    child: contenido,
  );
}

class _PestanaGuias extends StatefulWidget {
  const _PestanaGuias();

  @override
  State<_PestanaGuias> createState() => _PestanaGuiasState();
}

class _PestanaGuiasState extends State<_PestanaGuias> {
  GrupoEstado? _filtro;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final todas = appState.guias;
    final guias =
        todas
            .where((g) => _filtro == null || g.estado.grupo == _filtro)
            .toList()
          ..sort(
            (a, b) => b.fechaActualizacion.compareTo(a.fechaActualizacion),
          );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FiltroChip(
                  label: 'Todas (${todas.length})',
                  selected: _filtro == null,
                  onTap: () => setState(() => _filtro = null),
                ),
                for (final grupo in GrupoEstado.values)
                  _FiltroChip(
                    label:
                        '${grupo.etiqueta} '
                        '(${todas.where((g) => g.estado.grupo == grupo).length})',
                    selected: _filtro == grupo,
                    onTap: () => setState(() => _filtro = grupo),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _conCarga(
            context,
            appState,
            guias.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('No hay guías con este filtro.')),
                    ],
                  )
                : ListView.builder(
                    itemCount: guias.length,
                    itemBuilder: (context, i) => GuiaCard(
                      guia: guias[i],
                      onTap: () => _abrirGuia(context, guias[i]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Las tareas que cada transportista registró, agrupadas por persona.
class _PestanaTareas extends StatelessWidget {
  const _PestanaTareas();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final porTransportista = <String, List<Guia>>{};
    for (final g in appState.guias) {
      porTransportista.putIfAbsent(g.transportista, () => []).add(g);
    }
    final nombres = porTransportista.keys.toList()..sort();

    return _conCarga(
      context,
      appState,
      nombres.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Center(child: Text('Aún no hay tareas registradas.')),
              ],
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                for (final nombre in nombres)
                  _GrupoTransportista(
                    nombre: nombre,
                    guias: porTransportista[nombre]!
                      ..sort(
                        (a, b) => b.fechaActualizacion.compareTo(
                          a.fechaActualizacion,
                        ),
                      ),
                  ),
              ],
            ),
    );
  }
}

class _GrupoTransportista extends StatelessWidget {
  const _GrupoTransportista({required this.nombre, required this.guias});

  final String nombre;
  final List<Guia> guias;

  @override
  Widget build(BuildContext context) {
    int contar(GrupoEstado g) => guias.where((x) => x.estado.grupo == g).length;
    final resumen = GrupoEstado.values
        .map((g) => '${contar(g)} ${g.etiqueta.toLowerCase()}')
        .join(' · ');

    return ExpansionTile(
      initiallyExpanded: true,
      leading: CircleAvatar(
        child: Text(nombre.isEmpty ? '?' : nombre[0].toUpperCase()),
      ),
      title: Text(
        nombre.isEmpty ? 'Sin transportista' : nombre,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text('${guias.length} tareas · $resumen'),
      children: [
        for (final g in guias)
          GuiaCard(guia: g, onTap: () => _abrirGuia(context, g)),
      ],
    );
  }
}

class _PestanaSucursales extends StatelessWidget {
  const _PestanaSucursales();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final sucursales = appState.sucursales;

    if (sucursales.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aún no hay sucursales. Crea una con "Nueva sucursal" y marca su '
            'perímetro en el mapa: los traslados entre sucursales solo pueden '
            'registrar su llegada dentro de ese perímetro.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final s in sucursales)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: ListTile(
              leading: const Icon(Icons.store, color: Colors.purple),
              title: Text(s.nombre),
              subtitle: Text('Perímetro de ${s.radioM.round()} m'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SucursalEditScreen(sucursal: s),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FiltroChip extends StatelessWidget {
  const _FiltroChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
