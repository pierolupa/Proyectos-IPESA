import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../models/tipo_entrega.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/escena_ruta.dart';
import '../../widgets/foto_entrega.dart';
import '../../widgets/lugares_sucursal.dart';
import '../../widgets/seccion_ubicacion.dart';

final _fechaHora = DateFormat('dd/MM/yyyy HH:mm');
final _fechaSello = DateFormat('dd/MM/yyyy · HH:mm');

/// La guía que buscó el comercial, "de frente": una guía de remisión IPESA
/// que se imprime sobre el paisaje (con el camión abajo) y un sello con el
/// estado. Solo lectura; se actualiza sola.
class RastreoDetalleScreen extends StatelessWidget {
  const RastreoDetalleScreen({
    super.key,
    required this.numeroGuia,
    this.fechaCreacion,
  });

  final String numeroGuia;

  /// Cuál de las tareas con ese número (la misma guía puede registrarse de
  /// nuevo tras un rechazo).
  final DateTime? fechaCreacion;

  @override
  Widget build(BuildContext context) {
    final guia = context.watch<AppState>().buscarPorNumero(
      numeroGuia,
      fechaCreacion: fechaCreacion,
    );
    final ancho = MediaQuery.sizeOf(context).width;
    final altoEscena = ancho < 600 ? 170.0 : 220.0;

    return Scaffold(
      backgroundColor: cieloEscena,
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: EscenaRuta(alto: altoEscena),
                ),
                Padding(
                  // Solo se reserva el suelo del paisaje: el camión
                  // queda siempre a la vista, debajo de la guía.
                  padding: EdgeInsets.only(
                    bottom: math.max(altoEscena - 56, 112),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _BarraSuperior(),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                              child: guia == null
                                  ? const _NoEncontrada()
                                  : _Boleto(guia: guia),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarraSuperior extends StatelessWidget {
  const _BarraSuperior();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          IconButton.filled(
            tooltip: 'Nueva búsqueda',
            onPressed: () => Navigator.of(context).maybePop(),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Ipesa.petroleo,
              fixedSize: const Size(44, 44),
              elevation: 2,
              shadowColor: const Color(0x330F4C5C),
            ),
            icon: const Icon(Icons.chevron_left, size: 26),
          ),
          Expanded(
            child: Text(
              'Tu guía',
              textAlign: TextAlign.center,
              style: Ipesa.titulo(17),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _NoEncontrada extends StatelessWidget {
  const _NoEncontrada();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text(
        'Guía no encontrada.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Ipesa.textoSuave),
      ),
    );
  }
}

/// Lo que dice el sello según el estado de la guía.
(String, String) _textoSello(Guia guia) {
  String fecha(DateTime f) => _fechaSello.format(f.toLocal());
  switch (guia.estado) {
    case EstadoGuia.enRuta:
      return ('EN RUTA', 'Desde ${fecha(guia.fechaActualizacion)}');
    case EstadoGuia.enProcesoTrasbordo:
      return ('EN TRASBORDO', 'Desde ${fecha(guia.fechaActualizacion)}');
    case EstadoGuia.recepcionSucursal:
      return ('EN SUCURSAL', 'Desde ${fecha(guia.fechaActualizacion)}');
    case EstadoGuia.entregado:
    case EstadoGuia.finalizado:
      return ('ENTREGADO', fecha(guia.fechaCierre ?? guia.fechaActualizacion));
    case EstadoGuia.rechazado:
      return ('RECHAZADA', fecha(guia.fechaActualizacion));
  }
}

/// La guía de remisión: cabecera negra IPESA, los datos, un corte de
/// boleto y el sello del estado. Entra "imprimiéndose" y luego cae el
/// sello.
class _Boleto extends StatefulWidget {
  const _Boleto({required this.guia});

  final Guia guia;

  @override
  State<_Boleto> createState() => _BoletoState();
}

class _BoletoState extends State<_Boleto> with SingleTickerProviderStateMixin {
  late final AnimationController _entrada = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  late final Animation<double> _impresion = CurvedAnimation(
    parent: _entrada,
    curve: const Interval(0, 0.6, curve: Cubic(.3, .7, .2, 1)),
  );

  late final Animation<double> _escalaSello = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.8, end: 0.94), weight: 70),
    TweenSequenceItem(tween: Tween(begin: 0.94, end: 1.0), weight: 30),
  ]).animate(CurvedAnimation(parent: _entrada, curve: const Interval(0.55, 1)));

