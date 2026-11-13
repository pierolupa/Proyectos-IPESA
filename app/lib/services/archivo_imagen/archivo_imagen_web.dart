import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

web.Blob _blob(Uint8List bytes, String tipo) =>
    web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: tipo));

/// Guarda la imagen como archivo (la descarga el navegador).
Future<void> descargarImagen(
  Uint8List bytes,
  String nombre,
  String tipo,
) async {
  final url = web.URL.createObjectURL(_blob(bytes, tipo));
  final enlace = web.HTMLAnchorElement()
    ..href = url
    ..download = nombre;
  web.document.body!.append(enlace);
  enlace.click();
  enlace.remove();
  // Se libera después: el navegador necesita la URL mientras descarga.
  Timer(const Duration(seconds: 10), () => web.URL.revokeObjectURL(url));
}

/// Copia la imagen al portapapeles. Los navegadores solo aceptan PNG. Se
/// escribe en el mismo toque (Safari lo exige) con una promesa que se
/// cumple cuando [png] está lista.
Future<void> copiarImagen(Future<Uint8List> png) async {
  final blob = png.then((bytes) => _blob(bytes, 'image/png')).toJS;
  final datos = JSObject()..setProperty('image/png'.toJS, blob);
  await web.window.navigator.clipboard
      .write([web.ClipboardItem(datos)].toJS)
      .toDart;
}

web.ShareData _datosCompartir(Uint8List bytes, String nombre, String tipo) =>
    web.ShareData(
      files: [
        web.File([bytes.toJS].toJS, nombre, web.FilePropertyBag(type: tipo)),
      ].toJS,
    );

/// Si el dispositivo puede compartir archivos (sobre todo celulares).
bool puedeCompartirImagen(Uint8List bytes, String nombre, String tipo) {
  final navegador = web.window.navigator as JSObject;
  if (!navegador.has('canShare')) return false;
  try {
    return web.window.navigator.canShare(_datosCompartir(bytes, nombre, tipo));
  } catch (_) {
    return false;
  }
}

/// Abre el menú de compartir del dispositivo con la imagen.
Future<void> compartirImagen(
  Uint8List bytes,
  String nombre,
  String tipo,
) async {
  await web.window.navigator.share(_datosCompartir(bytes, nombre, tipo)).toDart;
}

/// Guarda un archivo cualquiera (la descarga el navegador).
Future<void> descargarArchivo(Uint8List bytes, String nombre, String tipo) =>
    descargarImagen(bytes, nombre, tipo);
