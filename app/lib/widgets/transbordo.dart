import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/guia.dart';
import '../services/guias_api.dart';
import '../state/app_state.dart';
import '../theme.dart';

const _azul = Color(0xFF2459A8);
const _rojo = Color(0xFFB42318);

String _error(Object e) =>
    e is ApiException ? e.mensaje : 'Error de conexión: $e';

/// Transbordo: el transportista elige a qué otro transportista pasar la
/// tarea. Sigue siendo suya hasta que el otro acepte. Devuelve true si se
/// envió.
Future<bool> mostrarTransbordo(BuildContext context, Guia guia) async {
  final enviado = await showDialog<bool>(
    context: context,
    builder: (_) => _DialogoTransbordo(guia: guia),
  );
  return enviado ?? false;
}

class _DialogoTransbordo extends StatefulWidget {
  const _DialogoTransbordo({required this.guia});

  final Guia guia;

  @override
  State<_DialogoTransbordo> createState() => _DialogoTransbordoState();
}

class _DialogoTransbordoState extends State<_DialogoTransbordo> {
  late final Future<List<String>> _transportistas = context
      .read<AppState>()
      .listarTransportistas();
  final _busqueda = TextEditingController();
  String? _elegido;
  bool _enviando = false;
  String? _falla;

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final a = _elegido;
    if (a == null) return;
    setState(() {
      _enviando = true;
      _falla = null;
    });
    try {
      await context.read<AppState>().pedirTransbordo(widget.guia, a);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _enviando = false;
          _falla = _error(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final yo = widget.guia.transportista.trim().toLowerCase();
    return AlertDialog(
      title: const Text('Transbordo'),
      content: SizedBox(
        width: 400,
        child: FutureBuilder<List<String>>(
          future: _transportistas,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Text(
                'No se pudo cargar la lista: ${_error(snap.error!)}',
                style: const TextStyle(color: _rojo),
              );
            }
            final q = _busqueda.text.trim().toLowerCase();
            final otros = [
              for (final n in snap.data!)
                if (n.trim().toLowerCase() != yo) n,
            ];
            final visibles = [
              for (final n in otros)
                if (q.isEmpty || n.toLowerCase().contains(q)) n,
            ];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Pasa la guía ${widget.guia.numeroGuia} a otro '
                  'transportista. Sigue siendo tuya hasta que la acepte.',
                  style: const TextStyle(color: Ipesa.textoSuave),
                ),
                const SizedBox(height: 12),
                if (otros.isEmpty)
                  const Text('No hay otros transportistas activos.')
                else ...[
                  if (otros.length > 6) ...[
                    TextField(
                      controller: _busqueda,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Buscar transportista',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: RadioGroup<String>(
                      groupValue: _elegido,
                      onChanged: (v) {
                        if (!_enviando) setState(() => _elegido = v);
                      },
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final n in visibles)
                            RadioListTile<String>(
                              value: n,
                              title: Text(n),
                              secondary: CircleAvatar(
                                radius: 16,
                                backgroundColor: Ipesa.menta,
                                child: Text(
                                  _iniciales(n),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Ipesa.petroleo,
                                  ),
                                ),
                              ),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            ),
                          if (visibles.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text('Nadie coincide con la búsqueda.'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_falla != null) ...[
                  const SizedBox(height: 10),
                  Text(_falla!, style: const TextStyle(color: _rojo)),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _elegido == null || _enviando ? null : _enviar,
          icon: _enviando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.swap_horiz_rounded),
          label: Text(_elegido == null ? 'Enviar' : 'Enviar a $_elegido'),
        ),
      ],
    );
  }
}

String _iniciales(String nombre) => nombre
    .split(RegExp(r'\s+'))
    .where((p) => p.isNotEmpty)
    .take(2)
    .map((p) => p[0].toUpperCase())
    .join();

/// Línea en la tarjeta de quien envió o recibió la tarea: esperando que
/// el otro acepte, que no la aceptó, o de quién la recibió.
class AvisoTransbordo extends StatelessWidget {
  const AvisoTransbordo({super.key, required this.guia});

  final Guia guia;