  late final Animation<double> _opacidadSello = CurvedAnimation(
    parent: _entrada,
    curve: const Interval(0.55, 0.75),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entrada.isAnimating || _entrada.isCompleted) return;
    if (MediaQuery.of(context).disableAnimations) {
      _entrada.value = 1;
    } else {
      _entrada.forward();
    }
  }

  @override
  void dispose() {
    _entrada.dispose();
    super.dispose();
  }

  void _verFoto() => _hoja(FotoEntrega(guia: widget.guia));

  void _verUbicacion() {
    final guia = widget.guia;
    _hoja(
      SeccionUbicacion(
        guia: guia,
        perimetro: guia.tipoEntrega == TipoEntrega.entreSucursales
            ? context.read<AppState>().sucursalPorNombre(guia.destino)
            : null,
      ),
    );
  }

  void _hoja(Widget contenido) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: contenido,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final guia = widget.guia;
    final (sello, fechaSello) = _textoSello(guia);
    final recojo = sucursalDeRecojo(context, guia);
    final entrega = sucursalDeEntrega(context, guia);
    final color = guia.estado.color;

    final boleto = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E0F4C5C),
            blurRadius: 48,
            offset: Offset(0, 22),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Image.asset(
                    'assets/brand/ipesa_blanco.png',
                    height: 18,
                    semanticLabel: 'IPESA',
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'GUÍA DE REMISIÓN',
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFFC9CFCD),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 4, color: const Color(0xFF0E7A3A)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Etiqueta('N° de guía'),
                  Text(
                    guia.numeroGuia,
                    style: Ipesa.titulo(30, color: Ipesa.texto),
                  ),
                  const SizedBox(height: 10),
                  const _Etiqueta('Cliente'),
                  Text(
                    guia.destinatario.isEmpty ? '—' : guia.destinatario,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Ipesa.texto,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _Dato('N° pedido', guia.numeroPedido)),
                      const SizedBox(width: 16),
                      Expanded(child: _Dato('N° entrega', guia.numeroEntrega)),
                    ],
                  ),
                  if (guia.tieneComprobanteAgencia) ...[
                    const SizedBox(height: 10),
                    _Dato('Agencia', guia.agenciaRazonSocial),
                    const SizedBox(height: 10),
                    _Dato('N° de comprobante', guia.agenciaComprobante),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _Dato('RUC agencia', guia.agenciaRuc)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _Dato(
                            'Monto pagado',
                            guia.agenciaMonto == null
                                ? ''
                                : 'S/ ${guia.agenciaMonto!.toStringAsFixed(2)}',
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (recojo != null || entrega != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _Dato('Recogida en', recojo ?? '—')),
                        const SizedBox(width: 16),
                        Expanded(child: _Dato('Entregada en', entrega ?? '—')),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _Dato(
                          'Salió',
                          _fechaHora.format(guia.fechaCreacion.toLocal()),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _Dato(
                          'Transportista',
                          guia.transbordoAceptado &&
                                  guia.transbordoDe.isNotEmpty
                              ? '${guia.transportista} (transbordo de '
                                    '${guia.transbordoDe})'
                              : guia.transportista,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const _Corte(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: FadeTransition(
                      opacity: _opacidadSello,
                      child: ScaleTransition(
                        scale: _escalaSello,
                        // Inclinado, sus esquinas salen de su caja: el
                        // margen vertical las deja libres; y si el texto es
                        // largo (EN TRASBORDO) se achica para caber.
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Transform.rotate(
                              angle: -9 * math.pi / 180,
                              child: _Sello(
                                texto: sello,
                                fecha: fechaSello,
                                color: color,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (guia.motivoRechazo.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Motivo: ${guia.motivoRechazo}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: color),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (guia.estado.esFinal) ...[
                        Expanded(
                          child: _BotonBoleto(
                            texto: 'Ver foto',
                            icono: Icons.photo_camera_outlined,
                            onPressed: _verFoto,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: _BotonBoleto(
                          texto: 'Ubicación',
                          icono: Icons.place_outlined,
                          onPressed: _verUbicacion,
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

    // Se "imprime" de arriba hacia abajo mientras baja un poco.
    return AnimatedBuilder(
      animation: _impresion,
      builder: (context, hijo) => Transform.translate(
        offset: Offset(0, -20 * (1 - _impresion.value)),
        child: ClipRect(clipper: _Revelado(_impresion.value), child: hijo),
      ),
      child: boleto,
    );
  }
}

class _Revelado extends CustomClipper<Rect> {
  _Revelado(this.avance);

  final double avance;

  @override
  Rect getClip(Size size) =>
      // Un margen extra para no cortar la sombra al terminar.
      avance >= 1
      ? Rect.fromLTWH(-60, -60, size.width + 120, size.height + 120)
      : Rect.fromLTWH(-60, -60, size.width + 120, 60 + size.height * avance);

  @override
  bool shouldReclip(_Revelado anterior) => anterior.avance != avance;
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Text(
    texto,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Ipesa.textoSuave,
    ),
  );
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor);

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Etiqueta(etiqueta),
      Text(
        valor.isEmpty ? '—' : valor,
        style: const TextStyle(fontSize: 15, color: Ipesa.texto),
      ),
    ],
  );
}

/// El corte del boleto: dos medias lunas del color del fondo y una línea
/// punteada.
class _Corte extends StatelessWidget {
  const _Corte();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            left: 20,
            right: 20,
            child: CustomPaint(painter: _LineaPunteada()),
          ),
          const Positioned(left: -11, top: 0, child: _MediaLuna()),
          const Positioned(right: -11, top: 0, child: _MediaLuna()),
        ],
      ),
    );
  }
}

class _MediaLuna extends StatelessWidget {
  const _MediaLuna();

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: const BoxDecoration(color: cieloEscena, shape: BoxShape.circle),
  );
}

class _LineaPunteada extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pintura = Paint()
      ..color = Ipesa.borde
      ..strokeWidth = 2;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += 10) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + 5, size.width), y),
        pintura,
      );
    }
  }

  @override
  bool shouldRepaint(_LineaPunteada anterior) => false;
}

/// Sello de goma: solo el borde y el texto, sin fondo.
class _Sello extends StatelessWidget {
  const _Sello({required this.texto, required this.fecha, required this.color});

  final String texto;
  final String fecha;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            texto,
            style: TextStyle(
              fontFamily: Ipesa.fuenteTitulos,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
              color: color,
            ),
          ),
          Text(
            fecha,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _BotonBoleto extends StatelessWidget {
  const _BotonBoleto({
    required this.texto,
    required this.icono,
    required this.onPressed,
  });

  final String texto;
  final IconData icono;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: Ipesa.petroleo,
      ),
      icon: Icon(icono, size: 18),
      label: Text(texto, overflow: TextOverflow.ellipsis),
    );
  }
}
