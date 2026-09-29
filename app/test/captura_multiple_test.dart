import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/screens/transportista/capture_flow_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/services/ubicacion.dart';
import 'package:ipesa_guias/state/app_state.dart';

// PNG de 1×1 válido (la tarjeta muestra la miniatura).
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Map<String, dynamic> _guia(String numero, DateTime creada) => {
  'numero_guia': numero,
  'estado': 'en_ruta',
  'tipo_entrega': 'cliente_final',
  'origen': 'Almacén Callao',
  'destino': 'Av. Principal 123',
  'transportista': 'Juan Pérez',
  'destinatario': 'Cliente $numero',
  'fecha_creacion': creada.toUtc().toIso8601String(),
  'fecha_actualizacion': creada.toUtc().toIso8601String(),
  'corregido_por_admin': false,
};

void main() {
  late List<String> leidas;
  late List<String> registradas;
  late List<String> origenes;
  var sucursales = '[]';

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'sesion_nombre': 'Juan Pérez',
      'sesion_rol': 'transportista',
    });
    leidas = ['T200', 'T201', 'T100'];
    registradas = [];
    origenes = [];
    sucursales = '[]';
    Ubicacion.olvidarUltima();
    Ubicacion.permisoConcedido = () async => false;
    Ubicacion.leer = () async => Position(
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
    CaptureFlowScreen.elegirFotos = () async => [
      Uint8List.fromList(_png),
      Uint8List.fromList(_png),
      Uint8List.fromList(_png),
    ];
  });

  Future<void> abrir(WidgetTester tester) async {
    // T100 se registró hace 30 min: no se puede registrar otra vez aún.
    final hace30 = DateTime.now().subtract(const Duration(minutes: 30));
    final client = MockClient((request) async {
      final ruta = request.url.path;
      if (ruta.endsWith('/sucursales')) return http.Response(sucursales, 200);
      if (ruta.endsWith('/ocr/leer-guia')) {
        final numero = leidas.removeAt(0);
        return http.Response(
          jsonEncode({
            'numero_guia': numero,
            'destinatario': 'Cliente $numero',
            'destino': 'Av. Lima 100',
            'origen': 'Almacén Lurín',
          }),
          200,
        );
      }
      if (request.method == 'POST' && ruta.endsWith('/guias')) {
        final cuerpo = jsonDecode(request.body) as Map<String, dynamic>;
        final numero = cuerpo['numeroGuia'] as String;
        registradas.add(numero);
        origenes.add(cuerpo['origen'] as String);
        return http.Response(jsonEncode(_guia(numero, DateTime.now())), 201);
      }
      return http.Response(jsonEncode([_guia('T100', hace30)]), 200);
    });
    final appState = AppState(api: GuiasApi(client: client));
    await appState.restaurarSesion();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(home: CaptureFlowScreen()),
      ),
    );
  }

  testWidgets('Varias fotos se leen a la vez y se registran juntas', (
    tester,
  ) async {
    await abrir(tester);

    await tester.tap(find.text('GPS activo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galería'));
    await tester.pumpAndSettle();

    // Las tres fotos se leyeron (en paralelo) y quedaron como tarjetas.
    expect(leidas, isEmpty);
    expect(find.text('T200'), findsOneWidget);
    expect(find.text('T201'), findsOneWidget);
    expect(find.text('T100'), findsOneWidget);
    // T100 se registró hace 30 min: esa espera; las otras dos, listas.
    expect(find.textContaining('ya se registró hace poco'), findsOneWidget);
    expect(find.text('Registrar 2 guías'), findsOneWidget);

    await tester.tap(find.text('Registrar 2 guías'));
    await tester.pumpAndSettle();

    expect(registradas, unorderedEquals(['T200', 'T201']));
    expect(find.text('2 guías asignadas · en ruta'), findsOneWidget);
    // Queda solo la que no se pudo registrar.
    expect(find.text('T100'), findsOneWidget);
    expect(find.text('T200'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Una guía repetida en la misma tanda no se registra dos veces', (
    tester,
  ) async {
    leidas = ['T300', 'T300', 'T301'];
    await abrir(tester);

    await tester.tap(find.text('GPS activo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galería'));
    await tester.pumpAndSettle();

    expect(
      find.text('Esta guía ya está en otra foto de esta lista.'),
      findsOneWidget,
    );
    expect(find.text('Registrar 2 guías'), findsOneWidget);
  });

  test('La misma guía se puede registrar de nuevo pasadas 2 horas', () async {
    final ahora = DateTime(2026, 9, 28, 15);
    final client = MockClient(
      (request) async => request.url.path.endsWith('/sucursales')
          ? http.Response('[]', 200)
          : http.Response(
              jsonEncode([
                _guia('T1', ahora.subtract(const Duration(hours: 1))),
                _guia('T2', ahora.subtract(const Duration(hours: 3))),
              ]),
              200,
            ),
    );
    final appState = AppState(api: GuiasApi(client: client));
    await appState.cargarGuias();

    expect(
      appState.registroBloqueadoHasta('T1', ahora: ahora),
      ahora.add(const Duration(hours: 1)).toUtc(),
    );
    expect(appState.registroBloqueadoHasta('T2', ahora: ahora), isNull);
    expect(appState.registroBloqueadoHasta('T9', ahora: ahora), isNull);
  });

  testWidgets('El GPS se activa solo si el celular ya dio permiso', (
    tester,
  ) async {
    Ubicacion.permisoConcedido = () async => true;
    await abrir(tester);
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    // Sin tocar el interruptor ya se puede elegir fotos.
    await tester.tap(find.text('Galería'));
    await tester.pumpAndSettle();
    expect(find.text('T200'), findsOneWidget);
  });

  testWidgets('Encendido una vez, queda encendido la próxima vez', (
    tester,
  ) async {
    await abrir(tester);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await tester.tap(find.text('GPS activo'));
    await tester.pumpAndSettle();

    // Vuelve a entrar: ya no hay que activarlo.
    await tester.pumpWidget(const SizedBox());
    await abrir(tester);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );

    // Si lo apaga, se respeta y no se prende solo.
    await tester.tap(find.text('GPS activo'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await abrir(tester);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
  });

  testWidgets('Dentro de una sucursal, sale de ahí', (tester) async {
    // El GPS de prueba está en -12.05, -77.04: dentro de este perímetro.
    sucursales = jsonEncode([
      {
        'nombre': 'Trp San Luis',
        'lat': -12.0501,
        'lng': -77.0401,
        'radio_m': 150,
      },
    ]);
    leidas = ['T200'];
    CaptureFlowScreen.elegirFotos = () async => [Uint8List.fromList(_png)];
    Ubicacion.permisoConcedido = () async => true;
    await abrir(tester);
    await tester.pumpAndSettle();

    expect(find.text('Estás en Trp San Luis'), findsOneWidget);
    await tester.tap(find.text('Galería'));
    await tester.pumpAndSettle();
    expect(find.text('Punto de partida: Trp San Luis'), findsOneWidget);

    await tester.tap(find.text('Registrar guía'));
    await tester.pumpAndSettle();
    expect(registradas, ['T200']);
    expect(origenes, ['Trp San Luis']);
  });
}
