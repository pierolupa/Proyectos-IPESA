import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/estado_guia.dart';
import 'package:ipesa_guias/models/guia.dart';
import 'package:ipesa_guias/screens/admin/admin_guia_edit_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

Map<String, dynamic> _guiaJson(Map<String, dynamic> extra) => {
  'numero_guia': 'T001-94609',
  'estado': 'en_ruta',
  'tipo_entrega': 'cliente_final',
  'origen': 'Almacén Callao',
  'destino': 'Jr. San Lorenzo 330',
  'transportista': 'Juan Perez',
  'destinatario': 'GENUS SVC S.A.C.',
  'fecha_actualizacion': '2026-09-26T21:16:00.000Z',
  'corregido_por_admin': false,
  ...extra,
};

Future<void> _abrirDetalle(
  WidgetTester tester,
  Map<String, dynamic> guia,
) async {
  final client = MockClient(
    (request) async => http.Response(jsonEncode([guia]), 200),
  );
  final appState = AppState(api: GuiasApi(client: client));
  await appState.cargarGuias();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: appState,
      child: const MaterialApp(
        home: AdminGuiaEditScreen(numeroGuia: 'T001-94609'),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'la entrega manda la foto y devuelve el aviso si no se guardó',
    () async {
      late Map<String, dynamic> enviado;
      final client = MockClient((request) async {
        enviado = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            ..._guiaJson({'estado': 'entregado'}),
            'aviso_foto': 'La foto no se pudo guardar: sin almacenamiento',
          }),
          200,
        );
      });
      final foto = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

      final (guia, aviso) = await GuiasApi(client: client).actualizarEstado(
        'T001-94609',
        EstadoGuia.entregado,
        lat: -12.1,
        lng: -77.0,
        foto: foto,
      );

      final fotoJson = enviado['foto'] as Map<String, dynamic>;
      expect(base64Decode(fotoJson['base64'] as String), foto);
      expect(fotoJson['mediaType'], 'image/jpeg');
      expect(guia.estado, EstadoGuia.entregado);
      expect(aviso, contains('sin almacenamiento'));
    },
  );

  test('detecta PNG por sus primeros bytes', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);
    expect(tipoImagen(png), 'image/png');
  });

  test('la URL de la foto pasa por el backend y cambia si la foto cambia', () {
    final a = Guia.fromJson(
      _guiaJson({'foto_entrega_url': 'https://blob/a.jpg'}),
    );
    final b = Guia.fromJson(
      _guiaJson({'foto_entrega_url': 'https://blob/b.jpg'}),
    );
    expect(
      urlFoto(a, TipoFoto.entrega),
      startsWith('$apiBaseUrl/guias/T001-94609/foto/entrega?v='),
    );
    expect(urlFoto(a, TipoFoto.entrega), isNot(urlFoto(b, TipoFoto.entrega)));
  });

  testWidgets('El admin ve las fotos de la guía', (tester) async {
    await _abrirDetalle(
      tester,
      _guiaJson({
        'estado': 'entregado',
        'foto_guia_url': 'https://blob/guia.jpg',
        'foto_entrega_url': 'https://blob/entrega.jpg',
      }),
    );

    expect(find.text('Fotos'), findsOneWidget);
    expect(find.text('Guía firmada (entrega)'), findsOneWidget);
    expect(find.text('Foto al asignar la guía'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('Sin fotos, el admin ve un aviso claro', (tester) async {
    await _abrirDetalle(tester, _guiaJson({}));

    expect(find.textContaining('Sin fotos guardadas'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
