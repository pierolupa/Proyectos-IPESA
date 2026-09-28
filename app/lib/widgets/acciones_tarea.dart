import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/guia.dart';
import '../models/tipo_entrega.dart';
import '../services/guias_api.dart';
import '../state/app_state.dart';
import '../theme.dart';

const _rojo = Color(0xFFB42318);

void _avisar(BuildContext context, String mensaje) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
}

String _error(Object e) =>
    e is ApiException ? e.mensaje : 'Error de conexión: $e';

/// Cambiar el tipo de entrega de una tarea. El transportista solo mientras
/// está en ruta; el administrador ([porAdmin]) siempre. Devuelve true si se
/// guardó.
Future<bool> mostrarCambioTipo(
  BuildContext context,
  Guia guia, {
  bool porAdmin = false,
}) async {
  final guardado = await showDialog<bool>(
    context: context,
    builder: (_) => _DialogoTipo(guia: guia, porAdmin: porAdmin),
  );
  return guardado ?? false;
}

class _DialogoTipo extends StatefulWidget {
  const _DialogoTipo({required this.guia, required this.porAdmin});

  final Guia guia;
  final bool porAdmin;

  @override
  State<_DialogoTipo> createState() => _DialogoTipoState();
}

class _DialogoTipoState extends State<_DialogoTipo> {
  late TipoEntrega _tipo = widget.guia.tipoEntrega;
  String? _sucursal;
  late final _destino = TextEditingController(
    text: widget.guia.tipoEntrega == TipoEntrega.entreSucursales
        ? ''
        : widget.guia.destino,
  );
  bool _guardando = false;
  String? _falla;

  @override
  void initState() {
    super.initState();
    if (widget.guia.tipoEntrega == TipoEntrega.entreSucursales) {
      _sucursal = widget.guia.destino;
    }
  }

  @override
  void dispose() {
    _destino.dispose();
    super.dispose();
  }

  bool get _traslado => _tipo == TipoEntrega.entreSucursales;

