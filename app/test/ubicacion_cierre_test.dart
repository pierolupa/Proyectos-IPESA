import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/guia.dart';
import 'package:ipesa_guias/screens/admin/admin_guia_edit_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';
import 'package:ipesa_guias/widgets/mapa_ubicacion.dart';

Map<String, dynamic> _guiaJson(Map<String, dynamic> extra) => {
  'numero_guia': 'T028-130133',
  'estado': 'entregado',
  'tipo_entrega': 'cliente_final',
  'origen': 'Almacén Callao',
  'destino': 'Jr. San Lorenzo 330',
  'transportista': 'Juan Pérez',
  'destinatario': 'GENUS SVC S.A.C.',
  'fecha_actualizacion': '2026-09-01T15:30:00.000Z',
  'corregido_por_admin': false,
  ...extra,
};

Future<void> _abrirDetalleAdmin(
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
        home: AdminGuiaEditScreen(numeroGuia: 'T028-130133'),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('lee coordenadas con coma decimal como las devuelve Sheets', () {
    final guia = Guia.fromJson(
      _guiaJson({
        'cierre_lat': '-12,0654',
        'cierre_lng': '-77,0312',
        'fecha_cierre': '2026-09-01T15:30:00.000Z',
      }),
    );
    expect(guia.cierreLat, -12.0654);
    expect(guia.cierreLng, -77.0312);
    expect(guia.tieneUbicacionCierre, isTrue);
    expect(guia.fechaCierre, DateTime.utc(2026, 9, 1, 15, 30));
  });

  test('una guía sin cierre no tiene ubicación de cierre', () {
    final guia = Guia.fromJson(
      _guiaJson({'cierre_lat': '', 'cierre_lng': '', 'fecha_cierre': ''}),
    );
    expect(guia.tieneUbicacionCierre, isFalse);
    expect(guia.fechaCierre, isNull);
  });

  testWidgets('El admin ve dónde se cerró la tarea en un mapa', (
    tester,
  ) async {
    await _abrirDetalleAdmin(
      tester,
      _guiaJson({
        'cierre_lat': -12.0654,
        'cierre_lng': -77.0312,
        'fecha_cierre': '2026-09-01T15:30:00.000Z',
      }),
    );

    expect(find.text('Dónde se cerró la tarea'), findsOneWidget);
    expect(find.textContaining('Cerrada por Juan Pérez'), findsOneWidget);
    expect(find.textContaining('-12.065400, -77.031200'), findsOneWidget);
    expect(find.byType(MapaUbicacion), findsOneWidget);
  });

  testWidgets('Un cierre manual del admin avisa que no hay ubicación', (
    tester,
  ) async {
    await _abrirDetalleAdmin(tester, _guiaJson({}));

    expect(find.textContaining('Sin ubicación de cierre'), findsOneWidget);
    expect(find.byType(MapaUbicacion), findsNothing);
  });
}
