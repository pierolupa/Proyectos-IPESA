import 'package:flutter/material.dart';

import '../models/estado_guia.dart';
import '../models/guia.dart';
import '../models/tipo_entrega.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Cómo se presenta una novedad: título corto, detalle, ícono y color.
extension PresentacionNovedad on CambioGuia {
  String get titulo {
    if (nueva) return 'Nueva guía registrada';
    return switch (guia.estado) {
      EstadoGuia.enRuta => 'Guía de vuelta en ruta',
      EstadoGuia.enProcesoTrasbordo => 'Traslado iniciado',
      EstadoGuia.recepcionSucursal => 'Llegó a la sucursal',
      EstadoGuia.entregado => 'Guía entregada',
      EstadoGuia.finalizado => 'Entregada en agencia',
      EstadoGuia.rechazado => 'Guía rechazada',
    };
  }

  /// Lo que pasó, en una línea: quién y a dónde / por qué.
  String get detalle {
    final quien = guia.transportista.trim().isEmpty
        ? 'Sin transportista'
        : guia.transportista.trim();
    if (nueva) return '$quien · ${guia.tipoEntrega.etiqueta}';
    return switch (guia.estado) {
      EstadoGuia.enProcesoTrasbordo ||
      EstadoGuia.recepcionSucursal => '$quien · ${guia.destino}',
      EstadoGuia.rechazado when guia.motivoRechazo.trim().isNotEmpty =>
        '$quien · ${guia.motivoRechazo.trim()}',
      _ when guia.destinatario.trim().isNotEmpty =>
        '$quien · ${guia.destinatario.trim()}',
      _ => quien,
    };
  }

  IconData get icono {
    if (nueva) return Icons.post_add_rounded;
    return switch (guia.estado) {
      EstadoGuia.enRuta => Icons.local_shipping_outlined,
      EstadoGuia.enProcesoTrasbordo => Icons.swap_horiz_rounded,
      EstadoGuia.recepcionSucursal => Icons.warehouse_outlined,
      EstadoGuia.entregado || EstadoGuia.finalizado => Icons.task_alt_rounded,
      EstadoGuia.rechazado => Icons.block_rounded,
    };
  }

  Color get color => nueva ? Ipesa.turquesa : guia.estado.color;
}

String _hace(DateTime momento, DateTime ahora) {
  final d = ahora.difference(momento);
  if (d.inSeconds < 60) return 'ahora';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  return d.inDays == 1 ? 'hace 1 día' : 'hace ${d.inDays} días';
}

/// Novedades de la sesión: el historial (para la campana) y los avisos que
/// están a la vista en pantalla.
class CentroNovedades extends ChangeNotifier {
  static const _maxHistorial = 60;

  /// Cuántos avisos se muestran a la vez; el resto se resume.
  static const maxAvisos = 3;

  final List<CambioGuia> historial = [];
  final List<AvisoEnPantalla> avisos = [];
  int noLeidas = 0;
  int _siguienteId = 0;

  void agregar(List<CambioGuia> cambios) {
    if (cambios.isEmpty) return;
    historial.insertAll(0, cambios);
    if (historial.length > _maxHistorial) {
      historial.removeRange(_maxHistorial, historial.length);
    }
    noLeidas += cambios.length;
    avisos.clear();
    if (cambios.length <= maxAvisos) {
      for (final c in cambios) {
        avisos.add(AvisoEnPantalla(_siguienteId++, c));
      }
    } else {
      for (final c in cambios.take(maxAvisos - 1)) {
        avisos.add(AvisoEnPantalla(_siguienteId++, c));
      }
      avisos.add(
        AvisoEnPantalla(
          _siguienteId++,
          null,
          resumidas: cambios.length - (maxAvisos - 1),
        ),
      );
    }
    notifyListeners();
  }

  void descartar(int id) {
    avisos.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  void marcarLeidas() {
    if (noLeidas == 0 && avisos.isEmpty) return;
    noLeidas = 0;
    avisos.clear();
    notifyListeners();
  }
}

class AvisoEnPantalla {
  AvisoEnPantalla(this.id, this.cambio, {this.resumidas = 0});
  final int id;

  /// null: tarjeta que resume [resumidas] novedades más.
  final CambioGuia? cambio;
  final int resumidas;
}

/// Pone los avisos arriba a la derecha (arriba y a todo el ancho en
/// celular), encima de [child].
class CapaAvisos extends StatelessWidget {
  const CapaAvisos({
    super.key,
    required this.centro,
    required this.onAbrirGuia,
    required this.onVerTodas,
    required this.child,
  });

  final CentroNovedades centro;
  final void Function(Guia guia) onAbrirGuia;
  final VoidCallback onVerTodas;
  final Widget child;

  static const duracion = Duration(seconds: 7);