  Future<void> _guardar() async {
    final destino = _traslado ? _sucursal : _destino.text.trim();
    if (_traslado && destino == null) {
      setState(() => _falla = 'Elige la sucursal destino.');
      return;
    }
    setState(() {
      _guardando = true;
      _falla = null;
    });
    try {
      await context.read<AppState>().cambiarTipoEntrega(
        widget.guia,
        _tipo,
        destino: destino == null || destino.isEmpty ? null : destino,
        porAdmin: widget.porAdmin,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _falla = _error(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sucursales = [
      for (final s in context.watch<AppState>().sucursales) s.nombre,
    ];
    return AlertDialog(
      title: const Text('Tipo de entrega'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RadioGroup<TipoEntrega>(
                groupValue: _tipo,
                onChanged: (t) {
                  if (t != null && !_guardando) setState(() => _tipo = t);
                },
                child: Column(
                  children: [
                    for (final t in TipoEntrega.values)
                      RadioListTile<TipoEntrega>(
                        value: t,
                        title: Text(t.etiqueta),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (_traslado)
                DropdownButtonFormField<String>(
                  initialValue: sucursales.contains(_sucursal)
                      ? _sucursal
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Sucursal destino',
                    helperText: sucursales.isEmpty
                        ? 'El administrador aún no registró sucursales.'
                        : null,
                  ),
                  items: [
                    for (final s in sucursales)
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() => _sucursal = v),
                )
              else
                TextField(
                  controller: _destino,
                  enabled: !_guardando,
                  decoration: const InputDecoration(
                    labelText: 'Destino',
                    helperText: 'Déjalo igual si no cambia.',
                  ),
                ),
              if (_falla != null) ...[
                const SizedBox(height: 10),
                Text(_falla!, style: const TextStyle(color: _rojo)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

/// El transportista pide borrar una tarea en ruta; el administrador decide.
/// Devuelve true si se envió el pedido.
Future<bool> mostrarPedidoEliminacion(BuildContext context, Guia guia) async {
  final enviado = await showDialog<bool>(
    context: context,
    builder: (_) => _DialogoEliminacion(guia: guia),
  );
  return enviado ?? false;
}

class _DialogoEliminacion extends StatefulWidget {
  const _DialogoEliminacion({required this.guia});

  final Guia guia;

  @override
  State<_DialogoEliminacion> createState() => _DialogoEliminacionState();
}

class _DialogoEliminacionState extends State<_DialogoEliminacion> {
  final _motivo = TextEditingController();
  bool _enviando = false;
  String? _falla;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_motivo.text.trim().length < 3) {
      setState(() => _falla = 'Cuéntale al administrador por qué.');
      return;
    }
    setState(() {
      _enviando = true;
      _falla = null;
    });
    try {
      await context.read<AppState>().pedirEliminacion(
        widget.guia,
        _motivo.text.trim(),
      );
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
    return AlertDialog(
      title: const Text('Eliminar tarea'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Se le pedirá al administrador que apruebe borrar la guía '
              '${widget.guia.numeroGuia}. Mientras tanto la tarea sigue en '
              'tu lista.',
              style: const TextStyle(color: Ipesa.etiqueta),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _motivo,
              enabled: !_enviando,
              autofocus: true,
              maxLength: 300,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                hintText: 'Ej.: la registré por error, es duplicada…',
              ),
            ),
            if (_falla != null)
              Text(_falla!, style: const TextStyle(color: _rojo)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _rojo),
          onPressed: _enviando ? null : _enviar,
          child: _enviando
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Pedir eliminación'),
        ),
      ],
    );
  }
}

/// Para el transportista: su pedido de eliminación está esperando al
/// administrador (y lo puede retirar), o el administrador no lo aprobó.
class AvisoEliminacion extends StatefulWidget {
  const AvisoEliminacion({super.key, required this.guia});

  final Guia guia;

  @override
  State<AvisoEliminacion> createState() => _AvisoEliminacionState();
}

class _AvisoEliminacionState extends State<AvisoEliminacion> {
  bool _retirando = false;

  Future<void> _retirar() async {
    setState(() => _retirando = true);
    try {
      await context.read<AppState>().retirarPedidoEliminacion(widget.guia);
    } catch (e) {
      if (mounted) _avisar(context, _error(e));
    } finally {
      if (mounted) setState(() => _retirando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.guia;
    if (!g.eliminacionPendiente && !g.eliminacionRechazada) {
      return const SizedBox.shrink();
    }
    final pendiente = g.eliminacionPendiente;
    final color = pendiente ? const Color(0xFF8A4F00) : _rojo;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(Ipesa.radioCampo),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            pendiente ? Icons.hourglass_top_rounded : Icons.do_not_disturb_on,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pendiente
                      ? 'Pediste eliminar esta tarea'
                      : 'El administrador no aprobó eliminarla',
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  pendiente
                      ? 'Esperando la respuesta del administrador.'
                      : 'La tarea sigue asignada a ti.',
                  style: const TextStyle(color: Ipesa.texto),
                ),
                if (g.motivoEliminacion.trim().isNotEmpty)
                  Text(
                    'Motivo: ${g.motivoEliminacion.trim()}',
                    style: const TextStyle(color: Ipesa.textoSuave),
                  ),
                if (pendiente)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _retirando ? null : _retirar,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: Ipesa.petroleo,
                      ),
                      child: Text(_retirando ? 'Retirando…' : 'Retirar pedido'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Para el administrador: el transportista pide borrar la tarea. Aprobar la
/// borra de la hoja; "Mantener" la deja como estaba.
class SolicitudEliminacionAdmin extends StatefulWidget {
  const SolicitudEliminacionAdmin({
    super.key,
    required this.guia,
    required this.onEliminada,
  });

  final Guia guia;
  final VoidCallback onEliminada;

  @override
  State<SolicitudEliminacionAdmin> createState() =>
      _SolicitudEliminacionAdminState();
}

class _SolicitudEliminacionAdminState extends State<SolicitudEliminacionAdmin> {
  bool _ocupado = false;

  Future<void> _aprobar() async {
    final g = widget.guia;
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar la tarea?'),
        content: Text(
          'La guía ${g.numeroGuia} de ${g.transportista} se borrará por '
          'completo de la base de datos. No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _rojo),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (seguro != true || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await context.read<AppState>().eliminarGuia(g);
      if (mounted) widget.onEliminada();
    } catch (e) {
      if (mounted) {
        setState(() => _ocupado = false);
        _avisar(context, _error(e));
      }
    }
  }

  Future<void> _mantener() async {
    setState(() => _ocupado = true);
    try {
      await context.read<AppState>().rechazarEliminacion(widget.guia);
      if (mounted) {
        _avisar(context, 'Pedido rechazado: la tarea se mantiene.');
      }
    } catch (e) {
      if (mounted) _avisar(context, _error(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.guia;
    if (!g.eliminacionPendiente) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _rojo.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(Ipesa.radioCampo),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.delete_outline_rounded, color: _rojo),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${g.transportista} pide eliminar esta tarea',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: _rojo,
                  ),
                ),
              ),
            ],
          ),
          if (g.motivoEliminacion.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Motivo: ${g.motivoEliminacion.trim()}',
              style: const TextStyle(color: Ipesa.texto),
            ),
          ],
          const SizedBox(height: 4),
          const Text(
            'Si la apruebas, se borra por completo de la base de datos.',
            style: TextStyle(color: Ipesa.textoSuave, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _rojo),
                onPressed: _ocupado ? null : _aprobar,
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Aprobar y eliminar'),
              ),
              OutlinedButton(
                onPressed: _ocupado ? null : _mantener,
                child: const Text('Mantener tarea'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Botón del administrador para quitar la foto de la entrega.
class BotonEliminarFoto extends StatefulWidget {
  const BotonEliminarFoto({super.key, required this.guia});

  final Guia guia;

  @override
  State<BotonEliminarFoto> createState() => _BotonEliminarFotoState();
}

class _BotonEliminarFotoState extends State<BotonEliminarFoto> {
  bool _borrando = false;

  Future<void> _borrar() async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar la foto?'),
        content: const Text(
          'La foto de la entrega se quitará de esta guía. La guía y su '
          'estado no cambian.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _rojo),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar foto'),
          ),
        ],
      ),
    );
    if (seguro != true || !mounted) return;
    setState(() => _borrando = true);
    try {
      final aviso = await context.read<AppState>().eliminarFotoEntrega(
        widget.guia,
      );
      if (mounted) _avisar(context, aviso ?? 'Foto eliminada.');
    } catch (e) {
      if (mounted) _avisar(context, _error(e));
    } finally {
      if (mounted) setState(() => _borrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.guia.tieneFotoEntrega) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _borrando ? null : _borrar,
        style: TextButton.styleFrom(foregroundColor: _rojo),
        icon: const Icon(Icons.hide_image_outlined),
        label: Text(_borrando ? 'Eliminando…' : 'Eliminar foto'),
      ),
    );
  }
}
