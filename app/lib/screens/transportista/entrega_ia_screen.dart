import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../models/tipo_entrega.dart';
import '../../services/guias_api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/gps_transportista.dart';

/// Cuántas fotos lee la IA a la vez y cuántas entregas se envían a la vez
/// (cada entrega sube su foto: de a pocas para no saturar).
const _lecturasSimultaneas = 3;
const _entregasSimultaneas = 2;

/// Esperas antes de reintentar una foto si la IA está ocupada.
const _esperasIAOcupada = [
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 20),
  Duration(seconds: 30),
  Duration(seconds: 45),
];

final _picker = ImagePicker();

Future<List<Uint8List>> _fotoDeCamara() async {
  final archivo = await _picker.pickImage(
    source: ImageSource.camera,
    maxWidth: 1600,
    imageQuality: 90,
  );
  return archivo == null ? const [] : [await archivo.readAsBytes()];
}

Future<List<Uint8List>> _fotosDeGaleria() async {
  final archivos = await _picker.pickMultiImage(
    maxWidth: 1600,
    imageQuality: 90,
    limit: maxGuiasPorCarga,
  );
  return [for (final a in archivos) await a.readAsBytes()];
}

/// El número de guía para comparar: sin espacios y en mayúsculas.
String _clave(String numero) =>
    numero.toUpperCase().replaceAll(RegExp(r'\s+'), '');

enum _Estado { leyendo, encontrada, noEncontrada, sinNumero, repetida, error }

/// Una foto de la entrega: lo que leyó la IA y a qué tarea corresponde.
class _Foto {
  _Foto(this.bytes, this.id);

  final Uint8List bytes;
  final int id;
  _Estado estado = _Estado.leyendo;
  bool leida = false;
  String? numeroLeido;
  Guia? guia;
  String? aviso;
  bool enviando = false;
  String? error;
}

/// "Entrega inteligente": el transportista sube hasta [maxGuiasPorCarga] fotos
/// de guías entregadas; la IA lee el número de guía de cada una y la busca
/// entre sus tareas en ruta. Las que encuentra quedan listas para
/// entregar (con esa foto como foto de entrega, y la hora y el GPS de
/// ahora); las que no, se muestran aparte y no se entregan. Nada se
/// entrega hasta que él revisa y confirma.
class EntregaIAScreen extends StatefulWidget {
  const EntregaIAScreen({super.key});

  /// Los tests los reemplazan (no hay cámara ahí).
  @visibleForTesting
  static Future<List<Uint8List>> Function() tomarFoto = _fotoDeCamara;
  @visibleForTesting
  static Future<List<Uint8List>> Function() elegirFotos = _fotosDeGaleria;

  @override
  State<EntregaIAScreen> createState() => _EntregaIAScreenState();
}

