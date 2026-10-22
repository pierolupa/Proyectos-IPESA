import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/guia.dart';
import '../screens/transportista/capture_flow_screen.dart';
import '../screens/transportista/rechazo_sheet.dart';
import '../services/ubicacion.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Las guías en camino agrupadas por Despacho Corte (código → guías), en
/// el orden en que aparecen; las sueltas no van aquí.
Map<String, List<Guia>> agruparPorCorte(Iterable<Guia> guias) {
  final cortes = <String, List<Guia>>{};
  for (final g in guias) {
    if (g.enDespachoCorte) cortes.putIfAbsent(g.despachoCorte, () => []).add(g);
  }
  return cortes;
}

enum _OpcionGuiaCorte { quitar, rechazar }

/// Un Despacho Corte en camino: sus guías y el botón para marcar la
/// llegada de todas a la vez (sin foto, con GPS).
class TarjetaDespachoCorte extends StatefulWidget {
  const TarjetaDespachoCorte({
    super.key,
    required this.codigo,
    required this.guias,
  });

  final String codigo;
  final List<Guia> guias;

  @override
  State<TarjetaDespachoCorte> createState() => _TarjetaDespachoCorteState();
}

class _TarjetaDespachoCorteState extends State<TarjetaDespachoCorte> {
  bool _abierta = false;
  bool _llegando = false;

  DateTime get _salida => widget.guias
      .map((g) => g.fechaCreacion)
      .reduce((a, b) => a.isBefore(b) ? a : b)
      .toLocal();

  Future<void> _llegada() async {
    final n = widget.guias.length;
    final confirma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Llegó el despacho?'),
        content: Text(
          n == 1
              ? 'La guía de ${widget.codigo} quedará entregada con la hora '
                    'y la ubicación de ahora.'
              : 'Las $n guías de ${widget.codigo} quedarán entregadas a la '
                    'vez, con la hora y la ubicación de ahora.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sí, llegó'),
          ),
        ],
      ),
    );
    if (confirma != true || !mounted) return;
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _llegando = true);
    try {
      Position? posicion;
      try {
        posicion = await Ubicacion.actual();
      } catch (_) {
        posicion = Ubicacion.reciente;
      }
      if (posicion == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo leer tu ubicación: activa el GPS e inténtalo de nuevo.',
            ),
          ),
        );
        return;
      }
      final entregadas = await appState.llegadaDespachoCorte(
        widget.codigo,
        lat: posicion.latitude,
        lng: posicion.longitude,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Despacho ${widget.codigo} entregado · '
            '${entregadas == 1 ? '1 guía' : '$entregadas guías'}',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo registrar la llegada: $e')),
      );
    } finally {
      if (mounted) setState(() => _llegando = false);
    }
  }

  Future<void> _opcion(Guia guia, _OpcionGuiaCorte opcion) async {
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    switch (opcion) {
      case _OpcionGuiaCorte.quitar:
        try {
          await appState.quitarDeDespachoCorte(guia);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                '${guia.numeroGuia} salió del despacho: queda como tarea suelta.',
              ),
            ),
          );
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(content: Text('No se pudo quitar: $e')),
          );
        }
      case _OpcionGuiaCorte.rechazar:
        if (await mostrarRechazo(context, guia)) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Guía ${guia.numeroGuia} rechazada. Se avisó al administrador.',
              ),
            ),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final guias = widget.guias;
    final n = guias.length;
    final visibles = _abierta ? guias : guias.take(3).toList();
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Ipesa.mentaBorde, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Ipesa.menta,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_rounded, color: Ipesa.petroleo),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Despacho Corte',
                        style: Ipesa.titulo(16, color: Ipesa.petroleo),
                      ),
                      Text(
                        '${widget.codigo} · ${n == 1 ? '1 guía' : '$n guías'}'
                        ' · salió ${DateFormat('HH:mm').format(_salida)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Ipesa.etiqueta,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final g in visibles)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.numeroGuia, style: Ipesa.titulo(14.5)),
                        Text(
                          g.destinatario,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Ipesa.textoSuave,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_OpcionGuiaCorte>(
                    tooltip: 'Opciones de ${g.numeroGuia}',
                    enabled: !_llegando,
                    onSelected: (o) => _opcion(g, o),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _OpcionGuiaCorte.quitar,
                        child: ListTile(
                          leading: Icon(Icons.call_split_rounded),
                          title: Text('Quitar del despacho'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: _OpcionGuiaCorte.rechazar,
                        child: ListTile(
                          leading: Icon(Icons.block),
                          title: Text('Rechazar'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Row(
            children: [
              if (n > 3)
                TextButton(
                  onPressed: () => setState(() => _abierta = !_abierta),
                  child: Text(_abierta ? 'Ver menos' : 'Ver las $n guías'),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: _llegando
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CaptureFlowScreen(
                            despachoCorte: true,
                            codigoCorte: widget.codigo,
                          ),
                        ),
                      ),
                icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: const Text('Agregar guías'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: const Color(0xFF1D6B41),
              ),
              onPressed: _llegando ? null : _llegada,
              icon: _llegando
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.flag_rounded),
              label: Text(
                _llegando
                    ? 'Registrando llegada…'
                    : n == 1
                    ? 'Llegó · entregar 1 guía'
                    : 'Llegó · entregar $n guías',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
