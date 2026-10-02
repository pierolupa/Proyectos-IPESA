import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/sucursal.dart';
import '../../models/tipo_entrega.dart';
import '../../services/guias_api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/aviso_sucursal.dart';
import '../../widgets/gps_transportista.dart';

/// Cuántas fotos lee la IA a la vez (el resto espera su turno).
const _lecturasSimultaneas = 3;

/// Esperas antes de reintentar una foto si la IA está ocupada (límite por
/// minuto, por ejemplo con varios transportistas cargando a la vez).
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

/// Una guía por registrar: su foto y los datos que leyó la IA (editables).
class _Borrador {
  _Borrador(this.foto, this.id);

  final Uint8List foto;
  final int id;
  final numero = TextEditingController();
  final destinatario = TextEditingController();
  final destino = TextEditingController();
  final origen = TextEditingController();
  final pedido = TextEditingController();
  final entrega = TextEditingController();
  TipoEntrega tipo = TipoEntrega.clienteFinal;

  /// El comprobante de agencia pegado en la guía, si la IA lo encontró.
  ComprobanteAgencia? comprobante;
  bool enCola = true;
  bool leyendo = false;
  String? avisoLectura;
  bool enviando = false;
  String? error;

  void dispose() {
    for (final c in [numero, destinatario, destino, origen, pedido, entrega]) {
      c.dispose();
    }
  }
}

/// Flujo de "Asignación" (ARCHITECTURE.md, sección 4.1): el transportista
/// fotografía las guías antes de salir. Puede tomar o elegir VARIAS fotos
/// seguidas: cada una queda como una tarjeta que la IA va llenando en
/// paralelo (Gemini con visión, vía backend/src/ocrAgente.js) mientras él
/// sigue fotografiando. Revisa y corrige lo que haga falta, y registra
/// todas las que estén listas de una vez. El GPS es obligatorio. Un
/// transportista no registra el mismo número dos veces dentro de 20
/// minutos (otro transportista sí puede).
class CaptureFlowScreen extends StatefulWidget {
  const CaptureFlowScreen({
    super.key,
    this.despachoCorte = false,
    this.codigoCorte,
  });

  /// Despacho Corte: las guías se registran igual, pero unidas en un solo
  /// despacho que sale y llega junto (sin foto al llegar).
  final bool despachoCorte;

  /// Para sumar guías a un Despacho Corte que ya está en camino.
  final String? codigoCorte;

  /// Los tests los reemplazan (no hay cámara ahí). El GPS, en
  /// `Ubicacion.leer`.
  @visibleForTesting
  static Future<List<Uint8List>> Function() tomarFoto = _fotoDeCamara;
  @visibleForTesting
  static Future<List<Uint8List>> Function() elegirFotos = _fotosDeGaleria;

  @override
  State<CaptureFlowScreen> createState() => _CaptureFlowScreenState();
}

