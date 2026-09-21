import 'package:flutter_test/flutter_test.dart';
import 'package:ipesa_guias/services/ocr_service.dart';

void main() {
  group('extraerNumeroGuia', () {
    test('reconoce el formato IPE-AAAA-NNNNNN entre texto ruidoso', () {
      const texto = 'GUIA DE REMISION\nIPE-2026-000123\nFECHA 20/09/2026';
      expect(extraerNumeroGuia(texto), 'IPE-2026-000123');
    });

    test('normaliza espacios en vez de guiones dentro del patrón IPE', () {
      const texto = 'IPE 2026 000123';
      expect(extraerNumeroGuia(texto), 'IPE-2026-000123');
    });

    test('sin patrón IPE, usa el token con más dígitos como mejor intento', () {
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
