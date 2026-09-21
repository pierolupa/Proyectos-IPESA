import 'dart:typed_data';

/// Implementación de respaldo para plataformas sin `dart:js_interop` (la
/// VM de Dart, usada por `flutter test`/`flutter analyze`). La app solo se
/// despliega como Flutter Web, así que esto nunca se ejecuta de verdad —
/// ver ocr_service.dart.
Future<String> reconocerTexto(Uint8List fotoBytes) {
  throw UnsupportedError('El OCR solo está disponible en la versión web de la app.');
}