class _CaptureFlowScreenState extends State<CaptureFlowScreen>
    with GpsTransportista {
  bool _abriendoFotos = false;
  bool _registrando = false;
  final _borradores = <_Borrador>[];
  final _cola = <_Borrador>[];
  int _leyendoAhora = 0;
  int _siguienteId = 0;

  /// El código del Despacho Corte una vez creado: si registra más guías
  /// desde esta misma pantalla, se suman al mismo corte.
  late String? _codigoCorte = widget.codigoCorte;

  @override
  void dispose() {
    for (final b in _borradores) {
      b.dispose();
    }
    super.dispose();
  }

  /// La sucursal donde está el transportista (por el GPS), si hay.
  Sucursal? _sucursalAqui(AppState appState) =>
      gpsActivo && lat != null && lng != null
      ? appState.sucursalEnPunto(lat!, lng!)
      : null;

  Future<void> _agregarFotos(Future<List<Uint8List>> Function() origen) async {
    setState(() => _abriendoFotos = true);
    try {
      final elegidas = await origen();
      if (!mounted || elegidas.isEmpty) return;
      final espacio = maxGuiasPorCarga - _borradores.length;
      final fotos = elegidas.take(espacio < 0 ? 0 : espacio).toList();
      if (fotos.length < elegidas.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Máximo $maxGuiasPorCarga guías por carga: '
              '${fotos.isEmpty ? 'no se agregó ninguna' : 'se agregaron las primeras ${fotos.length}'}. '
              'Registra estas y luego carga el resto.',
            ),
          ),
        );
      }
      if (fotos.isEmpty) return;
      setState(() {
        for (final foto in fotos) {
          final b = _Borrador(foto, _siguienteId++);
          _borradores.add(b);
          _cola.add(b);
        }
      });
      _leerSiguientes();
      // Cada tanda de fotos lleva la ubicación del momento.
      refrescarGps();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo abrir la foto: $e')));
    } finally {
      if (mounted) setState(() => _abriendoFotos = false);
    }
  }

  /// Lee con IA hasta [_lecturasSimultaneas] fotos a la vez.
  void _leerSiguientes() {
    while (_leyendoAhora < _lecturasSimultaneas && _cola.isNotEmpty) {
      final b = _cola.removeAt(0);
      if (!_borradores.contains(b)) continue;
      _leyendoAhora++;
      _leer(b).whenComplete(() {
        _leyendoAhora--;
        if (mounted) _leerSiguientes();
      });
    }
  }

  Future<void> _leer(_Borrador b) async {
    setState(() {
      b.enCola = false;
      b.leyendo = true;
    });
    try {
      final appState = context.read<AppState>();
      final datos = await _leerConReintentos(appState, b);
      if (datos == null || !mounted || !_borradores.contains(b)) return;
      setState(() {
        b.avisoLectura = null;
        void llenar(TextEditingController c, String? valor) {
          if (valor != null && c.text.trim().isEmpty) c.text = valor;
        }

        llenar(b.numero, datos.numeroGuia);
        llenar(b.destinatario, datos.destinatario);
        llenar(b.destino, datos.destino);
        llenar(b.origen, datos.origen);
        llenar(b.pedido, datos.numeroPedido);
        llenar(b.entrega, datos.numeroEntrega);
        b.comprobante ??= datos.comprobante;
        if (datos.numeroGuia == null) {
          b.avisoLectura = 'No se leyó el número: escríbelo.';
        }
      });
    } catch (e) {
      if (!mounted || !_borradores.contains(b)) return;
      setState(
        () => b.avisoLectura = 'No se pudo leer la foto: completa los datos.',
      );
    } finally {
      if (mounted && _borradores.contains(b)) {
        setState(() => b.leyendo = false);
      }
    }
  }

  /// Lee la foto; si la IA está ocupada, espera y lo vuelve a intentar
  /// (ver [_esperasIAOcupada]). null si quitaron la foto mientras tanto.
  Future<DatosGuiaLeida?> _leerConReintentos(
    AppState appState,
    _Borrador b,
  ) async {
    for (var intento = 0; ; intento++) {
      try {
        return await appState.leerGuiaConIA(b.foto);
      } on ApiException catch (e) {
        if (!e.esLimiteTemporal || intento >= _esperasIAOcupada.length) {
          rethrow;
        }
      }
      if (!mounted || !_borradores.contains(b)) return null;
      setState(() => b.avisoLectura = 'La IA está ocupada: reintentando…');
      await Future<void>.delayed(_esperasIAOcupada[intento]);
      if (!mounted || !_borradores.contains(b)) return null;
    }
  }

  void _quitar(_Borrador b) {
    setState(() {
      _borradores.remove(b);
      _cola.remove(b);
    });
    b.dispose();
  }

  /// Por qué este borrador no se puede registrar todavía (null = listo).
  String? _falta(_Borrador b, AppState appState) {
    if (b.enCola || b.leyendo) return 'Leyendo…';
    final numero = b.numero.text.trim();
    if (numero.isEmpty) return 'Falta el número de guía.';
    if (appState.registroBloqueadoHasta(numero) != null) {
      return 'Ya registraste esta guía hoy: no puedes asignártela dos veces '
          'el mismo día.';
    }
    final repetida = _borradores.any(
      (o) => o != b && o.id < b.id && o.numero.text.trim() == numero,
    );
    if (repetida) return 'Esta guía ya está en otra foto de esta lista.';
    if (b.destinatario.text.trim().isEmpty) return 'Falta el destinatario.';
    if (b.origen.text.trim().isEmpty && _sucursalAqui(appState) == null) {
      return 'Falta el punto de partida.';
    }
    if (b.destino.text.trim().isEmpty) return 'Falta el destino.';
    return null;
  }

  /// Registra a la vez todas las que están listas; las que fallan se
  /// quedan en la lista con su error.
  Future<void> _registrarListas() async {
    final appState = context.read<AppState>();
    final listas = [
      for (final b in _borradores)
        if (!b.enviando && _falta(b, appState) == null) b,
    ];
    if (listas.isEmpty || !gpsActivo) return;
    setState(() {
      _registrando = true;
      for (final b in listas) {
        b.enviando = true;
        b.error = null;
      }
    });
    final resultados = await _registrar(appState, listas);
    if (!mounted) return;
    final ok = resultados.where((r) => r).length;
    final fallidas = resultados.length - ok;
    setState(() => _registrando = false);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          [
            if (ok > 0 && widget.despachoCorte)
              'Despacho Corte $_codigoCorte · '
                  '${ok == 1 ? '1 guía' : '$ok guías'} en ruta'
            else if (ok > 0)
              ok == 1
                  ? '1 guía asignada · en ruta'
                  : '$ok guías asignadas · en ruta',
            if (fallidas > 0)
              fallidas == 1
                  ? '1 no se pudo registrar'
                  : '$fallidas no se pudieron registrar',
          ].join(' · '),
        ),
      ),
    );
    if (_borradores.isEmpty) Navigator.of(context).pop();
  }

  /// Registra todas con un solo pedido (carga masiva): las que se crean
  /// salen de la lista y las que no se quedan con su error. Devuelve si
  /// cada una se registró.
  Future<List<bool>> _registrar(
    AppState appState,
    List<_Borrador> listas,
  ) async {
    // Dentro del perímetro de una sucursal, salen de ahí.
    final sucursal = _sucursalAqui(appState)?.nombre;
    try {
      final carga = await appState.asignarLote(
        despachoCorte: widget.despachoCorte,
        codigoCorte: _codigoCorte,
        [
          for (final b in listas)
            GuiaNueva(
              numeroGuia: b.numero.text.trim(),
              tipoEntrega: b.tipo,
              origen: sucursal ?? b.origen.text.trim(),
              destino: b.destino.text.trim(),
              transportista: appState.transportistaActual,
              destinatario: b.destinatario.text.trim(),
              lat: lat!,
              lng: lng!,
              numeroPedido: b.pedido.text.trim(),
              numeroEntrega: b.entrega.text.trim(),
              comprobante: b.comprobante,
            ),
        ],
      );
      final resultados = carga.resultados;
      _codigoCorte ??= carga.despachoCorte;
      if (mounted) {
        setState(() {
          for (var i = 0; i < listas.length; i++) {
            final b = listas[i];
            final error = i < resultados.length
                ? resultados[i].error
                : 'No se pudo registrar.';
            if (error == null) {
              _borradores.remove(b);
              b.dispose();
            } else {
              b.enviando = false;
              b.error = error;
            }
          }
        });
      }
      return [
        for (var i = 0; i < listas.length; i++)
          i < resultados.length && resultados[i].guia != null,
      ];
    } catch (e) {
      final mensaje = e is ApiException ? e.mensaje : 'Error de conexión: $e';
      if (mounted) {
        setState(() {
          for (final b in listas) {
            b.enviando = false;
            b.error = mensaje;
          }
        });
      }
      return [for (final _ in listas) false];
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final listas = _borradores
        .where((b) => !b.enviando && _falta(b, appState) == null)
        .length;
    final leyendo = _borradores.where((b) => b.enCola || b.leyendo).length;
    final puedeFotografiar =
        gpsActivo && !_abriendoFotos && _borradores.length < maxGuiasPorCarga;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.despachoCorte
              ? 'Despacho Corte${_codigoCorte == null ? '' : ' · $_codigoCorte'}'
              : 'Nuevas guías · Asignación',
        ),
      ),
      bottomNavigationBar: _borradores.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (leyendo > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          leyendo == 1
                              ? 'La IA está leyendo 1 foto…'
                              : 'La IA está leyendo $leyendo fotos…',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Ipesa.textoSuave),
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: listas > 0 && gpsActivo && !_registrando
                          ? _registrarListas
                          : null,
                      icon: _registrando
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle),
                      label: Text(
                        _registrando
                            ? 'Registrando…'
                            : listas <= 1
                            ? (widget.despachoCorte
                                  ? 'Despachar guía'
                                  : 'Registrar guía')
                            : (widget.despachoCorte
                                  ? 'Despachar $listas guías'
                                  : 'Registrar $listas guías'),
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
            textoActivo: 'Ubicación disponible: se adjuntará a cada guía.',
            textoApagado: 'Obligatorio: sin GPS no se puede subir ningún registro fotográfico.',
          ),
          if (_sucursalAqui(appState) case final aqui?) ...[
            const SizedBox(height: 10),
            AvisoSucursal(
              nombre: aqui.nombre,
              detalle: 'Será el punto de partida de las guías que registres.',
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: puedeFotografiar
                      ? () => _agregarFotos(CaptureFlowScreen.tomarFoto)
                      : null,
                  icon: const Icon(Icons.camera_alt),
                  label: Text(_borradores.isEmpty ? 'Tomar foto' : 'Otra foto'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: puedeFotografiar
                      ? () => _agregarFotos(CaptureFlowScreen.elegirFotos)
                      : null,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    _borradores.isEmpty
                        ? 'Galería'
                        : 'Galería · ${_borradores.length}/$maxGuiasPorCarga',
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              gpsActivo
                  ? 'Puedes tomar varias fotos seguidas o elegir hasta '
                        '$maxGuiasPorCarga de la galería: la IA las lee '
                        'mientras sigues.'
                  : 'Activa el GPS para habilitar la cámara.',
              style: TextStyle(
                color: gpsActivo ? Ipesa.textoSuave : Colors.red,
                fontSize: 13,
              ),
            ),
          ),
          for (final b in _borradores) ...[
            const SizedBox(height: 14),
            _TarjetaBorrador(
              key: ValueKey(b.id),
              borrador: b,
              falta: _falta(b, appState),
              sucursalAqui: _sucursalAqui(appState)?.nombre,
              onCambio: () => setState(() {}),
              onQuitar: b.enviando ? null : () => _quitar(b),
            ),
          ],
        ],
      ),
    );
  }
}

