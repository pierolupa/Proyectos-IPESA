import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/estado_guia.dart';
import '../../models/guia.dart';
import '../../models/sucursal.dart';
import '../../models/tipo_entrega.dart';
import '../../services/guias_api.dart';
import '../../services/ubicacion.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/aviso_sucursal.dart';
import '../../widgets/celebracion_jornada.dart';
import '../../widgets/gps_transportista.dart';
import 'entrega_ia_screen.dart' show claveGuia;

/// Flujo de "Entrega" y "Entrega entre sucursales" (ARCHITECTURE.md,
/// sección 4.2 y 4.3). El paso concreto depende del tipo de entrega y del
/// estado actual de la guía; el GPS sigue siendo obligatorio (se activa
/// solo si ya estaba encendido, ver [GpsTransportista]). La foto se toma
/// con la cámara o se elige de la galería.
class EntregaFlowScreen extends StatefulWidget {
  const EntregaFlowScreen({
    super.key,
    required this.guia,
    this.desdeDetalle = true,
    this.fotoInicial,
  });

  final Guia guia;

  /// La foto ya elegida (cuando la IA vio que era de esta otra tarea y el
  /// transportista pasó a entregarla).
  final Uint8List? fotoInicial;

  /// Abierta desde el detalle de la guía: al entregar se cierra también el
  /// detalle. Desde "Mis tareas" solo se cierra esta pantalla.
  final bool desdeDetalle;

  /// Los tests los reemplazan (no hay cámara ni galería ahí).
  @visibleForTesting
  static Future<Uint8List?> Function() tomarFoto = () =>
      _abrirFoto(ImageSource.camera);
  @visibleForTesting
  static Future<Uint8List?> Function() elegirFoto = () =>
      _abrirFoto(ImageSource.gallery);

  @override
  State<EntregaFlowScreen> createState() => _EntregaFlowScreenState();
}

final _picker = ImagePicker();

Future<Uint8List?> _abrirFoto(ImageSource origen) async {
  final archivo = await _picker.pickImage(
    source: origen,
    maxWidth: 1600,
    imageQuality: 80,
  );
  return archivo?.readAsBytes();
}

/// Qué dice la IA del número de guía de la foto de entrega.
enum _Verificacion { ninguna, leyendo, coincide, otraTarea, fuera, sinLeer }

