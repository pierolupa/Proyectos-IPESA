import 'package:flutter_test/flutter_test.dart';
import 'package:ipesa_guias/services/ocr_service.dart';

const _textoGuiaReal = '''
IPESA S.A.C.
RUC: 20101639275
GUIA DE REMISION ELECTRONICA - REMITENTE
T028-130133

Datos del Destinatario
Señor(es) : GENUS SVC S.A.C.
RUC : 20601771641
Punto de Partida : FND. LA ESTRELLA AV. ALFONSO UGARTE 228 LOTE 44, ATE - LIMA - LIMA
Punto de Llegada : JR. SAN LORENZO 330, LA VICTORIA, LA VICTORIA - LIMA - LIMA
Fecha y hora de Emision: 08-09-2026 19:39:48

Datos adicionales
Documentos : Orden de Compra:6000129235;Pedido:0188173910;N Bultos:1;Entrega:0080216544

Item Codigo Descripcion UM Cantidad
1 NA1400000158 TYVEK TALLA M EA 2
2 NA1400000357 JGO. LLAVE RUEDAS RETROEXCAVADORA EA 1
''';

void main() {
  group('extraerDatosGuia', () {
    test('extrae los 5 campos de una guía real con ruido alrededor', () {
      final datos = extraerDatosGuia(_textoGuiaReal);
      expect(datos.numeroGuia, 'T028-130133');
      expect(datos.destinatario, 'GENUS SVC S.A.C.');
      expect(
        datos.destino,
        'JR. SAN LORENZO 330, LA VICTORIA, LA VICTORIA - LIMA - LIMA',
      );
      expect(datos.numeroPedido, '0188173910');
      expect(datos.numeroEntrega, '0080216544');
    });

    test('tolera separadores raros que a veces mete el OCR entre etiqueta y valor',
        () {
      const texto = 'Señor(es)  GENUS SVC S.A.C.\nPedido~0188173910';
      final datos = extraerDatosGuia(texto);
      expect(datos.destinatario, 'GENUS SVC S.A.C.');
      expect(datos.numeroPedido, '0188173910');
    });
  });

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

    test('no confunde el número de guía con códigos de producto de la tabla',
        () {
      const texto = 'NA1400000158 TYVEK TALLA M NA1400000357 JGO LLAVE';
      expect(extraerNumeroGuia(texto), isNull);
    });

    test(
        'si el patrón SUNAT no aparece para nada, no cae de rebote en un RUC de 11 dígitos',
        () {
      const texto = 'RUC: 20101639275\nGUIA DE REMISION ELECTRONICA';
      expect(extraerNumeroGuia(texto), isNull);
    });

    test('prioriza el patrón SUNAT sobre los códigos de producto', () {
      const texto =
          'T028-130133\nNA1400000158 TYVEK TALLA M NA1400000357 JGO LLAVE';
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