class _TarjetaBorrador extends StatelessWidget {
  const _TarjetaBorrador({
    super.key,
    required this.borrador,
    required this.falta,
    required this.sucursalAqui,
    required this.onCambio,
    required this.onQuitar,
  });

  final _Borrador borrador;
  final String? falta;

  /// Si está dentro de una sucursal, ese es el punto de partida.
  final String? sucursalAqui;
  final VoidCallback onCambio;
  final VoidCallback? onQuitar;

  void _verFoto(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.memory(borrador.foto, fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = borrador;
    final ocupado = b.enCola || b.leyendo || b.enviando;
    final rojo = Colors.red[700]!;

    Widget campo(TextEditingController c, String etiqueta) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: c,
        enabled: !ocupado,
        onChanged: (_) => onCambio(),
        decoration: InputDecoration(labelText: etiqueta, isDense: true),
      ),
    );

    final String estado;
    final Color colorEstado;
    if (b.enviando) {
      estado = 'Registrando…';
      colorEstado = Ipesa.petroleo;
    } else if (b.enCola) {
      estado = 'En espera para leer…';
      colorEstado = Ipesa.textoSuave;
    } else if (b.leyendo) {
      estado = b.avisoLectura ?? 'Leyendo con IA…';
      colorEstado = Ipesa.petroleo;
    } else if (b.error != null) {
      estado = b.error!;
      colorEstado = rojo;
    } else if (falta != null) {
      estado = falta!;
      colorEstado = const Color(0xFF8A4F00);
    } else {
      estado = b.avisoLectura ?? 'Lista para registrar';
      colorEstado = const Color(0xFF1D6B41);
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _verFoto(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      b.foto,
                      width: 72,
                      height: 96,
                      fit: BoxFit.cover,
                      semanticLabel: 'Foto de la guía',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (ocupado)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: SizedBox.square(
                                dimension: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              estado,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: colorEstado,
                              ),
                            ),
                          ),
                        ],
                      ),
                      campo(b.numero, 'Número de guía'),
                      campo(b.destinatario, 'Destinatario'),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar esta foto',
                  onPressed: onQuitar,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (sucursalAqui != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.storefront_outlined,
                            size: 18,
                            color: Ipesa.turquesa,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Punto de partida: $sucursalAqui',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Ipesa.petroleo,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    campo(b.origen, 'Punto de partida'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<TipoEntrega>(
                    initialValue: b.tipo,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de entrega',
                      isDense: true,
                    ),
                    items: [
                      for (final tipo in tiposEntregaElegibles)
                        DropdownMenuItem(
                          value: tipo,
                          child: Text(tipo.etiqueta),
                        ),
                    ],
                    onChanged: ocupado
                        ? null
                        : (tipo) {
                            if (tipo != null) b.tipo = tipo;
                            onCambio();
                          },
                  ),
                  campo(b.destino, 'Destino'),
                  Row(
                    children: [
                      Expanded(child: campo(b.pedido, 'N° pedido')),
                      const SizedBox(width: 8),
                      Expanded(child: campo(b.entrega, 'N° entrega')),
                    ],
                  ),
                  if (b.comprobante case final c?)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.receipt_long_outlined,
                            size: 18,
                            color: Ipesa.petroleo,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Comprobante de agencia: ${c.resumen}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Ipesa.etiqueta,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
