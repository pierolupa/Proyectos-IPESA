import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../models/tipo_entrega.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/marca_rpa.dart';
import '../../widgets/acciones_tarea.dart';
import '../../widgets/actualizacion_automatica.dart';
import '../../widgets/carrusel_marcas.dart';
import '../../widgets/despacho_corte.dart';
import '../../widgets/estado_badge.dart';
import '../../widgets/transbordo.dart';
import 'capture_flow_screen.dart';
import 'entrega_flow_screen.dart';
import 'entrega_ia_screen.dart';
import 'guia_detail_screen.dart';
import 'rechazo_sheet.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  bool _verEntregadas = false;
  final _busqueda = TextEditingController();

  final _scaffold = GlobalKey<ScaffoldState>();

  /// Transbordos recibidos ya anunciados en esta sesión (uno por tarea).
  final _anunciados = <String>{};
  bool _anunciando = false;

  /// Al entrar (o al llegar uno nuevo), anuncia el primer transbordo que
  /// otro transportista le pasa y aún no vio.
  void _anunciarTransbordos(List<Guia> recibidos) {
    if (_anunciando) return;
    final nuevo = recibidos.where((g) => !_anunciados.contains(g.clave));
    if (nuevo.isEmpty) return;
    final guia = nuevo.first;
    _anunciados.add(guia.clave);
    _anunciando = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) await mostrarAnuncioTransbordo(context, guia);
      _anunciando = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

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

  /// Número de guía, cliente, destino, pedido o entrega.
  static bool _coincide(Guia g, String q) {
    if (q.isEmpty) return true;
    return [
      g.numeroGuia,
      g.destinatario,
      g.destino,
      g.numeroPedido,
      g.numeroEntrega,
    ].any((c) => c.toLowerCase().contains(q));
  }

  void _nuevaGuia() =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const CaptureFlowScreen()));

  void _cerrarSesion() {
    context.read<AppState>().cerrarSesion();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _entregaConIA() =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const EntregaIAScreen()));

  void _despachoCorte() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const CaptureFlowScreen(despachoCorte: true),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final nombre = appState.transportistaActual;
    final todas = appState.guiasDelTransportista(nombre);
    final recibidos = appState.transbordosPara(nombre);
    _anunciarTransbordos(recibidos);
    // Las entregadas desaparecen de "Pendientes"; las de hoy quedan a la
    // vista en la otra pestaña.
    final pendientes = todas.where((g) => !g.estado.esCerrada).toList();
    final entregadasHoy = todas
        .where((g) => g.estado.esFinal && _esHoy(g.fechaActualizacion))
        .toList();
    final total = pendientes.length + entregadasHoy.length;
    final avance = total == 0
        ? 0
        : (entregadasHoy.length * 100 / total).round();
    final q = _busqueda.text.trim().toLowerCase();
    final guias = (_verEntregadas ? entregadasHoy : pendientes)
        .where((g) => _coincide(g, q))
        .toList();

    return Scaffold(
      key: _scaffold,
      backgroundColor: Ipesa.fondo,
      drawer: _MenuTransportista(
        nombre: nombre,
        onDespachoCorte: _despachoCorte,
        onEntregaConIA: _entregaConIA,
        onCerrarSesion: _cerrarSesion,
      ),
      bottomNavigationBar: const BandaMarcas(),
      // Sin pendientes, "Nueva guía" ya está en la tarjeta de ruta completada.
      floatingActionButton: !_verEntregadas && pendientes.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: Ipesa.turquesa,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Nueva guía'),
              onPressed: _nuevaGuia,
            ),
      body: ActualizacionAutomatica(
        intervalo: const Duration(seconds: 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Cabecera(
              saludo: _saludo(),
              nombre: nombre,
              pendientes: pendientes.length,
              entregadas: entregadasHoy.length,
              avance: avance,
              onMenu: () => _scaffold.currentState?.openDrawer(),
              onCerrarSesion: _cerrarSesion,
            ),
            _Pestanas(
              izquierda: 'Pendientes · ${pendientes.length}',
              derecha: 'Entregadas hoy · ${entregadasHoy.length}',
              derechaActiva: _verEntregadas,
              onCambio: (v) => setState(() => _verEntregadas = v),
            ),
            Expanded(
              child: _lista(
                context,
                appState,
                guias,
                sinPendientes: !_verEntregadas && pendientes.isEmpty,
                entregadasHoy: entregadasHoy.length,
                recibidos: _verEntregadas ? const [] : recibidos,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buscador() {
    return TextField(
      controller: _busqueda,
      onChanged: (_) => setState(() {}),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Buscar guía, cliente o destino',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        suffixIcon: _busqueda.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpiar búsqueda',
                icon: const Icon(Icons.close),
                onPressed: () => setState(_busqueda.clear),
              ),
      ),
    );
  }

  Widget _lista(
    BuildContext context,
    AppState appState,
    List<Guia> guias, {
    required bool sinPendientes,
    required int entregadasHoy,
    required List<Guia> recibidos,
  }) {
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

    final Widget contenido;
    if (sinPendientes) {
      contenido = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _TodoEntregado(
            entregadasHoy: entregadasHoy,
            onNuevaGuia: _nuevaGuia,
            onDespachoCorte: _despachoCorte,
          ),
        ),
      );
    } else if (guias.isEmpty) {
      contenido = Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Text(
          _busqueda.text.trim().isNotEmpty
              ? 'Ninguna guía coincide con “${_busqueda.text.trim()}”.'
              : 'Todavía no entregas ninguna guía hoy.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Ipesa.textoSuave, fontSize: 15),
        ),
      );
    } else {
      // En pendientes, las de un Despacho Corte van juntas en una tarjeta.
      final cortes = _verEntregadas
          ? const <String, List<Guia>>{}
          : agruparPorCorte(guias);
      final sueltas = _verEntregadas
          ? guias
          : guias.where((g) => !g.enDespachoCorte).toList();
      contenido = LayoutBuilder(
        builder: (context, c) {
          // Una columna en celular; 2 o 3 en pantallas anchas.
          final columnas = c.maxWidth >= 1100
              ? 3
              : c.maxWidth >= 720
              ? 2
              : 1;
          const espacio = 14.0;
          final ancho = (c.maxWidth - espacio * (columnas - 1)) / columnas;
          return Wrap(
            spacing: espacio,
            runSpacing: espacio,
            children: [
              for (final e in cortes.entries)
                SizedBox(
                  width: ancho,
                  child: TarjetaDespachoCorte(
                    key: ValueKey(e.key),
                    codigo: e.key,
                    guias: e.value,
                  ),
                ),
              for (final g in sueltas)
                SizedBox(
                  width: ancho,
                  child: _TarjetaTarea(guia: g, entregada: _verEntregadas),
                ),
            ],
          );
        },
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().cargarGuias(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
        children: [
          // Lo que otro transportista le quiere pasar va primero.
          if (recibidos.isNotEmpty) ...[
            Text(
              recibidos.length == 1
                  ? 'Te pasaron 1 tarea'
                  : 'Te pasaron ${recibidos.length} tareas',
              style: Ipesa.titulo(15, color: Ipesa.texto),
            ),
            const SizedBox(height: 10),
            for (final g in recibidos) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: TarjetaTransbordoRecibido(guia: g),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 6),
          ],
          if (!sinPendientes) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: _buscador(),
              ),
            ),
            const SizedBox(height: 14),
          ],
          contenido,
        ],
      ),
    );
  }
}

