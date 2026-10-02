import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/screens/transportista/entrega_ia_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/services/ubicacion.dart';
import 'package:ipesa_guias/state/app_state.dart';

// PNG de 1×1 (la foto en sí no importa: la "IA" del test responde por orden).
const _png = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

final _creada = DateTime.now().toUtc().toIso8601String();

Map<String, dynamic> _guia(
  String numero, {
  String estado = 'en_ruta',
  String tipo = 'cliente_final',
  String transportista = 'Juan Pérez',
}) => {
  'numero_guia': numero,
  'estado': estado,
  'tipo_entrega': tipo,
  'origen': 'Trp Callao',
  'destino': 'Av. Lima 100',
  'transportista': transportista,
  'destinatario': 'Cliente $numero',
  'fecha_creacion': _creada,
  'fecha_actualizacion': _creada,
  'corregido_por_admin': false,
};

void main() {
  late List<String?> leidas;
  late List<String> candidatos;
  late List<Map<String, dynamic>> entregas;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'sesion_nombre': 'Juan Pérez',
      'sesion_rol': 'transportista',
    });
    entregas = [];
    Ubicacion.olvidarUltima();
    Ubicacion.permisoConcedido = () async => true;
    Ubicacion.leer = () async => Position(
      latitude: -12.1,
      longitude: -77.0,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  });

  Future<void> abrir(WidgetTester tester, int fotos) async {
    EntregaIAScreen.elegirFotos = () async => [
      for (var i = 0; i < fotos; i++) Uint8List.fromList(_png),
    ];
    final client = MockClient((r) async {
      final ruta = r.url.path;
      if (ruta.endsWith('/sucursales')) return http.Response('[]', 200);
      if (ruta.endsWith('/ocr/numero-guia')) {
        candidatos = List<String>.from(
          (jsonDecode(r.body) as Map<String, dynamic>)['candidatos'] as List,
        );
        return http.Response(
          jsonEncode({'numero_guia': leidas.removeAt(0)}),
          200,
        );
      }
      if (ruta.endsWith('/estado')) {
        final cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
        final numero = ruta.split('/')[ruta.split('/').length - 2];
        entregas.add({...cuerpo, 'numero': numero});
        return http.Response(
          jsonEncode({..._guia(numero), 'estado': cuerpo['estado']}),
          200,
        );
      }
      return http.Response(
        jsonEncode([
          _guia('T001-1'),
          _guia('T001-2', tipo: 'agencia'),
          _guia('T001-3', estado: 'entregado'),
          _guia('T001-4', transportista: 'Diego'),
        ]),
        200,
      );
    });
    final appState = AppState(api: GuiasApi(client: client));
    await appState.restaurarSesion();
    await appState.cargarGuias();
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(home: EntregaIAScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Entrega solo las fotos cuya guía está en sus tareas en ruta', (
    tester,
  ) async {
    // Dos suyas en ruta, una repetida, una ya entregada, una de otro
    // transportista, una que no existe y una sin número.
    leidas = ['t001-1', 'T001-2', 'T001-1', 'T001-3', 'T001-4', 'X999-9', null];
    await abrir(tester, 7);
    await tester.tap(find.textContaining('Galería'));
    await tester.pumpAndSettle();

    expect(find.text('Para entregar · 2'), findsOneWidget);
    expect(find.text('No se entregarán · 5'), findsOneWidget);
    expect(find.text('Repetida: ya está en otra foto'), findsOneWidget);
    expect(find.text('No está en tus tareas en ruta'), findsNWidgets(3));
    expect(find.text('La IA no pudo leer el número de guía'), findsOneWidget);
    // Nada se entrega sin confirmar.
    expect(entregas, isEmpty);

    await tester.tap(find.text('Entregar 2 guías'));
    await tester.pumpAndSettle();

    expect(
      entregas.map((e) => e['numero']),
      unorderedEquals(['T001-1', 'T001-2']),
    );
    final porNumero = {for (final e in entregas) e['numero']: e};
    expect(porNumero['T001-1']!['estado'], 'entregado');
    // La de agencia queda finalizada, como en la entrega normal.
    expect(porNumero['T001-2']!['estado'], 'finalizado');
    for (final e in entregas) {
      expect(e['geo'], {'lat': -12.1, 'lng': -77.0});
      expect(e['foto'], isNotNull);
      expect(e['fechaCreacion'], isNotNull);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Encuentra la guía aunque la IA lea ceros u O por 0', (
    tester,
  ) async {
    leidas = ['T001-0001', 'TOO1 - 2', 'T001 N° 0003'];
    await abrir(tester, 3);
    await tester.tap(find.textContaining('Galería'));
    await tester.pumpAndSettle();

    // La IA recibe solo sus guías en ruta para compararlas.
    expect(candidatos, unorderedEquals(['T001-1', 'T001-2']));
    expect(find.text('Para entregar · 2'), findsOneWidget);
    // T001-3 ya estaba entregada: no se vuelve a entregar.
    expect(find.text('No se entregarán · 1'), findsOneWidget);
    expect(find.text('Entregar 2 guías'), findsOneWidget);
  });

  test('El número se compara sin ceros, espacios ni confusiones O/0', () {
    for (final leido in ['T001-0093506', 't001 - 93506', 'TOO1-93506']) {
      expect(claveGuia(leido), claveGuia('T001-93506'));
    }
    expect(claveGuia('T001-93507'), isNot(claveGuia('T001-93506')));
  });

  testWidgets('Quitar una foto encontrada no la entrega', (tester) async {
    leidas = ['T001-1', 'T001-2'];
    await abrir(tester, 2);
    await tester.tap(find.textContaining('Galería'));
    await tester.pumpAndSettle();
    expect(find.text('Entregar 2 guías'), findsOneWidget);

    await tester.tap(find.byTooltip('Quitar foto').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entregar 1 guía'));
    await tester.pumpAndSettle();
    expect(entregas, hasLength(1));
  });
}
