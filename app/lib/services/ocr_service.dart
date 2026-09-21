import 'dart:typed_data';

import 'ocr_service_stub.dart'
    if (dart.library.js_interop) 'ocr_service_web.dart'
    as impl;

/// Corre OCR real sobre la foto y devuelve el texto reconocido completo.
/// Lanza si el lector no cargó (por ejemplo, sin conexión) o si Tesseract.js
/// falla al procesar la imagen. Solo funciona compilado para web (ver
/// ocr_service_web.dart / ocr_service_stub.dart).
Future<String> reconocerTexto(Uint8List fotoBytes) =>
    impl.reconocerTexto(fotoBytes);

/// El patrón/regex exacto de IPESA para números de guía todavía no está
/// definido (ver ARCHITECTURE.md, sección 8, "Pendientes"). Mientras tanto:
/// 1) si el texto reconocido contiene algo con forma "IPE-2026-000123"
///    (el formato que usa esta app), se usa eso;
/// 2) si no, se toma como mejor intento el token alfanumérico más largo que
///    tenga al menos 4 dígitos.
/// El resultado siempre queda en un campo editable — nunca se confirma sin
/// que el transportista lo revise.
String? extraerNumeroGuia(String textoOcr) {
  final texto = textoOcr.toUpperCase();

  final patronIpesa = RegExp(r'IPE[\s-]?\d{4}[\s-]?\d{3,8}');
  final matchIpesa = patronIpesa.firstMatch(texto);
  if (matchIpesa != null) {
    return matchIpesa.group(0)!.replaceAll(RegExp(r'\s+'), '-');
  }

  final patronGenerico = RegExp(r'[A-Z0-9-]*\d[A-Z0-9-]*');
  final candidatos = patronGenerico
      .allMatches(texto)
      .map((m) => m.group(0)!.trim())
      .where((s) => RegExp(r'\d').allMatches(s).length >= 4)
      .toList();
  if (candidatos.isEmpty) return null;

  candidatos.sort((a, b) => b.length.compareTo(a.length));
  return candidatos.first;
}
