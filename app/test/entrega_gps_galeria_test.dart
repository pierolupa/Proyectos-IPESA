import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/guia.dart';
import 'package:ipesa_guias/screens/transportista/entrega_flow_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/services/ubicacion.dart';
import 'package:ipesa_guias/state/app_state.dart';

// PNG de 1×1 válido (se muestra la vista previa).
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

final _json = {
  'numero_guia': 'T500',
  'estado': 'en_ruta',
  'tipo_entrega': 'cliente_final',
  'origen': 'Almacén Callao',
  'destino': 'Av. Principal 123',
  'transportista': 'Juan Pérez',
  'destinatario': 'Cliente T500',
  'fecha_creacion': DateTime.now().toUtc().toIso8601String(),
  'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
  'corregido_por_admin': false,
};

void main() {
  late List<Map<String, dynamic>> cambios;
  late int lecturasGps;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'sesion_nombre': 'Juan Pérez',
      'sesion_rol': 'transportista',
    });
    cambios = [];
    lecturasGps = 0;
    Ubicacion.olvidarUltima();
    Ubicacion.permisoConcedido = () async => true;
    Ubicacion.leer = () async {
      lecturasGps++;
      return Position(
        latitude: -12.05,
        longitude: -77.04,
        timestamp: DateTime.now(),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    };
    EntregaFlowScreen.tomarFoto = () async => null;
    EntregaFlowScreen.elegirFoto = () async => Uint8List.fromList(_png);
  });

  Future<void> abrir(WidgetTester tester) async {
    final client = MockClient((request) async {
      final ruta = request.url.path;
      if (ruta.endsWith('/sucursales')) return http.Response('[]', 200);
      if (request.method == 'PATCH' && ruta.endsWith('/estado')) {
        final cuerpo = jsonDecode(request.body) as Map<String, dynamic>;
        cambios.add(cuerpo);
        return http.Response(
          jsonEncode({..._json, 'estado': cuerpo['estado']}),
          200,
        );
      }
      return http.Response(jsonEncode([_json]), 200);
    });
    final appState = AppState(api: GuiasApi(client: client));
    await appState.restaurarSesion();
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                EntregaFlowScreen(guia: Guia.fromJson(_json)),
                          ),
                        ),
                        child: const Text('Entregar'),
                      ),
                    ),
                  ),
                ),
                child: const Text('Detalle'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Detalle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entregar'));
    await tester.pumpAndSettle();
  }

  testWidgets('Con permiso, el GPS ya está activo y la foto sale de la '
      'galería', (tester) async {
    await abrir(tester);

    // No hubo que tocar el interruptor.
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );

    await tester.tap(find.text('Galería'));
    await tester.pumpAndSettle();
    expect(find.text('Foto de la guía firmada lista'), findsOneWidget);

    await tester.tap(find.text('Firma del cliente capturada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(cambios, hasLength(1));
    expect(cambios.single['estado'], 'entregado');
    expect(cambios.single['geo'], {'lat': -12.05, 'lng': -77.04});
    expect(cambios.single['foto'], isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sin permiso ni recuerdo, el GPS espera al transportista', (
    tester,
  ) async {
    Ubicacion.permisoConcedido = () async => false;
    await abrir(tester);

    expect(lecturasGps, 0);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.ancestor(
              of: find.text('Galería'),
              matching: find.byWidgetPredicate((w) => w is OutlinedButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('GPS activo'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });
}
