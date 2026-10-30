import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/documento_cliente.dart';
import 'package:ipesa_guias/models/guia.dart';
import 'package:ipesa_guias/screens/comercial/rastreo_detalle_screen.dart';
import 'package:ipesa_guias/screens/transportista/entrega_flow_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/services/ubicacion.dart';
import 'package:ipesa_guias/state/app_state.dart';

// PNG de 1×1 válido (se muestra la vista previa).
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Map<String, dynamic> _guia({
  String destinatario = 'MOTA-ENGIL PERU S.A.',
  String tipo = 'cliente_final',
  String estado = 'en_ruta',
  String docCliente = '',
}) => {
  'numero_guia': 'T028-133950',
  'estado': estado,
  'tipo_entrega': tipo,
  'origen': 'Almacen Ate',
  'destino': 'Av. Javier Prado Este 444',
  'transportista': 'Juan Pérez',
  'destinatario': destinatario,
  'fecha_creacion': DateTime.now().toUtc().toIso8601String(),
  'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
  'corregido_por_admin': false,
  'doc_cliente': docCliente,
};

void main() {
  test('MIGO para Mota-Engil y H.E.S para SK Rental, solo a cliente final', () {
    DocumentoCliente? doc(String cliente, {String tipo = 'cliente_final'}) =>
        DocumentoCliente.de(
          Guia.fromJson(_guia(destinatario: cliente, tipo: tipo)),
        );
    expect(doc('MOTA-ENGIL PERU S.A.')?.nombre, 'MIGO');
    expect(doc('Mota Engil Perú S.A.')?.nombre, 'MIGO');
    expect(doc('SK RENTAL S.A.C.')?.nombre, 'H.E.S');
    expect(doc('MOTA-ENGIL PERU S.A.', tipo: 'agencia'), isNull);
    expect(doc('FERRETERÍA LIMA S.A.C.'), isNull);
  });

  group('Entrega', () {
    late List<Map<String, dynamic>> cambios;
    // Lo que la IA lee en la foto de la guía (además del número).
    late Map<String, dynamic> lectura;

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'sesion_nombre': 'Juan Pérez',
        'sesion_rol': 'transportista',
      });
      cambios = [];
      lectura = {};
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

    Future<void> abrir(WidgetTester tester, Map<String, dynamic> json) async {
      final client = MockClient((request) async {
        final ruta = request.url.path;
        if (ruta.endsWith('/sucursales')) return http.Response('[]', 200);
        if (ruta.endsWith('/ocr/numero-guia')) {
          return http.Response(
            jsonEncode({'numero_guia': json['numero_guia'], ...lectura}),
            200,
          );
        }
        if (request.method == 'PATCH' && ruta.endsWith('/estado')) {
          final cuerpo = jsonDecode(request.body) as Map<String, dynamic>;
          cambios.add(cuerpo);
          return http.Response(
            jsonEncode({...json, 'estado': cuerpo['estado']}),
            200,
          );
        }
        return http.Response(jsonEncode([json]), 200);
      });
      final appState = AppState(api: GuiasApi(client: client));
      await appState.restaurarSesion();
      await appState.cargarGuias();
      tester.view.physicalSize = const Size(800, 2400);
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
                      builder: (_) => EntregaFlowScreen(
                        guia: Guia.fromJson(json),
                        desdeDetalle: false,
                      ),
                    ),
                  ),
                  child: const Text('Entregar'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Entregar'));
      await tester.pumpAndSettle();
      // Antes de la foto de la guía no se sabe si es cliente final o
      // agencia: todavía no pide el documento.
      expect(find.textContaining('MIGO'), findsNothing);
      expect(find.textContaining('H.E.S'), findsNothing);
      // La foto de la guía firmada.
      await tester.tap(find.text('Galería').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(
          'La foto muestra la guía firmada o el comprobante de la agencia',
        ),
      );
      await tester.pumpAndSettle();
    }

    bool confirmarHabilitado(WidgetTester tester) =>
        tester
            .widget<ButtonStyleButton>(
              find.ancestor(
                of: find.text('Confirmar'),
                matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
              ),
            )
            .onPressed !=
        null;

    testWidgets('Mota-Engil: sin la foto del MIGO no se puede confirmar', (
      tester,
    ) async {
      await abrir(tester, _guia());

      expect(find.text('Foto del MIGO'), findsOneWidget);
      expect(confirmarHabilitado(tester), isFalse);

      // El ejemplo, para saber cuál es.
      await tester.tap(find.text('Ver ejemplo'));
      await tester.pumpAndSettle();
      expect(find.text('Así es el MIGO'), findsOneWidget);
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Galería').last);
      await tester.pumpAndSettle();
      expect(find.text('Foto del MIGO lista'), findsOneWidget);
      expect(confirmarHabilitado(tester), isTrue);

      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(cambios.single['estado'], 'entregado');
      expect(cambios.single['foto'], isNotNull);
      expect(cambios.single['docCliente'], isNotNull);
      expect(cambios.single.containsKey('docPorCorreo'), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SK Rental: sin H.E.S en físico se cierra marcando "por '
        'correo"', (tester) async {
      await abrir(tester, _guia(destinatario: 'SK RENTAL S.A.C.'));

      expect(find.text('Foto del H.E.S'), findsOneWidget);
      expect(confirmarHabilitado(tester), isFalse);
      await tester.tap(find.text('No me dieron el H.E.S en físico'));
      await tester.pumpAndSettle();
      expect(confirmarHabilitado(tester), isTrue);

      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(cambios.single['docPorCorreo'], isTrue);
      expect(cambios.single.containsKey('docCliente'), isFalse);
    });

    testWidgets('Si la IA ve un comprobante de agencia, no pide el MIGO', (
      tester,
    ) async {
      lectura = {
        'agencia_razon_social': 'SEÑOR DE LUREN EXPRESS E.I.R.L.',
        'agencia_ruc': '20601857457',
        'agencia_monto': 13,
        'agencia_comprobante': 'G003-0072373',
      };
      await abrir(tester, _guia());
      expect(find.textContaining('MIGO'), findsNothing);
      expect(confirmarHabilitado(tester), isTrue);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(cambios.single['estado'], 'finalizado');
      expect(cambios.single.containsKey('docCliente'), isFalse);
      expect(cambios.single.containsKey('docPorCorreo'), isFalse);
    });

    testWidgets('La observación es opcional y se envía solo si la escriben', (
      tester,
    ) async {
      await abrir(tester, _guia(destinatario: 'FERRETERÍA LIMA S.A.C.'));
      // Sin abrirla no se pide nada: se confirma igual que antes.
      expect(find.text('Observación (opcional)'), findsNothing);
      expect(confirmarHabilitado(tester), isTrue);
      await tester.tap(find.text('Agregar observación (opcional)'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Observación (opcional)'),
        'Faltó un bulto',
      );
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(cambios.single['observacion'], 'Faltó un bulto');
    });

    testWidgets('Otro cliente no pide documento', (tester) async {
      await abrir(tester, _guia(destinatario: 'FERRETERÍA LIMA S.A.C.'));
      expect(find.textContaining('MIGO'), findsNothing);
      expect(confirmarHabilitado(tester), isTrue);
    });
  });

  testWidgets('En Rastrear, una guía de Mota-Engil tiene el botón MIGO', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'sesion_nombre': 'Ana',
      'sesion_rol': 'comercial',
    });
    final json = _guia(estado: 'entregado', docCliente: 'correo');
    final client = MockClient(
      (request) async => request.url.path.endsWith('/sucursales')
          ? http.Response('[]', 200)
          : http.Response(jsonEncode([json]), 200),
    );
    final appState = AppState(api: GuiasApi(client: client));
    await appState.restaurarSesion();
    await appState.cargarGuias();
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(
          home: RastreoDetalleScreen(numeroGuia: 'T028-133950'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ver foto'), findsOneWidget);
    expect(find.text('Ubicación'), findsOneWidget);
    await tester.ensureVisible(find.text('MIGO'));
    await tester.tap(find.text('MIGO'));
    await tester.pumpAndSettle();
    expect(find.text('Foto del MIGO'), findsOneWidget);
    expect(find.text('El cliente envía el MIGO por correo'), findsOneWidget);
  });

  testWidgets('En Rastrear: "Entregado con observación" y lo que anotó', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'sesion_nombre': 'Ana',
      'sesion_rol': 'comercial',
    });
    final json = {
      ..._guia(destinatario: 'FERRETERÍA LIMA S.A.C.', estado: 'entregado'),
      'observacion_entrega': 'Recibió el vigilante',
    };
    final client = MockClient(
      (request) async => request.url.path.endsWith('/sucursales')
          ? http.Response('[]', 200)
          : http.Response(jsonEncode([json]), 200),
    );
    final appState = AppState(api: GuiasApi(client: client));
    await appState.restaurarSesion();
    await appState.cargarGuias();
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(
          home: RastreoDetalleScreen(numeroGuia: 'T028-133950'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ENTREGADO'), findsOneWidget);
    expect(find.text('CON OBSERVACIÓN'), findsOneWidget);
    expect(find.textContaining('Recibió el vigilante'), findsOneWidget);
  });
}
