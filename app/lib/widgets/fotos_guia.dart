import 'package:flutter/material.dart';

import '../models/guia.dart';
import '../models/tipo_entrega.dart';
import '../services/guias_api.dart';
import '../theme.dart';

/// Fotos guardadas de una guía (la de la asignación y la de la entrega),
/// para el administrador. Tocar una la abre en grande con zoom.
class FotosGuia extends StatelessWidget {
  const FotosGuia({super.key, required this.guia});

  final Guia guia;

  String get _etiquetaEntrega => switch (guia.tipoEntrega) {
    TipoEntrega.clienteFinal => 'Guía firmada (entrega)',
    TipoEntrega.agencia => 'Comprobante de agencia',
    TipoEntrega.entreSucursales => 'Guía al iniciar el traslado',
  };

  @override
  Widget build(BuildContext context) {
    final fotos = [
      if (guia.tieneFotoEntrega) (_etiquetaEntrega, TipoFoto.entrega),
      if (guia.tieneFotoGuia) ('Foto al asignar la guía', TipoFoto.guia),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fotos', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        if (fotos.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Ipesa.borde),
              borderRadius: BorderRadius.circular(Ipesa.radioCampo),
            ),
            child: const Row(
              children: [
                Icon(Icons.no_photography_outlined, color: Ipesa.textoSuave),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sin fotos guardadas. Las guías registradas antes de esta '
                    'versión de la app no tienen foto.',
                    style: TextStyle(color: Ipesa.textoSuave),
                  ),
                ),
              ],
            ),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (etiqueta, tipo) in fotos)
                _Miniatura(
                  etiqueta: etiqueta,
                  url: urlFoto(guia, tipo),
                  titulo: '$etiqueta · ${guia.numeroGuia}',
                ),
            ],
          ),
      ],
    );
  }
}

class _Miniatura extends StatelessWidget {
  const _Miniatura({
    required this.etiqueta,
    required this.url,
    required this.titulo,
  });

  final String etiqueta;
  final String url;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
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
              SizedBox(height: 160, child: _Imagen(url: url)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        etiqueta,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Ipesa.texto,
                        ),
                      ),
                    ),
                    const Icon(Icons.zoom_in, size: 20, color: Ipesa.turquesa),
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
