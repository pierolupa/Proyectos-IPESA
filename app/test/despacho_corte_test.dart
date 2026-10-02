import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/estado_guia.dart';
import 'package:ipesa_guias/screens/transportista/task_list_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/services/ubicacion.dart';
import 'package:ipesa_guias/state/app_state.dart';
import 'package:ipesa_guias/widgets/despacho_corte.dart';

const _corte = 'DC-261001-1542-K7';
final _salida = DateTime.now().toUtc().toIso8601String();

Map<String, dynamic> _guia(
  String numero, {
  String corte = _corte,
  String estado = 'en_ruta',
}) => {
  'numero_guia': numero,
  'estado': estado,
  'tipo_entrega': 'cliente_final',
  'origen': 'Trp Callao',
  'destino': 'Av. Lima 100',
  'transportista': 'Juan Pérez',
  'destinatario': 'Cliente $numero',
  'fecha_creacion': _salida,
  'fecha_actualizacion': _salida,
  'corregido_por_admin': false,
  'despacho_corte': corte,
};

void main() {
  late List<http.Request> pedidos;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'sesion_nombre': 'Juan Pérez',
      'sesion_rol': 'transportista',
    });
    Ubicacion.olvidarUltima();
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

  Future<AppState> abrir(WidgetTester tester) async {
    pedidos = [];
    final client = MockClient((r) async {
      pedidos.add(r);
      final ruta = r.url.path;
      if (ruta.endsWith('/sucursales')) return http.Response('[]', 200);
      if (ruta.endsWith('/llegada')) {
        return http.Response(
          jsonEncode({
            'despacho_corte': _corte,
            'guias': [
              for (final n in ['T1', 'T2', 'T3'])
                {..._guia(n), 'estado': 'entregado'},
            ],
          }),
          200,
        );
      }
      if (ruta.endsWith('/quitar')) {
        return http.Response(jsonEncode(_guia('T3', corte: '')), 200);
      }
      return http.Response(
        jsonEncode([
          _guia('T1'),
          _guia('T2'),
          _guia('T3'),
          _guia('S1', corte: ''),
        ]),
        200,
      );
    });
    final appState = AppState(api: GuiasApi(client: client));
    await appState.restaurarSesion();
    await appState.cargarGuias();
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(home: TaskListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return appState;
  }

  testWidgets('Las guías del corte van juntas y llegan todas a la vez', (
    tester,
  ) async {
    final appState = await abrir(tester);

    expect(find.byType(TarjetaDespachoCorte), findsOneWidget);
    expect(find.textContaining('$_corte · 3 guías'), findsOneWidget);
    // La suelta sigue con su propia tarjeta.
    expect(find.text('S1'), findsOneWidget);
    expect(find.text('Despacho Corte'), findsWidgets);

    await tester.tap(find.text('Llegó · entregar 3 guías'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, llegó'));
    await tester.pumpAndSettle();

    final llegada = pedidos.lastWhere((r) => r.url.path.endsWith('/llegada'));
    expect(llegada.url.path, contains(_corte));
    final cuerpo = jsonDecode(llegada.body) as Map<String, dynamic>;
    expect(cuerpo['geo'], {'lat': -12.1, 'lng': -77.0});
    expect(cuerpo['transportista'], 'Juan Pérez');
    expect(find.byType(TarjetaDespachoCorte), findsNothing);
    expect(
      appState.guias.where((g) => g.estado.esFinal).map((g) => g.numeroGuia),
      unorderedEquals(['T1', 'T2', 'T3']),
    );
    expect(find.text('Despacho $_corte entregado · 3 guías'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('La barra de opciones se abre, se esconde y se recuerda', (
    tester,
  ) async {
    await abrir(tester);
    // Empieza escondida: solo el botón "Opciones" junto al buscador.
    expect(find.text('Entrega con IA'), findsNothing);
    await tester.tap(find.text('Opciones'));
    await tester.pumpAndSettle();
    expect(find.text('Entrega con IA'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Despacho Corte'),
      findsOneWidget,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('opciones_tareas_abiertas'), isTrue);

    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Entrega con IA'), findsNothing);
    expect(prefs.getBool('opciones_tareas_abiertas'), isFalse);
  });

  testWidgets('Una guía se puede quitar del corte', (tester) async {
    await abrir(tester);

    await tester.tap(find.byTooltip('Opciones de T3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quitar del despacho'));
    await tester.pumpAndSettle();

    final quitar = pedidos.lastWhere((r) => r.url.path.endsWith('/quitar'));
    expect(jsonDecode(quitar.body), containsPair('numeroGuia', 'T3'));
    expect(find.textContaining('$_corte · 2 guías'), findsOneWidget);
    // Queda como tarea suelta.
    expect(find.byTooltip('Opciones de T3'), findsNothing);
    expect(find.text('T3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