class _EntregaFlowScreenState extends State<EntregaFlowScreen>
    with GpsTransportista {
  bool _tomandoFoto = false;
  Uint8List? _fotoBytes;

  // La IA lee el número de guía de la foto y lo compara con esta tarea,
  // para que no se entregue una guía con la foto de otra.
  _Verificacion _verificacion = _Verificacion.ninguna;
  LecturaEntrega? _lectura;
  Guia? _otraTarea;
  bool _entregarIgual = false;

  @override
  void initState() {
    super.initState();
    if (widget.fotoInicial case final foto?) {
      _fotoBytes = foto;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _verificarGuia(foto);
      });
    }
  }

  /// La foto es de otra guía (y no eligió entregar igual).
  bool get _guiaEquivocada =>
      !_entregarIgual &&
      (_verificacion == _Verificacion.otraTarea ||
          _verificacion == _Verificacion.fuera);

  Future<void> _verificarGuia(Uint8List foto) async {
    final g = widget.guia;
    if (g.tipoEntrega == TipoEntrega.entreSucursales) return;
    final appState = context.read<AppState>();
    final pendientes = [
      for (final t in appState.guiasDelTransportista(
        appState.transportistaActual,
      ))
        if (t.estado == EstadoGuia.enRuta) t,
    ];
    setState(() {
      _verificacion = _Verificacion.leyendo;
      _lectura = null;
      _otraTarea = null;
      _entregarIgual = false;
    });
    LecturaEntrega? lectura;
    try {
      lectura = await appState.leerNumeroGuia(
        foto,
        candidatos: {
          g.numeroGuia,
          for (final t in pendientes) t.numeroGuia,
        }.toList(),
      );
    } catch (_) {
      lectura = null;
    }
    // Cambió la foto mientras tanto: esta lectura ya no vale.
    if (!mounted || !identical(_fotoBytes, foto)) return;
    final numero = lectura?.numero;
    final clave = numero == null ? null : claveGuia(numero);
    setState(() {
      _lectura = lectura;
      if (clave == null) {
        _verificacion = _Verificacion.sinLeer;
      } else if (clave == claveGuia(g.numeroGuia)) {
        _verificacion = _Verificacion.coincide;
      } else {
        _otraTarea = pendientes
            .where((t) => claveGuia(t.numeroGuia) == clave)
            .firstOrNull;
        _verificacion = _otraTarea != null
            ? _Verificacion.otraTarea
            : _Verificacion.fuera;
      }
    });
  }

  /// Pasa a entregar la tarea de la foto, con la misma foto.
  void _entregarLaOtra() {
    final otra = _otraTarea;
    final foto = _fotoBytes;
    if (otra == null || foto == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => EntregaFlowScreen(
          guia: otra,
          desdeDetalle: false,
          fotoInicial: foto,
        ),
      ),
    );
  }

  /// Confirmó que la foto muestra la guía firmada o el comprobante.
  bool _fotoConfirmada = false;
  bool _dentroDeGeocerca = false;
  bool _verificandoPerimetro = false;
  String? _resultadoPerimetro;
  bool _enviando = false;

  bool get _fotoSimulada => _fotoBytes != null;

  Future<void> _verificarPerimetro(Sucursal sucursal) async {
    setState(() => _verificandoPerimetro = true);
    try {
      final posicion = await Ubicacion.actual();
      final distancia = Geolocator.distanceBetween(
        posicion.latitude,
        posicion.longitude,
        sucursal.lat,
        sucursal.lng,
      );
      if (!mounted) return;
      final dentro = distancia <= sucursal.radioM;
      setState(() {
        lat = posicion.latitude;
        lng = posicion.longitude;
        _dentroDeGeocerca = dentro;
        _resultadoPerimetro = dentro
            ? 'Estás dentro del perímetro de ${sucursal.nombre}.'
            : 'Estás a ${distancia.round()} m de ${sucursal.nombre}; '
                  'acércate a menos de ${sucursal.radioM.round()} m.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dentroDeGeocerca = false;
        _resultadoPerimetro = 'No se pudo leer tu ubicación: $e';
      });
    } finally {
      if (mounted) setState(() => _verificandoPerimetro = false);
    }
  }

  Future<void> _ponerFoto(Future<Uint8List?> Function() origen) async {
    setState(() => _tomandoFoto = true);
    try {
      final bytes = await origen();
      if (bytes == null || !mounted) return;
      setState(() => _fotoBytes = bytes);
      refrescarGps();
      _verificarGuia(bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo abrir la foto: $e')));
    } finally {
      if (mounted) setState(() => _tomandoFoto = false);
    }
  }

  String get _tituloAccion {
    final g = widget.guia;
    if (g.tipoEntrega == TipoEntrega.entreSucursales) {
      if (g.estado == EstadoGuia.enRuta) return 'Iniciar traslado a sucursal';
      if (g.estado == EstadoGuia.enProcesoTrasbordo) {
        return 'Registrar llegada a sucursal';
      }
      return 'Confirmar recepción en sucursal';
    }
    return 'Registrar entrega';
  }

  bool get _requiereFoto =>
      widget.guia.tipoEntrega != TipoEntrega.entreSucursales ||
      widget.guia.estado == EstadoGuia.enRuta;

  bool get _puedeConfirmar {
    if (!gpsActivo) return false;
    final g = widget.guia;
    if (g.tipoEntrega == TipoEntrega.entreSucursales) {
      if (g.estado == EstadoGuia.enProcesoTrasbordo) return _dentroDeGeocerca;
      return _fotoSimulada;
    }
    return _fotoSimulada &&
        _fotoConfirmada &&
        _verificacion != _Verificacion.leyendo &&
        !_guiaEquivocada;
  }

  Future<void> _confirmar(BuildContext context) async {
    final appState = context.read<AppState>();
    final g = widget.guia;
    EstadoGuia nuevoEstado;
    String mensaje;

    if (g.tipoEntrega == TipoEntrega.entreSucursales) {
      if (g.estado == EstadoGuia.enRuta) {
        nuevoEstado = EstadoGuia.enProcesoTrasbordo;
        mensaje = 'Traslado iniciado hacia ${g.destino}.';
      } else if (g.estado == EstadoGuia.enProcesoTrasbordo) {
        nuevoEstado = EstadoGuia.recepcionSucursal;
        mensaje = 'Llegada a ${g.destino} registrada dentro del perímetro.';
      } else {
        nuevoEstado = EstadoGuia.entregado;
        mensaje = 'Recepción en sucursal confirmada.';
      }
    } else if (g.tipoEntrega == TipoEntrega.agencia) {
      nuevoEstado = EstadoGuia.finalizado;
      mensaje = 'Entrega en agencia registrada.';
    } else if (_lectura?.comprobante != null) {
      nuevoEstado = EstadoGuia.finalizado;
      mensaje = 'Entrega en agencia registrada.';
    } else {
      // Si la IA ve en la foto el comprobante de una agencia, el servidor
      // la marca como entrega en agencia (finalizada).
      nuevoEstado = EstadoGuia.entregado;
      mensaje = 'Entrega registrada.';
    }

    setState(() => _enviando = true);
    try {
      // Se vuelve a leer el GPS al confirmar para registrar dónde se marcó
      // realmente, no dónde se encendió el GPS (si el celular tarda, sirve
      // la lectura de hace un momento).
      Position? posicion;
      try {
        posicion = await Ubicacion.actual();
      } catch (e) {
        posicion = Ubicacion.reciente;
        if (posicion == null) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo leer tu ubicación: $e')),
          );
          return;
        }
      }
      // La foto de la entrega final se guarda junto con el cambio de estado
      // para que el administrador la vea en el detalle de la guía.
      final avisoFoto = await appState.actualizarEstado(
        g.numeroGuia,
        nuevoEstado,
        lat: posicion.latitude,
        lng: posicion.longitude,
        foto: nuevoEstado.esFinal ? _fotoBytes : null,
        fechaCreacion: g.fechaCreacion,
        // Ya se leyó con el número: el servidor no lo vuelve a pedir.
        comprobante: _lectura == null ? null : (_lectura!.comprobante,),
      );
      if (!context.mounted) return;
      final actualizada = appState.guiaActual(g);
      if (nuevoEstado.esFinal &&
          (actualizada?.tieneComprobanteAgencia ?? false)) {
        mensaje =
            'Entrega en agencia registrada · '
            '${actualizada!.resumenComprobanteAgencia}';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(avisoFoto == null ? mensaje : '$mensaje\n$avisoFoto'),
        ),
      );
      // Entregada: vuelve directo a "Mis tareas" (cierra también el detalle),
      // donde la guía ya no aparece.
      final navigator = Navigator.of(context)..pop();
      if (nuevoEstado.esFinal && widget.desdeDetalle) navigator.pop();
      // Era la última pendiente: felicitación (una vez al día).
      if (nuevoEstado.esFinal) {
        final nombre = appState.transportistaActual;
        final hoy = DateTime.now();
        final suyas = appState.guiasDelTransportista(nombre);
        if (suyas.every((x) => x.estado.esCerrada)) {
          final entregadasHoy = suyas.where((x) {
            final f = x.fechaActualizacion.toLocal();
            return x.estado.esFinal &&
                f.year == hoy.year &&
                f.month == hoy.month &&
                f.day == hoy.day;
          }).length;
          await CelebracionJornada.mostrarSiCorresponde(
            navigator,
            nombre: nombre,
            entregadasHoy: entregadasHoy,
          );
        }
      }
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.mensaje)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error de conexión: $e')));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Avisa solo si la foto es de otra guía o no se pudo leer (esto último
  /// no bloquea la entrega); si coincide, no muestra nada.
  Widget _avisoVerificacion() {
    final g = widget.guia;
    final leido = _lectura?.numero ?? '';
    Widget tarjeta({
      required Color color,
      required IconData icono,
      required String titulo,
      String? detalle,
      List<Widget> acciones = const [],
    }) => Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icono, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          if (detalle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 28),
              child: Text(detalle, style: const TextStyle(fontSize: 13.5)),
            ),
          if (acciones.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 20),
              child: Wrap(spacing: 8, runSpacing: 4, children: acciones),
            ),
        ],
      ),
    );
    const naranja = Color(0xFFB45309);
    final entregarIgual = TextButton(
      onPressed: () => setState(() => _entregarIgual = true),
      child: const Text('La foto es correcta, entregar igual'),
    );
    return switch (_verificacion) {
      _Verificacion.leyendo => tarjeta(
        color: Ipesa.petroleo,
        icono: Icons.manage_search_rounded,
        titulo: 'Verificando el número de guía de la foto…',
      ),
      _Verificacion.otraTarea when !_entregarIgual => tarjeta(
        color: naranja,
        icono: Icons.warning_amber_rounded,
        titulo: 'Esta foto es de la guía $leido, no de ${g.numeroGuia}',
        detalle:
            '$leido es otra de tus tareas (${_otraTarea!.destinatario}). '
            'Cambia la foto o entrega esa guía.',
        acciones: [
          FilledButton.tonal(
            onPressed: _entregarLaOtra,
            child: Text('Entregar $leido'),
          ),
          entregarIgual,
        ],
      ),
      _Verificacion.fuera when !_entregarIgual => tarjeta(
        color: naranja,
        icono: Icons.warning_amber_rounded,
        titulo: 'Esta foto es de la guía $leido, no de ${g.numeroGuia}',
        detalle: '$leido no está en tus tareas en ruta. Revisa la foto.',
        acciones: [entregarIgual],
      ),
      _Verificacion.otraTarea || _Verificacion.fuera => tarjeta(
        color: naranja,
        icono: Icons.info_outline_rounded,
        titulo: 'Se entregará ${g.numeroGuia} con esta foto',
        detalle: 'La IA leyó $leido; confirmaste que la foto es correcta.',
      ),
      _Verificacion.sinLeer => tarjeta(
        color: Ipesa.textoSuave,
        icono: Icons.info_outline_rounded,
        titulo: 'No se pudo leer el número de guía en la foto',
        detalle: 'Revisa que sea la guía ${g.numeroGuia} antes de confirmar.',
      ),
      // Si coincide, sigue sin avisos.
      _Verificacion.ninguna ||
      _Verificacion.coincide => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.guia;
    final esPasoGeocerca =
        g.tipoEntrega == TipoEntrega.entreSucursales &&
        g.estado == EstadoGuia.enProcesoTrasbordo;
    final sucursal = context.watch<AppState>().sucursalPorNombre(g.destino);
    final puedeFoto = gpsActivo && _requiereFoto && !_tomandoFoto;

    return Scaffold(
      appBar: AppBar(title: Text(_tituloAccion)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          tarjetaGps(
            textoActivo: 'Ubicación disponible.',
            textoApagado:
                'Obligatorio para registrar cualquier evento de esta guía.',
          ),
          // Entrega final dentro de una sucursal: queda entregada ahí.
          if (gpsActivo &&
              lat != null &&
              lng != null &&
              g.tipoEntrega != TipoEntrega.entreSucursales)
            if (context.read<AppState>().sucursalEnPunto(lat!, lng!)
                case final aqui?) ...[
              const SizedBox(height: 10),
              AvisoSucursal(
                nombre: aqui.nombre,
                detalle:
                    'Si entregas aquí, quedará entregada en ${aqui.nombre}.',
              ),
            ],
          const SizedBox(height: 16),
          if (esPasoGeocerca) ...[
            _TarjetaPerimetro(
              sucursal: sucursal,
              destino: g.destino,
              gpsActivo: gpsActivo,
              verificando: _verificandoPerimetro,
              dentro: _dentroDeGeocerca,
              resultado: _resultadoPerimetro,
              onVerificar: sucursal == null
                  ? null
                  : () => _verificarPerimetro(sucursal),
            ),
          ] else ...[
            Text(
              _fotoSimulada
                  ? 'Foto de la guía firmada lista'
                  : 'Foto de la guía firmada',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: puedeFoto
                        ? () => _ponerFoto(EntregaFlowScreen.tomarFoto)
                        : null,
                    icon: _tomandoFoto
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt),
                    label: Text(_fotoSimulada ? 'Otra foto' : 'Tomar foto'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: puedeFoto
                        ? () => _ponerFoto(EntregaFlowScreen.elegirFoto)
                        : null,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galería'),
                  ),
                ),
              ],
            ),
            if (!gpsActivo)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Activa el GPS para habilitar la cámara y la galería.',
                  style: TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            if (_fotoSimulada) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: Image.memory(
                    _fotoBytes!,
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _avisoVerificacion(),
              const SizedBox(height: 4),
              if (g.tipoEntrega != TipoEntrega.entreSucursales)
                CheckboxListTile(
                  value: _fotoConfirmada,
                  onChanged: (v) =>
                      setState(() => _fotoConfirmada = v ?? false),
                  title: const Text(
                    'La foto muestra la guía firmada o el comprobante de la '
                    'agencia',
                  ),
                ),
            ],
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _puedeConfirmar && !_enviando
                ? () => _confirmar(context)
                : null,
            icon: _enviando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle),
            label: Text(_enviando ? 'Enviando...' : 'Confirmar'),
          ),
        ],
      ),
    );
  }
}

