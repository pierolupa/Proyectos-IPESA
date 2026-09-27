import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../models/tipo_entrega.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/actualizacion_automatica.dart';
import '../../widgets/carrusel_marcas.dart';
import '../../widgets/estado_badge.dart';
import 'capture_flow_screen.dart';
import 'guia_detail_screen.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  bool _verEntregadas = false;

  static bool _esHoy(DateTime fecha) {
    final f = fecha.toLocal();
    final hoy = DateTime.now();
    return f.year == hoy.year && f.month == hoy.month && f.day == hoy.day;
  }

  static String _saludo() {
    final hora = DateTime.now().hour;
    if (hora < 12) return 'Buenos días,';
    if (hora < 19) return 'Buenas tardes,';
    return 'Buenas noches,';
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final nombre = appState.transportistaActual;
    final todas = appState.guiasDelTransportista(nombre);
    // Las entregadas desaparecen de "Pendientes"; las de hoy quedan a la
    // vista en la otra pestaña.
    final pendientes = todas.where((g) => !g.estado.esFinal).toList();
    final entregadasHoy = todas
        .where((g) => g.estado.esFinal && _esHoy(g.fechaActualizacion))
        .toList();
    final guias = _verEntregadas ? entregadasHoy : pendientes;

    return Scaffold(
      bottomNavigationBar: const BandaMarcas(),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.photo_camera_outlined),
        label: const Text('Nueva guía'),
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const CaptureFlowScreen())),
      ),
      body: SafeArea(
        child: ActualizacionAutomatica(
          intervalo: const Duration(seconds: 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    _Avatar(nombre: nombre),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _saludo(),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Ipesa.textoSuave,
                            ),
                          ),
                          Text(nombre, style: Ipesa.titulo(20)),
                        ],
                      ),
                    ),
                    _BotonRedondo(
                      tooltip: 'Cerrar sesión',
                      icon: Icons.logout,
                      onPressed: () {
                        context.read<AppState>().cerrarSesion();
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: _Segmentos(
                  izquierda: 'Pendientes · ${pendientes.length}',
                  derecha: 'Entregadas hoy · ${entregadasHoy.length}',
                  derechaActiva: _verEntregadas,
                  onCambio: (v) => setState(() => _verEntregadas = v),
                ),
              ),
              Expanded(child: _lista(context, appState, guias)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lista(BuildContext context, AppState appState, List<Guia> guias) {
    if (appState.cargando && guias.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (appState.error != null && guias.isEmpty) {
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
    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().cargarGuias(),
      child: guias.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Text(
                    _verEntregadas
                        ? 'Todavía no entregas ninguna guía hoy.'
                        : 'No tienes tareas pendientes.',
                    style: const TextStyle(color: Ipesa.textoSuave),
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
              itemCount: guias.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, i) => _TarjetaTarea(guia: guias[i]),
            ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.nombre});

  final String nombre;

  @override
  Widget build(BuildContext context) {
    final iniciales = nombre
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Ipesa.petroleo,
        shape: BoxShape.circle,
      ),
      child: Text(
        iniciales,
        style: Ipesa.titulo(
          16,
          color: Colors.white,
        ).copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _BotonRedondo extends StatelessWidget {
  const _BotonRedondo({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        backgroundColor: Colors.white,
        side: const BorderSide(color: Ipesa.borde),
      ),
      icon: Icon(icon, color: Ipesa.petroleo, size: 20),
    );
  }
}

class _Segmentos extends StatelessWidget {
  const _Segmentos({
    required this.izquierda,
    required this.derecha,
    required this.derechaActiva,
    required this.onCambio,
  });

  final String izquierda;
  final String derecha;
  final bool derechaActiva;
  final ValueChanged<bool> onCambio;

  @override
  Widget build(BuildContext context) {
    Widget opcion(String texto, bool activa, bool valor) => Expanded(
      child: Material(
        color: activa ? Colors.white : Colors.transparent,
        shape: const StadiumBorder(),
        elevation: activa ? 1 : 0,
        shadowColor: const Color(0x330F4C5C),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => onCambio(valor),
          child: SizedBox(
            height: 40,
            child: Center(
              child: Text(
                texto,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: activa ? Ipesa.petroleo : Ipesa.textoSuave,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const ShapeDecoration(
        color: Ipesa.segmento,
        shape: StadiumBorder(),
      ),
      child: Row(
        children: [
          opcion(izquierda, !derechaActiva, false),
          opcion(derecha, derechaActiva, true),
        ],
      ),
    );
  }
}

class _TarjetaTarea extends StatelessWidget {
  const _TarjetaTarea({required this.guia});

  final Guia guia;

  @override
  Widget build(BuildContext context) {
    final esTraslado = guia.tipoEntrega == TipoEntrega.entreSucursales;
    final pasos = esTraslado
        ? const ['En ruta', 'Trasbordo', 'Llegada', 'Recibida']
        : const ['Registrada', 'En ruta', 'Entregada'];
    final actual = switch (guia.estado) {
      EstadoGuia.enRuta => esTraslado ? 0 : 1,
      EstadoGuia.enProcesoTrasbordo => 1,
      EstadoGuia.recepcionSucursal => 2,
      EstadoGuia.entregado || EstadoGuia.finalizado => pasos.length - 1,
    };
    final sucursal = esTraslado
        ? context.read<AppState>().sucursalPorNombre(guia.destino)
        : null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(Ipesa.radio),
      child: InkWell(
        borderRadius: BorderRadius.circular(Ipesa.radio),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GuiaDetailScreen(numeroGuia: guia.numeroGuia),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(guia.numeroGuia, style: Ipesa.titulo(17)),
                  ),
                  EstadoBadge(estado: guia.estado),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                guia.destinatario,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                guia.destino,
                style: const TextStyle(fontSize: 15, color: Ipesa.textoSuave),
              ),
              if (guia.estado.esFinal) ...[
                const SizedBox(height: 10),
                Text(
                  'Entregada a las '
                  '${DateFormat('HH:mm').format(guia.fechaActualizacion.toLocal())}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: guia.estado.color,
                  ),
                ),
              ] else if (guia.estado == EstadoGuia.enProcesoTrasbordo) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Ipesa.menta,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.my_location,
                        size: 18,
                        color: Ipesa.petroleo,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sucursal == null
                              ? 'La sucursal aún no tiene perímetro marcado.'
                              : 'Registra la llegada dentro de '
                                    '${sucursal.radioM.round()} m de la sucursal',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Ipesa.petroleo,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 14),
                _Progreso(pasos: pasos, actual: actual),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Progreso extends StatelessWidget {
  const _Progreso({required this.pasos, required this.actual});

  final List<String> pasos;
  final int actual;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < pasos.length; i++) {
      final hecho = i <= actual;
      items.add(
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hecho ? Ipesa.turquesa : Colors.transparent,
            border: hecho ? null : Border.all(color: Ipesa.borde, width: 2),
          ),
        ),
      );
      if (i < pasos.length - 1) {
        items.add(
          Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: i < actual ? Ipesa.turquesa : Ipesa.borde,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }
    }
    return Column(
      children: [
        Row(children: items),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final (i, p) in pasos.indexed)
              Expanded(
                child: Text(
                  p,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: i == 0
                      ? TextAlign.start
                      : i == pasos.length - 1
                      ? TextAlign.end
                      : TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Ipesa.textoSuave),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