/// Menú lateral del transportista (se abre con ☰ en la cabecera): las
/// opciones que no son del día a día, para que no quiten espacio a la
/// lista de tareas.
class _MenuTransportista extends StatelessWidget {
  const _MenuTransportista({
    required this.nombre,
    required this.onDespachoCorte,
    required this.onEntregaConIA,
    required this.onCerrarSesion,
  });

  final String nombre;
  final VoidCallback onDespachoCorte;
  final VoidCallback onEntregaConIA;
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
      String titulo,
      String detalle,
      VoidCallback onTap, {
      bool chispa = false,
    }) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: SizedBox(
        width: 42,
        height: 42,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Ipesa.menta,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icono, color: Ipesa.petroleo),
            ),
            // La chispa marca la opción "inteligente".
            if (chispa)
              Positioned(
                right: -5,
                top: -5,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Ipesa.turquesa,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
      title: Text(titulo, style: Ipesa.titulo(16, color: Ipesa.texto)),
      subtitle: Text(
        detalle,
        style: const TextStyle(fontSize: 13, color: Ipesa.textoSuave),
      ),
      onTap: cerrarY(onTap),
    );

    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Ipesa.petroleo,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_shipping_rounded,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Ipesa.titulo(18, color: Colors.white),
                          ),
                          const Text(
                            'Transportista',
                            style: TextStyle(
                              fontSize: 13,
                              color: Ipesa.suaveSobrePetroleo,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: MarcaRpa(tamano: 40, conEslogan: true),
          ),
          const SizedBox(height: 8),
          opcion(
            Icons.inventory_2_outlined,
            'Despacho Corte',
            'Varias guías que salen y llegan juntas',
            onDespachoCorte,
          ),
          opcion(
            Icons.smart_toy_outlined,
            'Entrega inteligente',
            'Entrega varias tareas con sus fotos',
            onEntregaConIA,
            chispa: true,
          ),
          const Spacer(),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(Icons.logout, color: Ipesa.textoSuave),
              title: const Text('Cerrar sesión'),
              onTap: cerrarY(onCerrarSesion),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cabecera petróleo: saludo, cerrar sesión y el resumen del día.
class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.saludo,
    required this.nombre,
    required this.pendientes,
    required this.entregadas,
    required this.avance,
    required this.onMenu,
    required this.onCerrarSesion,
  });

  final VoidCallback onMenu;
  final String saludo;
  final String nombre;
  final int pendientes;
  final int entregadas;
  final int avance;
  final VoidCallback onCerrarSesion;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final iniciales = nombre
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    Widget cifra(String valor, String etiqueta, {bool linea = true}) =>
        Expanded(
          child: Container(
            padding: EdgeInsets.only(left: linea ? 14 : 0),
            decoration: linea
                ? const BoxDecoration(
                    border: Border(left: BorderSide(color: Color(0x33FFFFFF))),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(valor, style: Ipesa.titulo(26, color: Colors.white)),
                Text(
                  etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Ipesa.suaveSobrePetroleo,
                  ),
                ),
              ],
            ),
          ),
        );

    return Container(
      color: Ipesa.petroleo,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Menú',
                    onPressed: onMenu,
                    style: IconButton.styleFrom(
                      fixedSize: const Size(44, 44),
                      backgroundColor: const Color(0x1FFFFFFF),
                    ),
                    icon: const Icon(
                      Icons.menu_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Text(iniciales, style: Ipesa.titulo(15)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          saludo,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Ipesa.suaveSobrePetroleo,
                          ),
                        ),
                        Text(
                          nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Ipesa.titulo(19, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  // El logo de RPA; con espacio, también el nombre y el
                  // eslogan.
                  Padding(
                    padding: const EdgeInsets.only(left: 8, right: 10),
                    child: MarcaRpa(
                      tamano: 38,
                      claro: true,
                      conNombre: ancho >= 700,
                      conEslogan: ancho >= 900,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar sesión',
                    onPressed: onCerrarSesion,
                    style: IconButton.styleFrom(
                      fixedSize: const Size(44, 44),
                      side: const BorderSide(color: Color(0x59FFFFFF)),
                    ),
                    icon: const Icon(
                      Icons.logout,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // En pantallas anchas las cifras no se estiran de lado a lado.
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Row(
                    children: [
                      cifra('$pendientes', 'pendientes', linea: false),
                      cifra('$entregadas', 'entregadas hoy'),
                      cifra('$avance%', 'del día'),
                    ],
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

/// Pestañas subrayadas: Pendientes / Entregadas hoy.
class _Pestanas extends StatelessWidget {
  const _Pestanas({
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
    Widget pestana(String texto, bool activa, bool valor) => Semantics(
      selected: activa,
      button: true,
      child: InkWell(
        onTap: () => onCambio(valor),
        child: Container(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 11),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: activa ? Ipesa.petroleo : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: activa ? FontWeight.w700 : FontWeight.w600,
              color: activa ? Ipesa.petroleo : Ipesa.textoSuave,
            ),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFDEE5E3))),
      ),
      child: Row(
        children: [
          Flexible(child: pestana(izquierda, !derechaActiva, false)),
          const SizedBox(width: 24),
          Flexible(child: pestana(derecha, derechaActiva, true)),
        ],
      ),
    );
  }
}

/// Sin tareas pendientes: la carretera llega al atardecer con la bandera
/// de meta, y debajo el mensaje de ruta completada.
class _TodoEntregado extends StatelessWidget {
  const _TodoEntregado({
    required this.entregadasHoy,
    required this.onNuevaGuia,
    required this.onDespachoCorte,
  });

  final int entregadasHoy;
  final VoidCallback onNuevaGuia;
  final VoidCallback onDespachoCorte;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEBDCC8)),
        borderRadius: BorderRadius.circular(22),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AspectRatio(
            aspectRatio: 390 / 300,
            child: CustomPaint(painter: _Atardecer()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RUTA COMPLETADA',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Color(0xFF1D6B41),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'No tienes más tareas pendientes',
                  style: Ipesa.titulo(26).copyWith(height: 1.15),
                ),
                const SizedBox(height: 8),
                Text(
                  entregadasHoy == 0
                      ? 'Si te asignan otra, aparecerá aquí.'
                      : entregadasHoy == 1
                      ? 'Entregaste 1 guía hoy. Si te asignan otra, '
                            'aparecerá aquí.'
                      : 'Entregaste $entregadasHoy guías hoy. Si te asignan '
                            'otra, aparecerá aquí.',
                  style: const TextStyle(fontSize: 15, color: Ipesa.textoSuave),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: onNuevaGuia,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Nueva guía'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: onDespachoCorte,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Despacho Corte'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cielo cálido, sol, cerros y la carretera hacia la bandera de meta.
/// Dibujado en un lienzo de 390×300 que se escala al ancho disponible.
class _Atardecer extends CustomPainter {
  const _Atardecer();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 390, size.height / 300);
    Paint p(int color) => Paint()..color = Color(color);

    canvas.drawRect(const Rect.fromLTWH(0, 0, 390, 300), p(0xFFFBE3C4));
    canvas.drawCircle(const Offset(195, 140), 86, p(0xFFF6B566));
    canvas.drawCircle(const Offset(195, 140), 60, p(0xFFF59E4A));

    canvas.drawPath(
      Path()
        ..moveTo(-10, 190)
        ..lineTo(60, 120)
        ..lineTo(120, 162)
        ..lineTo(190, 90)
        ..lineTo(260, 158)
        ..lineTo(320, 116)
        ..lineTo(400, 190)
        ..close(),
      p(0xFFE7B48B),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-10, 208)
        ..quadraticBezierTo(60, 170, 130, 194)
        ..quadraticBezierTo(200, 172, 270, 202)
        ..quadraticBezierTo(330, 182, 400, 206)
        ..lineTo(400, 300)
        ..lineTo(-10, 300)
        ..close(),
      p(0xFFC98E6A),
    );

    // La carretera se angosta hacia el horizonte.
    canvas.drawPath(
      Path()
        ..moveTo(150, 300)
        ..lineTo(186, 208)
        ..lineTo(204, 208)
        ..lineTo(240, 300)
        ..close(),
      p(0xFF2B2F33),
    );
    final linea = p(0xE6FFFFFF);
    for (final (y1, y2, a1, a2) in [
      (220.0, 236.0, 1.0, 1.6),
      (252.0, 272.0, 2.0, 3.0),
      (286.0, 300.0, 3.2, 4.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(195 - a1, y1)
          ..lineTo(195 + a1, y1)
          ..lineTo(195 + a2, y2)
          ..lineTo(195 - a2, y2)
          ..close(),
        linea,
      );
    }

    // Bandera de meta.
    canvas.drawLine(
      const Offset(212, 196),
      const Offset(212, 152),
      Paint()
        ..color = Ipesa.petroleo
        ..strokeWidth = 3,
    );
    canvas.drawPath(
      Path()
        ..moveTo(212, 152)
        ..lineTo(238, 161)
        ..lineTo(212, 170)
        ..close(),
      p(0xFF1D6B41),
    );
  }

  @override
  bool shouldRepaint(_Atardecer oldDelegate) => false;
}

/// Qué hace el botón principal según el tipo y el estado de la guía.
String? _siguientePaso(Guia g) {
  if (g.estado.esCerrada) return null;
  if (g.tipoEntrega == TipoEntrega.entreSucursales) {
    return switch (g.estado) {
      EstadoGuia.enRuta => 'Iniciar traslado',
      EstadoGuia.enProcesoTrasbordo => 'Registrar llegada',
      _ => 'Confirmar recepción',
    };
  }
  return 'Entregar';
}

class _TarjetaTarea extends StatelessWidget {
  const _TarjetaTarea({required this.guia, required this.entregada});

  final Guia guia;
  final bool entregada;

  void _abrirDetalle(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => GuiaDetailScreen(
        numeroGuia: guia.numeroGuia,
        fechaCreacion: guia.fechaCreacion,
      ),
    ),
  );

  Future<void> _opcion(BuildContext context, _Opcion opcion) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (opcion) {
      case _Opcion.transbordo:
        if (await mostrarTransbordo(context, guia)) {
          final actual = context.mounted
              ? context.read<AppState>().guiaActual(guia)
              : null;
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Transbordo enviado a ${actual?.transbordoA ?? 'otro transportista'}'
                '. Sigue siendo tuya hasta que la acepte.',
              ),
            ),
          );
        }
      case _Opcion.cancelarTransbordo:
        try {
          await context.read<AppState>().cancelarTransbordo(guia);
          messenger.showSnackBar(
            const SnackBar(content: Text('Cancelaste el transbordo.')),
          );
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(content: Text('No se pudo cancelar: $e')),
          );
        }
      case _Opcion.rechazar:
        if (await mostrarRechazo(context, guia)) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Guía ${guia.numeroGuia} rechazada. Se avisó al administrador.',
              ),
            ),
          );
        }
      case _Opcion.eliminar:
        if (await mostrarPedidoEliminacion(context, guia)) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Pedido enviado. El administrador debe aprobarlo.'),
            ),
          );
        }
      case _Opcion.retirar:
        try {
          await context.read<AppState>().retirarPedidoEliminacion(guia);
          messenger.showSnackBar(
            const SnackBar(content: Text('Retiraste el pedido de eliminar.')),
          );
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(content: Text('No se pudo retirar: $e')),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = guia;
    final paso = entregada ? null : _siguientePaso(g);
    final sucursal = g.tipoEntrega == TipoEntrega.entreSucursales
        ? context.read<AppState>().sucursalPorNombre(g.destino)
        : null;
    final hora = DateFormat('HH:mm');
    final meta = [
      g.tipoEntrega.etiqueta,
      if (g.origen.trim().isNotEmpty) 'Sale de ${g.origen.trim()}',
      hora.format(g.fechaCreacion.toLocal()),
    ].join(' · ');

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFDEE5E3)),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirDetalle(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(g.numeroGuia, style: Ipesa.titulo(16))),
                  EstadoBadge(estado: g.estado),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                g.destinatario,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.location_on_outlined,
                      size: 17,
                      color: Ipesa.turquesa,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      g.destino,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Ipesa.etiqueta,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                entregada
                    ? [
                        'Entregada',
                        if (context.read<AppState>().sucursalPorNombre(
                              g.destino,
                            ) !=
                            null)
                          'en ${g.destino}',
                        'a las ${hora.format(g.fechaActualizacion.toLocal())}',
                      ].join(' ')
                    : meta,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: entregada ? FontWeight.w700 : FontWeight.w400,
                  color: entregada ? g.estado.color : Ipesa.textoSuave,
                ),
              ),
              if (g.estado == EstadoGuia.enProcesoTrasbordo)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.my_location,
                        size: 16,
                        color: Ipesa.petroleo,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          sucursal == null
                              ? 'La sucursal aún no tiene perímetro marcado.'
                              : 'Registra la llegada dentro de '
                                    '${sucursal.radioM.round()} m de la sucursal',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Ipesa.petroleo,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!entregada &&
                  AvisoTransbordo.hayQueMostrar(
                    g,
                    context.read<AppState>().transportistaActual,
                  ))
                AvisoTransbordo(guia: g),
              if (g.eliminacionPendiente || g.eliminacionRechazada)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(
                        g.eliminacionPendiente
                            ? Icons.hourglass_top_rounded
                            : Icons.do_not_disturb_on,
                        size: 16,
                        color: g.eliminacionPendiente
                            ? const Color(0xFF8A4F00)
                            : const Color(0xFFB42318),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          g.eliminacionPendiente
                              ? 'Pediste eliminarla · esperando al administrador'
                              : 'El administrador no aprobó eliminarla',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: g.eliminacionPendiente
                                ? const Color(0xFF8A4F00)
                                : const Color(0xFFB42318),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (paso != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 20),
                        label: Text(paso),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                EntregaFlowScreen(guia: g, desdeDetalle: false),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<_Opcion>(
                      tooltip: 'Más opciones',
                      color: Colors.white,
                      position: PopupMenuPosition.under,
                      onSelected: (o) => _opcion(context, o),
                      itemBuilder: (_) => [
                        if (g.esEditablePorTransportista)
                          PopupMenuItem(
                            value: g.transbordoPendiente
                                ? _Opcion.cancelarTransbordo
                                : _Opcion.transbordo,
                            child: ListTile(
                              leading: const Icon(Icons.swap_horiz_rounded),
                              title: Text(
                                g.transbordoPendiente
                                    ? 'Cancelar transbordo'
                                    : 'Transbordo',
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        const PopupMenuItem(
                          value: _Opcion.rechazar,
                          child: ListTile(
                            leading: Icon(Icons.block),
                            title: Text('Rechazar tarea'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        if (g.esEditablePorTransportista)
                          PopupMenuItem(
                            value: g.eliminacionPendiente
                                ? _Opcion.retirar
                                : _Opcion.eliminar,
                            child: ListTile(
                              leading: const Icon(
                                Icons.delete_outline,
                                color: Color(0xFFB42318),
                              ),
                              title: Text(
                                g.eliminacionPendiente
                                    ? 'Retirar pedido de eliminar'
                                    : 'Eliminar tarea',
                                style: const TextStyle(
                                  color: Color(0xFFB42318),
                                ),
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                      ],
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          border: Border.all(color: Ipesa.borde),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.more_horiz,
                          color: Ipesa.petroleo,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _Opcion { transbordo, cancelarTransbordo, rechazar, eliminar, retirar }
