import 'dart:js_interop';
import 'dart:typed_data';

/// `window.ipesaReconocerGuia` (definida en `web/ocr.js`), que a su vez usa
/// Tesseract.js cargado en `web/index.html`. Solo se importa cuando se
/// compila para web — ver ocr_service.dart.
@JS('ipesaReconocerGuia')
external JSPromise<JSString?> _reconocerGuiaJs(JSUint8Array bytes);

Future<String> reconocerTexto(Uint8List fotoBytes) async {
  final resultado = await _reconocerGuiaJs(fotoBytes.toJS).toDart;
  return resultado?.toDart ?? '';
}