class _TarjetaPerimetro extends StatelessWidget {
  const _TarjetaPerimetro({
    required this.sucursal,
    required this.destino,
    required this.gpsActivo,
    required this.verificando,
    required this.dentro,
    required this.resultado,
    required this.onVerificar,
  });

  final Sucursal? sucursal;
  final String destino;
  final bool gpsActivo;
  final bool verificando;
  final bool dentro;
  final String? resultado;
  final VoidCallback? onVerificar;

  @override
  Widget build(BuildContext context) {
    if (sucursal == null) {
      return Card(
        color: Colors.red[50],
        child: ListTile(
          leading: const Icon(Icons.location_off, color: Colors.red),
          title: Text('$destino no tiene perímetro'),
          subtitle: const Text(
            'Pide al administrador que marque la sucursal en el mapa para '
            'poder registrar la llegada.',
          ),
        ),
      );
    }
    return Card(
      color: dentro ? Ipesa.menta : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: Ipesa.petroleo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Llegada a ${sucursal!.nombre} '
                    '(perímetro de ${sucursal!.radioM.round()} m)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: gpsActivo && !verificando ? onVerificar : null,
              icon: verificando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: const Text('Verificar que estoy en la sucursal'),
            ),
            if (resultado != null) ...[
              const SizedBox(height: 8),
              Text(
                resultado!,
                style: TextStyle(
                  color: dentro ? Colors.green[800] : Colors.red,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
