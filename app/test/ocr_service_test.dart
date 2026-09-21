import 'package:flutter_test/flutter_test.dart';
import 'package:ipesa_guias/services/ocr_service.dart';

void main() {
  group('extraerNumeroGuia', () {
    test('reconoce el formato SUNAT serie-correlativo entre texto ruidoso',
        () {
      const texto =
          'GUIA DE REMISION ELECTRONICA - REMITENTE\nT028-130133\nRUC: 20101639275';
      expect(extraerNumeroGuia(texto), 'T028-130133');
    });

    test('no confunde el número de guía con un RUC de 11 dígitos', () {
      const texto = 'RUC: 20601771641\nT028-130133\nRUC: 20613317997';
      expect(extraerNumeroGuia(texto), 'T028-130133');
    });

    test('quita espacios sueltos que a veces mete el OCR', () {
      const texto = 'T028 - 130133';
      expect(extraerNumeroGuia(texto), 'T028-130133');
    });

    test('sin el patrón SUNAT, usa el token con más dígitos como mejor intento',
        () {
      const texto = 'GUIA DE REMISION N 00123456 FECHA 20/09/2026';
      expect(extraerNumeroGuia(texto), '00123456');
    });

    test('ignora tokens con menos de 4 dígitos', () {
      const texto = 'PISO 3 OF 12 LIMA PERU';
      expect(extraerNumeroGuia(texto), isNull);
    });

    test('texto vacío no encuentra nada', () {
      expect(extraerNumeroGuia(''), isNull);
    });
  });
}
