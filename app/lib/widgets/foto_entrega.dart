import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/estado_guia.dart';
import '../models/guia.dart';
import '../services/archivo_imagen.dart';
import '../services/guias_api.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Foto de la entrega al cliente (la guía firmada), para el administrador.
/// Tocarla la abre en grande con zoom. Si no hay foto, explica por qué.
class FotoEntrega extends StatefulWidget {
  const FotoEntrega({super.key, required this.guia});

  final Guia guia;

  @override
  State<FotoEntrega> createState() => _FotoEntregaState();
}

class _FotoEntregaState extends State<FotoEntrega> {
  Future<bool?>? _configurado;

  @override
  void initState() {
    super.initState();
    // Solo hace falta saberlo cuando una entrega cerrada no tiene foto.
    if (!widget.guia.tieneFotoEntrega && widget.guia.estado.esFinal) {
      _configurado = context.read<AppState>().almacenamientoFotosConfigurado();
    }
  }

  @override
  Widget build(BuildContext context) {
    final guia = widget.guia;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Foto de la entrega',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        if (guia.tieneFotoEntrega)
          _Miniatura(guia: guia)
        else if (guia.estado == EstadoGuia.rechazado)
          const _Aviso(
            icono: Icons.no_photography_outlined,
            texto: 'Tarea rechazada: no tiene foto de entrega.',
          )
        else if (!guia.estado.esFinal)
          const _Aviso(
            icono: Icons.photo_camera_outlined,
            texto:
                'Se guardará cuando el transportista entregue la guía al '
                'cliente.',
          )
        else
          FutureBuilder<bool?>(
            future: _configurado,
            builder: (context, snapshot) => snapshot.data == false
                ? const _Aviso(
                    icono: Icons.warning_amber_rounded,
                    alerta: true,
                    texto:
                        'Las fotos NO se están guardando: falta conectar '
                        'Google Drive (o Vercel Blob) al servidor '
                        'proyectos-ipesa. Pasos en backend/README.md, '
                        'sección "Fotos".',
                  )
                : const _Aviso(
                    icono: Icons.no_photography_outlined,
                    texto: 'Esta entrega no tiene foto guardada.',
                  ),
          ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.texto, this.alerta = false});

  final IconData icono;
  final String texto;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final color = alerta ? const Color(0xFF8A4F00) : Ipesa.textoSuave;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: alerta ? const Color(0xFFFBF0DD) : Colors.white,
        border: Border.all(
          color: alerta ? const Color(0xFFE9C98F) : Ipesa.borde,
        ),
        borderRadius: BorderRadius.circular(Ipesa.radioCampo),
      ),
      child: Row(
        children: [
          Icon(icono, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(texto, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}

/// La foto: tocarla la abre en grande. Debajo, Descargar, Copiar (para
/// pegarla en WhatsApp, un correo…) y, en celulares, Compartir. Se baja
/// una sola vez y se reutiliza para todo.
class _Miniatura extends StatefulWidget {
  const _Miniatura({required this.guia});

  final Guia guia;

  @override
  State<_Miniatura> createState() => _MiniaturaState();
}

class _MiniaturaState extends State<_Miniatura> {
  late Future<Uint8List> _bytes = context.read<AppState>().fotoEntrega(
    widget.guia,
  );

  /// Qué pasó con el último botón ("Foto copiada…"). Se muestra junto a
  /// los botones (una SnackBar quedaría tapada por la hoja o el visor).
  final _mensaje = ValueNotifier<String?>(null);
  Timer? _borrarMensaje;

  String get _titulo => 'Entrega · ${widget.guia.numeroGuia}';

  @override
  void dispose() {
    _borrarMensaje?.cancel();
    _mensaje.dispose();
    super.dispose();
  }

  String _nombre(String tipo) {
    final extension = switch (tipo) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final numero = widget.guia.numeroGuia.replaceAll(RegExp(r'[^\w-]'), '_');
    return 'IPESA_entrega_$numero.$extension';
  }

  void _avisar(String texto) {
    if (!mounted) return;
    _mensaje.value = texto;
    _borrarMensaje?.cancel();
    _borrarMensaje = Timer(const Duration(seconds: 4), () {
      if (mounted) _mensaje.value = null;
    });
  }

  Future<void> _descargar() async {
    try {
      final bytes = await _bytes;
      final tipo = tipoImagen(bytes);
      await descargarImagen(bytes, _nombre(tipo), tipo);
      _avisar('Foto descargada.');
    } catch (_) {
      _avisar('No se pudo descargar la foto.');
    }
  }

  Future<void> _copiar() async {
    try {
      // Se llama de inmediato (dentro del toque): algunos navegadores solo
      // dejan copiar en ese momento; la imagen se entrega cuando está lista.
      await copiarImagen(_bytes.then(_comoPng));
      _avisar('Foto copiada: pégala donde quieras.');
    } catch (_) {
      _avisar(
        'Este navegador no deja copiar imágenes. Usa "Descargar" y '
        'adjúntala desde tus archivos.',
      );
    }
  }

  Future<void> _compartir(Uint8List bytes) async {
    final tipo = tipoImagen(bytes);
    try {
      await compartirImagen(bytes, _nombre(tipo), tipo);
    } catch (_) {
      // Cancelar el menú de compartir también llega aquí: no se avisa.
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Ipesa.borde),
          borderRadius: BorderRadius.circular(Ipesa.radioCampo),
        ),
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder<Uint8List>(
          future: _bytes,
          builder: (context, foto) {
            final bytes = foto.data;
            final lista = bytes != null;
            final puedeCompartir =
                lista &&
                puedeCompartirImagen(
                  bytes,
                  _nombre(tipoImagen(bytes)),
                  tipoImagen(bytes),
                );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: lista ? () => _abrir(context, bytes) : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 200,
                        child: _Imagen(
                          foto: foto,
                          onReintentar: () => setState(
                            () => _bytes = context.read<AppState>().fotoEntrega(
                              widget.guia,
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Ver foto completa',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Ipesa.texto,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.zoom_in,
                              size: 20,
                              color: Ipesa.turquesa,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: _Acciones(
                    onDescargar: lista ? _descargar : null,
                    onCopiar: lista ? _copiar : null,
                    onCompartir: puedeCompartir
                        ? () => _compartir(bytes)
                        : null,
                  ),
                ),
                _Mensaje(mensaje: _mensaje),
              ],
            );
          },
        ),
      ),
    );
  }

  void _abrir(BuildContext context, Uint8List bytes) {
    final puedeCompartir = puedeCompartirImagen(
      bytes,
      _nombre(tipoImagen(bytes)),
      tipoImagen(bytes),
    );
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 6,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  semanticLabel: 'Foto de la entrega',
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 16,
              right: 8,
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _titulo,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      color: Colors.white,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                child: Center(
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Acciones(
                            onDescargar: _descargar,
                            onCopiar: _copiar,
                            onCompartir: puedeCompartir
                                ? () => _compartir(bytes)
                                : null,
                          ),
                          _Mensaje(mensaje: _mensaje),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.mensaje});

  final ValueListenable<String?> mensaje;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: mensaje,
      builder: (context, texto, _) => texto == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(
                texto,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Ipesa.turquesa,
                ),
              ),
            ),
    );
  }
}

