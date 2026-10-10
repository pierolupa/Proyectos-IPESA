import 'dart:typed_data';

/// Guarda la imagen como archivo (en web, la descarga el navegador).
Future<void> descargarImagen(Uint8List bytes, String nombre, String tipo) =>
    Future.error(UnsupportedError('Solo disponible en el navegador.'));

/// Copia la imagen (PNG) al portapapeles, para pegarla en otra app. Se
/// llama en el mismo toque; [png] puede estar lista después.
Future<void> copiarImagen(Future<Uint8List> png) =>
    Future.error(UnsupportedError('Solo disponible en el navegador.'));

/// Si el dispositivo puede compartir archivos (menú de compartir del
/// celular: WhatsApp, correo, etc.).
bool puedeCompartirImagen(Uint8List bytes, String nombre, String tipo) => false;

/// Abre el menú de compartir del dispositivo con la imagen.
Future<void> compartirImagen(Uint8List bytes, String nombre, String tipo) =>
    Future.error(UnsupportedError('Solo disponible en el navegador.'));

/// Guarda un archivo cualquiera (en web, lo descarga el navegador).
Future<void> descargarArchivo(Uint8List bytes, String nombre, String tipo) =>
    Future.error(UnsupportedError('Solo disponible en el navegador.'));
