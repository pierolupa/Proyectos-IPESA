import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/estado_guia.dart';
import '../models/guia.dart';
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
          _Miniatura(
            url: urlFotoEntrega(guia),
            titulo: 'Entrega · ${guia.numeroGuia}',
          )
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

class _Miniatura extends StatelessWidget {
  const _Miniatura({required this.url, required this.titulo});

  final String url;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Ipesa.borde),
          borderRadius: BorderRadius.circular(Ipesa.radioCampo),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _abrir(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 200, child: _Imagen(url: url)),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
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
                    Icon(Icons.zoom_in, size: 20, color: Ipesa.turquesa),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _abrir(BuildContext context) {
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
                child: _Imagen(url: url, ajuste: BoxFit.contain),
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
                        titulo,
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
          ],
        ),
      ),
    );
  }
}

class _Imagen extends StatelessWidget {
  const _Imagen({required this.url, this.ajuste = BoxFit.cover});

  final String url;
  final BoxFit ajuste;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: ajuste,
      alignment: Alignment.topCenter,
      loadingBuilder: (context, child, progreso) => progreso == null
          ? child
          : const ColoredBox(
              color: Ipesa.mapaFondo,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
      errorBuilder: (context, error, stack) => const ColoredBox(
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
      ),
    );
  }
}