  @override
  Widget build(BuildContext context) {
    final (icono, texto, color) = guia.transbordoPendiente
        ? (
            Icons.hourglass_top_rounded,
            'Esperando que ${guia.transbordoA} acepte el transbordo',
            _azul,
          )
        : guia.transbordoRechazado
        ? (
            Icons.do_not_disturb_on,
            '${guia.transbordoA} no aceptó el transbordo',
            _rojo,
          )
        : (
            Icons.swap_horiz_rounded,
            'Te la pasó ${guia.transbordoDe}',
            Ipesa.turquesa,
          );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icono, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Si esta guía tiene algo de transbordo que mostrar a [yo].
  static bool hayQueMostrar(Guia guia, String yo) =>
      guia.transbordoPendiente ||
      guia.transbordoRechazado ||
      (guia.transbordoAceptado &&
          guia.transbordoDe.isNotEmpty &&
          guia.transportista == yo);
}

/// Acepta o rechaza el transbordo; avisa el resultado. Devuelve true si se
/// respondió.
Future<bool> responderTransbordo(
  BuildContext context,
  Guia guia, {
  required bool acepta,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await context.read<AppState>().responderTransbordo(guia, acepta: acepta);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          acepta
              ? 'Aceptaste la guía ${guia.numeroGuia}. Ya está en tus '
                    'pendientes.'
              : 'Rechazaste la guía ${guia.numeroGuia}. Vuelve a '
                    '${guia.transportista}.',
        ),
      ),
    );
    return true;
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('No se pudo responder: ${_error(e)}')),
    );
    return false;
  }
}

/// Lo que otro transportista le quiere pasar: quién, la guía y los botones
/// para aceptar o rechazar.
class TarjetaTransbordoRecibido extends StatefulWidget {
  const TarjetaTransbordoRecibido({super.key, required this.guia});

  final Guia guia;

  @override
  State<TarjetaTransbordoRecibido> createState() =>
      _TarjetaTransbordoRecibidoState();
}

class _TarjetaTransbordoRecibidoState extends State<TarjetaTransbordoRecibido> {
  bool _respondiendo = false;

  Future<void> _responder(bool acepta) async {
    setState(() => _respondiendo = true);
    await responderTransbordo(context, widget.guia, acepta: acepta);
    if (mounted) setState(() => _respondiendo = false);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.guia;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFB9CDEB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz_rounded, color: _azul, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${g.transportista} te pasa esta tarea',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _azul,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DatosGuia(guia: g),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: _rojo,
                  ),
                  onPressed: _respondiendo ? null : () => _responder(false),
                  child: const Text('Rechazar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: _respondiendo ? null : () => _responder(true),
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: const Text('Aceptar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DatosGuia extends StatelessWidget {
  const _DatosGuia({required this.guia});

  final Guia guia;

  @override
  Widget build(BuildContext context) {
    final g = guia;
    final salio = DateFormat('dd/MM HH:mm').format(g.fechaCreacion.toLocal());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(g.numeroGuia, style: Ipesa.titulo(16)),
        const SizedBox(height: 4),
        Text(
          g.destinatario,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.location_on_outlined,
              size: 16,
              color: Ipesa.turquesa,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                g.destino,
                style: const TextStyle(fontSize: 14, color: Ipesa.etiqueta),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          [
            if (g.origen.trim().isNotEmpty) 'Salió de ${g.origen.trim()}',
            salio,
          ].join(' · '),
          style: const TextStyle(fontSize: 13, color: Ipesa.textoSuave),
        ),
      ],
    );
  }
}

/// El anuncio al entrar a la app: otro transportista le pasa una tarea.
Future<void> mostrarAnuncioTransbordo(BuildContext context, Guia guia) {
  return showDialog<void>(
    context: context,
    builder: (dialogo) {
      void responder(bool acepta) {
        Navigator.of(dialogo).pop();
        responderTransbordo(context, guia, acepta: acepta);
      }

      return AlertDialog(
        icon: const Icon(Icons.swap_horiz_rounded, color: _azul, size: 36),
        title: Text('${guia.transportista} te pasa una tarea'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DatosGuia(guia: guia),
              const SizedBox(height: 12),
              const Text(
                'Si la aceptas, tú haces la entrega (con su foto). La salida '
                'sigue siendo desde donde partió.',
                style: TextStyle(fontSize: 13.5, color: Ipesa.textoSuave),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        foregroundColor: _rojo,
                      ),
                      onPressed: () => responder(false),
                      child: const Text('Rechazar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                      onPressed: () => responder(true),
                      child: const Text('Aceptar'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(dialogo).pop(),
                child: const Text('Ver después'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
