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

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Map<String, dynamic> _guia(String numero) => {
  'numero_guia': numero,
  'estado': 'en_ruta',
  'tipo_entrega': 'cliente_final',
  'origen': 'Almacén Callao',
  'destino': 'Av. Principal 123',
  'transportista': 'Juan Pérez',
  'destinatario': 'Cliente $numero',
  'fecha_creacion': DateTime.now().toUtc().toIso8601String(),
  'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
  'corregido_por_admin': false,
};

void main() {
  late Map<String, dynamic> lectura;
  late List<(String, Map<String, dynamic>)> entregas;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'sesion_nombre': 'Juan Pérez',
      'sesion_rol': 'transportista',
    });
    entregas = [];
    Ubicacion.olvidarUltima();
    Ubicacion.permisoConcedido = () async => true;
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
    EntregaFlowScreen.tomarFoto = () async => null;
    EntregaFlowScreen.elegirFoto = () async => Uint8List.fromList(_png);
  });

  Future<void> abrir(WidgetTester tester) async {
    final client = MockClient((r) async {
      final ruta = r.url.path;
      if (ruta.endsWith('/sucursales')) return http.Response('[]', 200);
      if (ruta.endsWith('/ocr/numero-guia')) {
        return http.Response(jsonEncode(lectura), 200);
      }
      if (r.method == 'PATCH' && ruta.endsWith('/estado')) {
        final cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
        final numero = ruta.split('/')[ruta.split('/').length - 2];
        entregas.add((numero, cuerpo));
        return http.Response(
          jsonEncode({..._guia(numero), 'estado': cuerpo['estado']}),
          200,
        );
      }
      return http.Response(jsonEncode([_guia('T500'), _guia('T501')]), 200);
    });
    final appState = AppState(api: GuiasApi(client: client));
    await appState.restaurarSesion();
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EntregaFlowScreen(
                    guia: Guia.fromJson(_guia('T500')),
                    desdeDetalle: false,
                  ),
                ),
              ),
              child: const Text('Entregar'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Entregar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galería'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(
        'La foto muestra la guía firmada o el comprobante de la agencia',
      ),
    );
    await tester.pumpAndSettle();
  }

  bool confirmarHabilitado(WidgetTester tester) => tester
      .widget<FilledButton>(
        find.ancestor(
          of: find.text('Confirmar'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      )
      .enabled;

  testWidgets('Si la foto es de otra de sus tareas, avisa y la puede '
      'entregar a ella', (tester) async {
    lectura = {'numero_guia': 'T501'};
    await abrir(tester);

    expect(
      find.text('Esta foto es de la guía T501, no de T500'),
      findsOneWidget,
    );
    expect(confirmarHabilitado(tester), isFalse);

    await tester.tap(find.text('Entregar T501'));
    await tester.pumpAndSettle();
    // La misma foto, ya verificada para T501.
    expect(find.text('Guía T501 verificada en la foto'), findsOneWidget);
    await tester.tap(
      find.text(
        'La foto muestra la guía firmada o el comprobante de la agencia',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(entregas.single.$1, 'T501');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Guía verificada con comprobante: se entrega en agencia', (
    tester,
  ) async {
    lectura = {
      'numero_guia': 'T500',
      'agencia_razon_social': 'SEÑOR DE LUREN EXPRESS E.I.R.L.',
      'agencia_ruc': '20601857457',
      'agencia_monto': 13,
      'agencia_comprobante': 'G003-0072373',
    };
    await abrir(tester);

    expect(find.text('Guía T500 verificada en la foto'), findsOneWidget);
    expect(find.textContaining('SEÑOR DE LUREN EXPRESS'), findsOneWidget);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    final (numero, cuerpo) = entregas.single;
    expect(numero, 'T500');
    expect(cuerpo['estado'], 'finalizado');
    // Ya leído: el servidor no lo vuelve a pedir a la IA.
    expect((cuerpo['comprobante'] as Map)['numero'], 'G003-0072373');
  });

  testWidgets('Si la IA se equivoca, puede entregar igual', (tester) async {
    lectura = {'numero_guia': 'X999-1'};
    await abrir(tester);

    expect(
      find.text('Esta foto es de la guía X999-1, no de T500'),
      findsOneWidget,
    );
    expect(confirmarHabilitado(tester), isFalse);
    await tester.tap(find.text('La foto es correcta, entregar igual'));
    await tester.pumpAndSettle();
    expect(confirmarHabilitado(tester), isTrue);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(entregas.single.$1, 'T500');
  });
}
