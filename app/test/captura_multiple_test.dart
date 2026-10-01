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
  late int pedidosDeRegistro;
  late int ocupadaVeces;
  late List<Map<String, dynamic>> cuerposCorte;
  var sucursales = '[]';

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'sesion_nombre': 'Juan Pérez',
      'sesion_rol': 'transportista',
    });
    leidas = ['T200', 'T201', 'T100'];
    registradas = [];
    origenes = [];
    pedidosDeRegistro = 0;
    ocupadaVeces = 0;
    cuerposCorte = [];
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

  Future<void> abrir(
    WidgetTester tester, {
    bool corte = false,
    String? codigo,
  }) async {
    // T100 la registró él hace 10 min: no se puede registrar otra vez aún.
    final hace10 = DateTime.now().subtract(const Duration(minutes: 10));
    final client = MockClient((request) async {
      final ruta = request.url.path;
      if (ruta.endsWith('/sucursales')) return http.Response(sucursales, 200);
      if (ruta.endsWith('/ocr/leer-guia')) {
        if (ocupadaVeces > 0) {
          ocupadaVeces--;
          return http.Response(
            jsonEncode({'error': 'La IA está ocupada en este momento.'}),
            429,
          );
        }
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
      if (request.method == 'POST' &&
          (ruta.endsWith('/guias/lote') || ruta.endsWith('/despachos-corte'))) {
        pedidosDeRegistro++;
        final cuerpo = jsonDecode(request.body) as Map<String, dynamic>;
        if (ruta.endsWith('/despachos-corte')) cuerposCorte.add(cuerpo);
        final resultados = <Map<String, dynamic>>[];
        for (final g in (cuerpo['guias'] as List).cast<Map>()) {
          final numero = g['numeroGuia'] as String;
          registradas.add(numero);
          origenes.add(g['origen'] as String);
          resultados.add({'guia': _guia(numero, DateTime.now())});
        }
        return http.Response(
          jsonEncode({
            'resultados': resultados,
            if (ruta.endsWith('/despachos-corte')) 'despacho_corte': 'DC-1',
          }),
          200,
        );
      }
      return http.Response(jsonEncode([_guia('T100', hace10)]), 200);
    });
    final appState = AppState(api: GuiasApi(client: client));
    await appState.restaurarSesion();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: MaterialApp(
          home: CaptureFlowScreen(despachoCorte: corte, codigoCorte: codigo),
        ),
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
    // T100 la registró él hace 10 min: esa espera; las otras dos, listas.
    expect(
      find.textContaining('Ya registraste esta guía hace poco'),
      findsOneWidget,
    );
    expect(find.text('Registrar 2 guías'), findsOneWidget);

    await tester.tap(find.text('Registrar 2 guías'));
    await tester.pumpAndSettle();

    expect(registradas, unorderedEquals(['T200', 'T201']));
    // Todas en un solo pedido al servidor.
    expect(pedidosDeRegistro, 1);
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

  testWidgets('Acepta hasta 30 fotos por carga y las registra juntas', (
    tester,
  ) async {
    leidas = [for (var i = 0; i < 30; i++) 'G$i'];
    CaptureFlowScreen.elegirFotos = () async => [
      for (var i = 0; i < 35; i++) Uint8List.fromList(_png),
    ];
    await abrir(tester);
    await tester.tap(find.text('GPS activo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galería'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Máximo 30 guías por carga'), findsOneWidget);
    expect(leidas, isEmpty);
    expect(find.text('Galería · 30/30'), findsOneWidget);
    // Se va el aviso del límite.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Registrar 30 guías'));
    await tester.pumpAndSettle();
    expect(registradas, hasLength(30));
    expect(pedidosDeRegistro, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Si la IA está ocupada, espera y vuelve a leer la foto', (
    tester,
  ) async {
    leidas = ['T500'];
    ocupadaVeces = 2;
    CaptureFlowScreen.elegirFotos = () async => [Uint8List.fromList(_png)];
    await abrir(tester);
    await tester.tap(find.text('GPS activo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galería'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('La IA está ocupada: reintentando…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(ocupadaVeces, 0);
    expect(find.text('T500'), findsOneWidget);
    expect(find.text('La IA está ocupada: reintentando…'), findsNothing);
    expect(find.text('Registrar guía'), findsOneWidget);
  });

  testWidgets('Despacho Corte: crea el corte y luego suma guías a él', (
    tester,
  ) async {
    leidas = ['T200'];
    CaptureFlowScreen.elegirFotos = () async => [Uint8List.fromList(_png)];
    await abrir(tester, corte: true);
    expect(find.text('Despacho Corte'), findsOneWidget);
    await tester.tap(find.text('GPS activo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galería'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Despachar guía'));
    await tester.pumpAndSettle();
    expect(cuerposCorte.single.containsKey('despachoCorte'), isFalse);
    expect(registradas, ['T200']);
  });

  testWidgets('Agregar guías a un corte en camino las suma a ese corte', (
    tester,
  ) async {
    leidas = ['T201'];
    CaptureFlowScreen.elegirFotos = () async => [Uint8List.fromList(_png)];
    await abrir(tester, corte: true, codigo: 'DC-9');
    expect(find.text('Despacho Corte · DC-9'), findsOneWidget);
    await tester.tap(find.text('GPS activo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galería'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Despachar guía'));
    await tester.pumpAndSettle();
    expect(cuerposCorte.single['despachoCorte'], 'DC-9');
  });

  test('Solo espera 20 minutos la guía que él mismo registró', () async {
    final ahora = DateTime(2026, 9, 28, 15);
    final deDiego = {
      ..._guia('T3', ahora.subtract(const Duration(minutes: 5))),
      'transportista': 'Diego',
    };
    final client = MockClient(
      (request) async => request.url.path.endsWith('/sucursales')
          ? http.Response('[]', 200)
          : http.Response(
              jsonEncode([
                _guia('T1', ahora.subtract(const Duration(minutes: 10))),
                _guia('T2', ahora.subtract(const Duration(minutes: 25))),
                deDiego,
              ]),
              200,
            ),
    );
    final appState = AppState(api: GuiasApi(client: client));
    await appState.restaurarSesion();
    await appState.cargarGuias();

    expect(
      appState.registroBloqueadoHasta('T1', ahora: ahora),
      ahora.add(const Duration(minutes: 10)).toUtc(),
    );
    expect(appState.registroBloqueadoHasta('T2', ahora: ahora), isNull);
    // La registró otro transportista: él la puede registrar al momento.
    expect(appState.registroBloqueadoHasta('T3', ahora: ahora), isNull);
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