class _Acciones extends StatelessWidget {
  const _Acciones({
    required this.onDescargar,
    required this.onCopiar,
    required this.onCompartir,
  });

  final VoidCallback? onDescargar;
  final VoidCallback? onCopiar;

  /// null = el dispositivo no puede compartir archivos: no se muestra.
  final VoidCallback? onCompartir;

  @override
  Widget build(BuildContext context) {
    Widget boton(String texto, IconData icono, VoidCallback? onPressed) =>
        TextButton.icon(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: Ipesa.petroleo,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 44),
          ),
          icon: Icon(icono, size: 18),
          label: Text(texto),
        );

    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        boton('Descargar', Icons.download_outlined, onDescargar),
        boton('Copiar', Icons.copy_outlined, onCopiar),
        if (onCompartir != null)
          boton('Compartir', Icons.share_outlined, onCompartir),
      ],
    );
  }
}

/// La foto ya bajada (o cargando / con error).
class _Imagen extends StatelessWidget {
  const _Imagen({required this.foto, required this.onReintentar});

  final AsyncSnapshot<Uint8List> foto;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    if (foto.hasData) {
      return Image.memory(
        foto.data!,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        semanticLabel: 'Foto de la entrega',
        errorBuilder: (context, error, stack) => const _SinFoto(),
      );
    }
    if (foto.hasError) {
      return ColoredBox(
        color: Ipesa.mapaFondo,
        child: Center(
          child: TextButton.icon(
            onPressed: onReintentar,
            icon: const Icon(Icons.refresh),
            label: const Text('No se pudo cargar. Reintentar'),
          ),
        ),
      );
    }
    return const ColoredBox(
      color: Ipesa.mapaFondo,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _SinFoto extends StatelessWidget {
  const _SinFoto();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Ipesa.mapaFondo,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'No se pudo cargar la foto.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Ipesa.textoSuave),
          ),
        ),
      ),
    );
  }
}

/// PNG de la imagen: los navegadores solo copian PNG al portapapeles.
Future<Uint8List> _comoPng(Uint8List bytes) async {
  if (tipoImagen(bytes) == 'image/png') return bytes;
  final codec = await ui.instantiateImageCodec(bytes);
  final cuadro = await codec.getNextFrame();
  final png = await cuadro.image.toByteData(format: ui.ImageByteFormat.png);
  cuadro.image.dispose();
  codec.dispose();
  return png!.buffer.asUint8List();
}
