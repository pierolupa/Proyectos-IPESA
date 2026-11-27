import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/guias_api.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Pasa las fotos viejas de Vercel Blob a la carpeta de Google Drive, de a
/// tandas, mostrando el avance. Para cuando no quedan, o cuando una tanda no
/// pudo mover ninguna (por ejemplo, si Vercel tiene bloqueado Blob).
Future<void> mostrarMigrarFotos(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _DialogoMigrarFotos(),
);

class _DialogoMigrarFotos extends StatefulWidget {
  const _DialogoMigrarFotos();

  @override
  State<_DialogoMigrarFotos> createState() => _DialogoMigrarFotosState();
}

class _DialogoMigrarFotosState extends State<_DialogoMigrarFotos> {
  bool _trabajando = false;
  bool _detener = false;
  int _movidas = 0;
  int? _pendientes;
  List<String> _errores = const [];
  String? _falla;

  @override
  void initState() {
    super.initState();
    _pasar();
  }

  Future<void> _pasar() async {
    final app = context.read<AppState>();
    setState(() {
      _trabajando = true;
      _detener = false;
      _errores = const [];
      _falla = null;
    });
    try {
      while (mounted && !_detener) {
        final r = await app.migrarFotos();
        if (!mounted) return;
        setState(() {
          _movidas += r.movidas;
          _pendientes = r.pendientes;
          _errores = r.errores;
        });
        if (r.pendientes == 0 || r.movidas == 0) break;
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _falla = e.mensaje);
    } catch (e) {
      if (mounted) setState(() => _falla = 'Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendientes = _pendientes;
    final listo = !_trabajando && pendientes == 0 && _falla == null;
    final trabado =
        !_trabajando && (pendientes ?? 0) > 0 && _errores.isNotEmpty;
    final String estado;
    if (_falla != null) {
      estado = _falla!;
    } else if (_trabajando) {
      estado = pendientes == null
          ? 'Buscando fotos en Vercel Blob…'
          : 'Pasando fotos a Drive… quedan $pendientes.';
    } else if (listo) {
      estado = _movidas == 0
          ? 'No hay fotos en Vercel Blob: todas ya están en Drive.'
          : 'Listo: todas las fotos están en Drive.';
    } else if (trabado) {
      estado =
          'No se pudieron leer las fotos de Vercel Blob. Si Vercel lo tiene '
          'bloqueado, vuelve a intentarlo cuando se desbloquee. Quedan '
          '$pendientes.';
    } else {
      estado = 'Detenido. Quedan ${pendientes ?? 0}.';
    }

    return AlertDialog(
      title: const Text('Pasar fotos a Drive'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Copia a la carpeta de Google Drive las fotos que quedaron en '
              'Vercel Blob y las borra de ahí. Las guías siguen mostrando su '
              'foto como siempre.',
              style: TextStyle(color: Ipesa.textoSuave, fontSize: 13.5),
            ),
            const SizedBox(height: 18),
            if (_trabajando) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            Text(
              estado,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _falla != null || trabado
                    ? const Color(0xFFB42318)
                    : Ipesa.texto,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _movidas == 1
                  ? '1 foto pasada a Drive'
                  : '$_movidas fotos pasadas a Drive',
              style: const TextStyle(color: Ipesa.textoSuave),
            ),
            if (_errores.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _errores.first,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: Ipesa.textoSuave),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_trabajando)
          TextButton(
            onPressed: _detener ? null : () => setState(() => _detener = true),
            child: Text(_detener ? 'Deteniendo…' : 'Detener'),
          )
        else ...[
          if (!listo)
            TextButton(onPressed: _pasar, child: const Text('Reintentar')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ],
    );
  }
}
