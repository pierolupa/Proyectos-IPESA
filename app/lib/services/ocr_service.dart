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

/// Todo lo que se puede sacar del texto reconocido en una sola pasada, para
/// no correr el OCR más de una vez por foto. Cada campo puede salir null si
/// no se encontró — todos quedan en campos editables en la pantalla, nunca
/// se confirma nada sin que el transportista lo revise.
class DatosGuiaOcr {
  const DatosGuiaOcr({
    this.numeroGuia,
    this.destinatario,
    this.destino,
    this.numeroPedido,
    this.numeroEntrega,
  });

  final String? numeroGuia;
  final String? destinatario;
  final String? destino;
  final String? numeroPedido;
  final String? numeroEntrega;
}

DatosGuiaOcr extraerDatosGuia(String textoOcr) {
  return DatosGuiaOcr(
    numeroGuia: extraerNumeroGuia(textoOcr),
    destinatario: _extraerEtiqueta(textoOcr, r'SE[ÑN]OR(?:\(ES\))?'),
    destino: _extraerEtiqueta(textoOcr, r'PUNTO\s+DE\s+LLEGADA'),
    numeroPedido: _extraerNumeroTrasEtiqueta(textoOcr, 'PEDIDO'),
    numeroEntrega: _extraerNumeroTrasEtiqueta(textoOcr, 'ENTREGA'),
  );
}

/// Las guías de IPESA son guías de remisión electrónica SUNAT, con el
/// formato estándar "serie-correlativo": una letra + 3 dígitos, guion, y
/// 4 a 8 dígitos más (ej. "T028-130133"). El número real aparece en la
/// cabecera del documento, antes de la tabla de ítems, y como el patrón es
/// bastante distintivo, el primer match en todo el texto (izquierda a
/// derecha) ya es casi siempre ese. Si no se encuentra ni con el patrón
/// exacto ni con una variante sin la letra inicial (el OCR a veces la
/// pierde), se cae a un heurístico genérico: el token alfanumérico más
/// largo con al menos 4 dígitos que no tenga forma de código de producto.
String? extraerNumeroGuia(String textoOcr) {
  final texto = textoOcr.toUpperCase();

  final patronSunat = RegExp(r'[A-Z]\s?\d{3}\s?-\s?\d{4,8}');
  final matchSunat = patronSunat.firstMatch(texto);
  if (matchSunat != null) {
    return matchSunat.group(0)!.replaceAll(RegExp(r'\s+'), '');
  }

  // El OCR a veces pierde la letra inicial de la serie; probamos el mismo
  // patrón sin ella antes de caer al heurístico genérico.
  final patronSinLetra = RegExp(r'\d{3}\s?-\s?\d{4,8}');
  final matchSinLetra = patronSinLetra.firstMatch(texto);
  if (matchSinLetra != null) {
    return matchSinLetra.group(0)!.replaceAll(RegExp(r'\s+'), '');
  }

  final patronGenerico = RegExp(r'[A-Z0-9-]*\d[A-Z0-9-]*');
  final candidatos = patronGenerico
      .allMatches(texto)
      .map((m) => m.group(0)!.trim())
      .where((s) => RegExp(r'\d').allMatches(s).length >= 4)
      // Los códigos de producto de la tabla (ej. "NA1400000158") tienen 2+
      // letras seguidas de muchos dígitos sin guion; se descartan.
      .where((s) => !RegExp(r'^[A-Z]{2,}\d{5,}$').hasMatch(s))
      .toList();
  if (candidatos.isEmpty) return null;

  candidatos.sort((a, b) => b.length.compareTo(a.length));
  return candidatos.first;
}

/// Palabras que marcan el inicio del siguiente campo en el documento — si
/// aparecen dentro de lo capturado tras una etiqueta, se corta ahí (el OCR
/// no siempre separa las "líneas" del documento con saltos de línea reales).
const _siguientesEtiquetas = [
  'RUC',
  'PUNTO DE',
  'FECHA',
  'MODALIDAD',
  'RAZÓN SOCIAL',
  'RAZON SOCIAL',
];

String? _extraerEtiqueta(String textoOcr, String patronEtiqueta) {
  final texto = textoOcr.toUpperCase();
  final match = RegExp('$patronEtiqueta\\s*:?\\s*([^\\n]{2,120})')
      .firstMatch(texto);
  if (match == null) return null;

  var valor = match.group(1)!.trim();
  for (final etiqueta in _siguientesEtiquetas) {
    final i = valor.indexOf(etiqueta);
    if (i > 0) valor = valor.substring(0, i).trim();
  }
  valor = valor.replaceAll(RegExp(r'[:;]+$'), '').trim();
  return valor.isEmpty ? null : valor;
}

String? _extraerNumeroTrasEtiqueta(String textoOcr, String etiqueta) {
  final texto = textoOcr.toUpperCase();
  final match = RegExp('$etiqueta\\s*:?\\s*(\\d{4,})').firstMatch(texto);
  return match?.group(1);
}