  @override
  Widget build(BuildContext context) {
    final angosta = MediaQuery.sizeOf(context).width < 600;
    final arriba = MediaQuery.paddingOf(context).top + (angosta ? 8 : 20);
    return Stack(
      children: [
        child,
        Positioned(
          top: arriba,
          right: angosta ? 12 : 24,
          left: angosta ? 12 : null,
          child: ListenableBuilder(
            listenable: centro,
            builder: (context, _) => SizedBox(
              width: angosta ? null : 390,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final a in centro.avisos)
                    Padding(
                      key: ValueKey(a.id),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TarjetaAviso(
                        aviso: a,
                        onCerrar: () => centro.descartar(a.id),
                        onAbrir: a.cambio == null
                            ? onVerTodas
                            : () {
                                centro.descartar(a.id);
                                onAbrirGuia(a.cambio!.guia);
                              },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Un aviso: entra deslizándose, se va solo con una barra de tiempo (que se
/// detiene con el mouse encima) y se puede cerrar o abrir.
class _TarjetaAviso extends StatefulWidget {
  const _TarjetaAviso({
    required this.aviso,
    required this.onCerrar,
    required this.onAbrir,
  });

  final AvisoEnPantalla aviso;
  final VoidCallback onCerrar;
  final VoidCallback onAbrir;

  @override
  State<_TarjetaAviso> createState() => _TarjetaAvisoState();
}

class _TarjetaAvisoState extends State<_TarjetaAviso>
    with TickerProviderStateMixin {
  late final _entrada = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();
  late final _tiempo = AnimationController(
    vsync: this,
    duration: CapaAvisos.duracion,
  );
  bool _cerrando = false;

  @override
  void initState() {
    super.initState();
    _tiempo
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _cerrar();
      })
      ..forward();
  }

  Future<void> _cerrar() async {
    if (_cerrando) return;
    _cerrando = true;
    await _entrada.reverse();
    if (mounted) widget.onCerrar();
  }

  @override
  void dispose() {
    _entrada.dispose();
    _tiempo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.aviso.cambio;
    final color = c?.color ?? Ipesa.petroleo;
    final curva = CurvedAnimation(
      parent: _entrada,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curva,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0.25, 0),
          end: Offset.zero,
        ).animate(curva),
        child: MouseRegion(
          onEnter: (_) => _tiempo.stop(),
          onExit: (_) {
            if (!_cerrando) _tiempo.forward();
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE1E6E4)),
              borderRadius: BorderRadius.circular(14),
              boxShadow: _sombra,
            ),
            child: Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: widget.onAbrir,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 6, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _IconoNovedad(
                            icono: c?.icono ?? Icons.notifications_rounded,
                            color: color,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: c == null
                                ? _ContenidoResumen(
                                    cantidad: widget.aviso.resumidas,
                                  )
                                : _ContenidoCambio(cambio: c),
                          ),
                          IconButton(
                            tooltip: 'Cerrar aviso',
                            visualDensity: VisualDensity.compact,
                            onPressed: _cerrar,
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Ipesa.textoSuave,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _tiempo,
                    builder: (_, _) => Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: 1 - _tiempo.value,
                        child: Container(
                          height: 3,
                          color: color.withValues(alpha: 0.7),
                        ),
                      ),
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
}

const _sombra = [
  BoxShadow(color: Color(0x1A0F2E36), blurRadius: 28, offset: Offset(0, 12)),
];

class _IconoNovedad extends StatelessWidget {
  const _IconoNovedad({required this.icono, required this.color});

  final IconData icono;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Icon(icono, color: color, size: 21),
    );
  }
}

class _ContenidoCambio extends StatelessWidget {
  const _ContenidoCambio({required this.cambio});

  final CambioGuia cambio;

  @override
  Widget build(BuildContext context) {
    final c = cambio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                c.titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Ipesa.titulo(15, color: Ipesa.texto),
              ),
            ),
            const Text(
              'ahora',
              style: TextStyle(fontSize: 12, color: Ipesa.textoSuave),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          c.guia.numeroGuia,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          c.detalle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, color: Ipesa.etiqueta),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ver guía →',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Ipesa.petroleo,
          ),
        ),
      ],
    );
  }
}

class _ContenidoResumen extends StatelessWidget {
  const _ContenidoResumen({required this.cantidad});

  final int cantidad;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cantidad == 1 ? '1 novedad más' : '$cantidad novedades más',
          style: Ipesa.titulo(15, color: Ipesa.texto),
        ),
        const SizedBox(height: 2),
        const Text(
          'Llegaron varias a la vez.',
          style: TextStyle(fontSize: 14, color: Ipesa.etiqueta),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ver todas →',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Ipesa.petroleo,
          ),
        ),
      ],
    );
  }
}

/// Campana con el número de novedades sin leer; abre el panel.
class BotonNovedades extends StatelessWidget {
  const BotonNovedades({
    super.key,
    required this.centro,
    required this.onPressed,
    this.tamano = 44,
  });