class _EntregaIAScreenState extends State<EntregaIAScreen>
    with GpsTransportista {
  final _fotos = <_Foto>[];
  final _cola = <_Foto>[];
  int _leyendoAhora = 0;
  int _siguienteId = 0;
  bool _abriendo = false;
  bool _entregando = false;

  /// Sus tareas en ruta, por número de guía (la más reciente si se repite).
  Map<String, Guia> _pendientes(AppState appState) {
    final porNumero = <String, Guia>{};
    for (final g in appState.guiasDelTransportista(
      appState.transportistaActual,
    )) {
      if (g.estado != EstadoGuia.enRuta) continue;
      final clave = _clave(g.numeroGuia);
      final otra = porNumero[clave];
      if (otra == null || g.fechaCreacion.isAfter(otra.fechaCreacion)) {
        porNumero[clave] = g;
      }
    }
    return porNumero;
  }

  Future<void> _agregar(Future<List<Uint8List>> Function() origen) async {
    setState(() => _abriendo = true);
    try {
      final elegidas = await origen();
      if (!mounted || elegidas.isEmpty) return;
      final espacio = maxGuiasPorCarga - _fotos.length;
      final nuevas = elegidas.take(espacio < 0 ? 0 : espacio).toList();
      if (nuevas.length < elegidas.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Máximo $maxGuiasPorCarga fotos por entrega: se agregaron '
              '${nuevas.isEmpty ? 'ninguna' : 'las primeras ${nuevas.length}'}.',
            ),
          ),
        );
      }
      setState(() {
        for (final bytes in nuevas) {
          final f = _Foto(bytes, _siguienteId++);
          _fotos.add(f);
          _cola.add(f);
        }
      });
      _leerSiguientes();
      refrescarGps();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo abrir la foto: $e')));
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  void _leerSiguientes() {
    while (_leyendoAhora < _lecturasSimultaneas && _cola.isNotEmpty) {
      final f = _cola.removeAt(0);
      if (!_fotos.contains(f)) continue;
      _leyendoAhora++;
      _leer(f).whenComplete(() {
        _leyendoAhora--;
        if (mounted) _leerSiguientes();
      });
    }
  }

  Future<void> _leer(_Foto f) async {
    final appState = context.read<AppState>();
    try {
      final datos = await _leerConReintentos(appState, f);
      if (datos == null || !mounted || !_fotos.contains(f)) return;
      setState(() {
        f.aviso = null;
        f.leida = true;
        f.numeroLeido = datos.numeroGuia?.trim();
        _clasificar(appState);
      });
    } catch (_) {
      if (!mounted || !_fotos.contains(f)) return;
      setState(() {
        f.estado = _Estado.error;
        f.aviso = 'No se pudo leer la foto.';
      });
    }
  }

  /// Lee la foto; si la IA está ocupada, espera y vuelve a intentar.
  Future<DatosGuiaLeida?> _leerConReintentos(AppState appState, _Foto f) async {
    for (var intento = 0; ; intento++) {
      try {
        return await appState.leerGuiaConIA(f.bytes);
      } on ApiException catch (e) {
        if (!e.esLimiteTemporal || intento >= _esperasIAOcupada.length) {
          rethrow;
        }
      }
      if (!mounted || !_fotos.contains(f)) return null;
      setState(() => f.aviso = 'La IA está ocupada: reintentando…');
      await Future<void>.delayed(_esperasIAOcupada[intento]);
      if (!mounted || !_fotos.contains(f)) return null;
    }
  }

  /// A qué tarea corresponde cada foto ya leída. Si dos fotos son de la
  /// misma guía, cuenta la primera.
  void _clasificar(AppState appState) {
    final pendientes = _pendientes(appState);
    final usadas = <String>{};
    for (final f in _fotos) {
      if (!f.leida || f.estado == _Estado.error || f.enviando) continue;
      final numero = f.numeroLeido;
      if (numero == null || numero.isEmpty) {
        f.estado = _Estado.sinNumero;
        f.guia = null;
        continue;
      }
      final clave = _clave(numero);
      final guia = pendientes[clave];
      if (guia == null) {
        f.estado = _Estado.noEncontrada;
        f.guia = null;
      } else if (!usadas.add(clave)) {
        f.estado = _Estado.repetida;
        f.guia = null;
      } else {
        f.estado = _Estado.encontrada;
        f.guia = guia;
      }
    }
  }

  void _quitar(_Foto f) {
    setState(() {
      _fotos.remove(f);
      _cola.remove(f);
      _clasificar(context.read<AppState>());
    });
  }

  static EstadoGuia _estadoFinal(Guia g) => g.tipoEntrega == TipoEntrega.agencia
      ? EstadoGuia.finalizado
      : EstadoGuia.entregado;

  /// Entrega todas las encontradas (de a [_entregasSimultaneas]), cada una
  /// con su foto, la hora y el GPS de ahora.
  Future<void> _entregar() async {
    final appState = context.read<AppState>();
    final listas = [
      for (final f in _fotos)
        if (f.estado == _Estado.encontrada && f.guia != null) f,
    ];
    if (listas.isEmpty || !gpsActivo || lat == null || lng == null) return;
    final latitud = lat!;
    final longitud = lng!;
    setState(() {
      _entregando = true;
      for (final f in listas) {
        f.enviando = true;
        f.error = null;
      }
    });
    var ok = 0;
    final pendientes = [...listas];
    Future<void> trabajador() async {
      while (pendientes.isNotEmpty) {
        final f = pendientes.removeAt(0);
        final g = f.guia!;
        try {
          await appState.actualizarEstado(
            g.numeroGuia,
            _estadoFinal(g),
            lat: latitud,
            lng: longitud,
            foto: f.bytes,
            fechaCreacion: g.fechaCreacion,
          );
          ok++;
          if (mounted) setState(() => _fotos.remove(f));
        } catch (e) {
          if (mounted) {
            setState(() {
              f.enviando = false;
              f.error = e is ApiException ? e.mensaje : 'Error de conexión: $e';
            });
          }
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < _entregasSimultaneas; i++) trabajador(),
    ]);
    if (!mounted) return;
    final fallidas = listas.length - ok;
    final sinEntregar = _fotos
        .where((f) => f.estado != _Estado.encontrada)
        .length;
    setState(() => _entregando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          [
            if (ok > 0) ok == 1 ? '1 guía entregada' : '$ok guías entregadas',
            if (fallidas > 0)
              fallidas == 1
                  ? '1 no se pudo entregar'
                  : '$fallidas no se pudieron entregar',
            if (sinEntregar > 0)
              sinEntregar == 1
                  ? '1 foto sin tarea'
                  : '$sinEntregar fotos sin tarea',
          ].join(' · '),
        ),
      ),
    );
    if (fallidas == 0) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final leyendo = _fotos.where((f) => f.estado == _Estado.leyendo).length;
    final encontradas = _fotos
        .where((f) => f.estado == _Estado.encontrada)
        .toList();
    final otras = _fotos
        .where(
          (f) => f.estado != _Estado.encontrada && f.estado != _Estado.leyendo,
        )
        .toList();
    final enCurso = _fotos.where((f) => f.estado == _Estado.leyendo).toList();
    final puedeAgregar =
        gpsActivo &&
        !_abriendo &&
        !_entregando &&
        _fotos.length < maxGuiasPorCarga;
    final n = encontradas.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Entrega inteligente')),
      bottomNavigationBar: _fotos.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (leyendo > 0 || otras.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          [
                            if (leyendo > 0)
                              leyendo == 1
                                  ? 'La IA está leyendo 1 foto…'
                                  : 'La IA está leyendo $leyendo fotos…',
                            if (otras.isNotEmpty)
                              otras.length == 1
                                  ? '1 foto no se entregará'
                                  : '${otras.length} fotos no se entregarán',
                          ].join(' · '),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Ipesa.textoSuave),
                        ),
                      ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: const Color(0xFF1D6B41),
                      ),
                      onPressed: n > 0 && gpsActivo && !_entregando
                          ? _entregar
                          : null,
                      icon: _entregando
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.task_alt_rounded),
                      label: Text(
                        _entregando
                            ? 'Entregando…'
                            : n == 1
                            ? 'Entregar 1 guía'
                            : 'Entregar $n guías',
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          tarjetaGps(
            textoActivo: 'Ubicación disponible: se guardará en cada entrega.',
            textoApagado:
                'Obligatorio: sin GPS no se puede registrar ninguna entrega.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Sube las fotos de las guías entregadas (firmadas o selladas). '
            'La IA lee el número de cada una y la busca en tus tareas en '
            'ruta. Revisa la lista y confirma: solo se entregan las que '
            'encontró.',
            style: TextStyle(color: Ipesa.textoSuave, fontSize: 14),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: puedeAgregar
                      ? () => _agregar(EntregaIAScreen.tomarFoto)
                      : null,
                  icon: const Icon(Icons.camera_alt),
                  label: Text(_fotos.isEmpty ? 'Tomar foto' : 'Otra foto'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: puedeAgregar
                      ? () => _agregar(EntregaIAScreen.elegirFotos)
                      : null,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    _fotos.isEmpty
                        ? 'Galería'
                        : 'Galería · ${_fotos.length}/$maxGuiasPorCarga',
                  ),
                ),
              ),
            ],
          ),
          if (encontradas.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              n == 1 ? 'Para entregar · 1' : 'Para entregar · $n',
              style: Ipesa.titulo(16, color: const Color(0xFF1D6B41)),
            ),
            for (final f in encontradas) _fila(f),
          ],
          if (enCurso.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('Leyendo', style: Ipesa.titulo(16)),
            for (final f in enCurso) _fila(f),
          ],
          if (otras.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'No se entregarán · ${otras.length}',
              style: Ipesa.titulo(16, color: EstadoGuia.rechazado.color),
            ),
            for (final f in otras) _fila(f),
          ],
        ],
      ),
    );
  }

  Widget _fila(_Foto f) {
    final (titulo, detalle, color) = switch (f.estado) {
      _Estado.leyendo => (
        'Leyendo con IA…',
        f.aviso ?? 'Buscando el número de guía',
        Ipesa.petroleo,
      ),
      _Estado.encontrada => (
        f.guia!.numeroGuia,
        f.error ??
            (f.enviando
                ? 'Entregando…'
                : '${f.guia!.destinatario} · ${f.guia!.destino}'),
        f.error != null ? EstadoGuia.rechazado.color : const Color(0xFF1D6B41),
      ),
      _Estado.noEncontrada => (
        f.numeroLeido ?? '',
        'No está en tus tareas en ruta',
        EstadoGuia.rechazado.color,
      ),
      _Estado.sinNumero => (
        'Sin número',
        'La IA no pudo leer el número de guía',
        EstadoGuia.rechazado.color,
      ),
      _Estado.repetida => (
        f.numeroLeido ?? '',
        'Repetida: ya está en otra foto',
        Ipesa.textoSuave,
      ),
      _Estado.error => (
        'Error',
        f.aviso ?? 'No se pudo leer la foto',
        EstadoGuia.rechazado.color,
      ),
    };
    return Padding(
      key: ValueKey(f.id),
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFDEE5E3)),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Image.memory(f.bytes, fit: BoxFit.cover, cacheWidth: 160),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: Ipesa.titulo(14.5, color: color)),
                  Text(
                    detalle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Ipesa.textoSuave,
                    ),
                  ),
                ],
              ),
            ),
            if (f.enviando)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                tooltip: 'Quitar foto',
                onPressed: _entregando ? null : () => _quitar(f),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }
}