  final CentroNovedades centro;
  final VoidCallback onPressed;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: centro,
      builder: (context, _) {
        final n = centro.noLeidas;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: n == 0
                  ? 'Novedades'
                  : n == 1
                  ? '1 novedad sin leer'
                  : '$n novedades sin leer',
              onPressed: onPressed,
              style: IconButton.styleFrom(
                fixedSize: Size.square(tamano),
                backgroundColor: Colors.white,
                side: const BorderSide(color: Ipesa.borde),
              ),
              icon: Icon(
                n == 0
                    ? Icons.notifications_none_rounded
                    : Icons.notifications_active_rounded,
                color: Ipesa.petroleo,
                size: 20,
              ),
            ),
            if (n > 0)
              Positioned(
                right: 2,
                top: 2,
                child: IgnorePointer(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB42318),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text(
                      n > 99 ? '99+' : '$n',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Abre el historial de novedades: un panel arriba a la derecha en
/// computadora, una hoja desde abajo en celular. Al abrirlo quedan leídas.
Future<void> mostrarPanelNovedades(
  BuildContext context, {
  required CentroNovedades centro,
  required void Function(Guia guia) onAbrirGuia,
  required bool avisosDelNavegador,
  required VoidCallback? onActivarNavegador,
}) {
  final angosta = MediaQuery.sizeOf(context).width < 600;
  final noLeidas = centro.noLeidas;
  centro.marcarLeidas();
  Widget panel(BuildContext ctx) => _PanelNovedades(
    centro: centro,
    resaltar: noLeidas,
    avisosDelNavegador: avisosDelNavegador,
    onActivarNavegador: onActivarNavegador == null
        ? null
        : () {
            Navigator.of(ctx).pop();
            onActivarNavegador();
          },
    onAbrirGuia: (g) {
      Navigator.of(ctx).pop();
      onAbrirGuia(g);
    },
  );
  if (angosta) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.8,
        ),
        child: panel(ctx),
      ),
    );
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar novedades',
    barrierColor: const Color(0x140F2E36),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, _) => SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 76, right: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE1E6E4)),
              borderRadius: BorderRadius.circular(16),
              boxShadow: _sombra,
            ),
            child: Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 420,
                  maxHeight: 580,
                ),
                child: panel(ctx),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, animacion, _, hijo) => FadeTransition(
      opacity: animacion,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, -0.02),
          end: Offset.zero,
        ).animate(animacion),
        child: hijo,
      ),
    ),
  );
}

class _PanelNovedades extends StatelessWidget {
  const _PanelNovedades({
    required this.centro,
    required this.resaltar,
    required this.avisosDelNavegador,
    required this.onActivarNavegador,
    required this.onAbrirGuia,
  });

  final CentroNovedades centro;

  /// Las primeras [resaltar] eran nuevas al abrir el panel.
  final int resaltar;
  final bool avisosDelNavegador;
  final VoidCallback? onActivarNavegador;
  final void Function(Guia guia) onAbrirGuia;

  @override
  Widget build(BuildContext context) {
    final lista = centro.historial;
    final ahora = DateTime.now();
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Novedades',
                    style: Ipesa.titulo(19, color: Ipesa.texto),
                  ),
                ),
                if (resaltar > 0)
                  Text(
                    resaltar == 1 ? '1 nueva' : '$resaltar nuevas',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB42318),
                    ),
                  ),
              ],
            ),
          ),
          if (!avisosDelNavegador)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                color: Ipesa.fondo,
                border: Border.all(color: const Color(0xFFE1E6E4)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.desktop_windows_outlined,
                    size: 20,
                    color: Ipesa.petroleo,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Recibe los avisos aunque estés en otra pestaña.',
                      style: TextStyle(fontSize: 13.5, color: Ipesa.etiqueta),
                    ),
                  ),
                  TextButton(
                    onPressed: onActivarNavegador,
                    child: const Text('Activar'),
                  ),
                ],
              ),
            ),
          const Divider(height: 1, color: Color(0xFFE9EDEC)),
          if (lista.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(32, 40, 32, 44),
              child: Column(
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 36,
                    color: Ipesa.mentaBorde,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Sin novedades por ahora',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Ipesa.texto,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Aquí verás cada guía que se registre, entregue o '
                    'rechace mientras tengas el panel abierto.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: Ipesa.textoSuave),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: lista.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  indent: 72,
                  color: Color(0xFFF0F3F2),
                ),
                itemBuilder: (_, i) {
                  final c = lista[i];
                  return InkWell(
                    onTap: () => onAbrirGuia(c.guia),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _IconoNovedad(icono: c.icono, color: c.color),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.titulo,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: i < resaltar
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: Ipesa.texto,
                                  ),
                                ),
                                Text(
                                  '${c.guia.numeroGuia} · ${c.detalle}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    color: Ipesa.textoSuave,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _hace(c.momento, ahora),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Ipesa.textoSuave,
                                ),
                              ),
                              if (i < resaltar) ...[
                                const SizedBox(height: 6),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFFB42318),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
