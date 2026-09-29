import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/guia.dart';
import 'package:ipesa_guias/screens/admin/admin_dashboard_screen.dart';
import 'package:ipesa_guias/screens/admin/transportistas.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

// Hoy a media mañana, para que las guías entren en la línea de tiempo.
final _hoy10 = DateTime.now().copyWith(
  hour: 10,
  minute: 0,
  second: 0,
  millisecond: 0,
  microsecond: 0,
);

Map<String, dynamic> _guia(
  String numero,
  String estado,
  String transportista, {
  int minutos = 0,
}) => {
  'numero_guia': numero,
  'estado': estado,
  'tipo_entrega': 'cliente_final',
  'origen': 'Almacén Callao',
  'destino': 'Av. Principal 123',
  'transportista': transportista,
  'destinatario': 'Cliente $numero',
  'fecha_actualizacion': _hoy10
      .add(Duration(minutes: minutos))
      .toUtc()
      .toIso8601String(),
  'corregido_por_admin': false,
};

Future<void> _abrirPanel(WidgetTester tester) async {
  final client = MockClient((request) async {
    if (request.url.path.endsWith('/sucursales')) {
      return http.Response(
        jsonEncode([
          {
            'nombre': 'Sucursal Arequipa',
            'lat': -16.4,
            'lng': -71.53,
            'radio_m': 200,
          },
        ]),
        200,
      );
    }
    return http.Response(
      jsonEncode([
        _guia('T001-1', 'en_ruta', 'Juan Pérez'),
        _guia('T001-2', 'en_proceso_trasbordo', 'Juan Pérez', minutos: 180),
        _guia('T001-3', 'recepcion_sucursal', 'Ana Díaz', minutos: 60),
        _guia('T001-4', 'entregado', 'Ana Díaz', minutos: 120),
        _guia('T001-5', 'finalizado', 'Ana Díaz', minutos: 240),
      ]),
      200,
    );
  });
  // Pantalla alta, como un celular: con la franja de marcas abajo, en la
  // de 800×600 por defecto no entran todas las guías.
  tester.view.physicalSize = const Size(800, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final appState = AppState(api: GuiasApi(client: client));
  await appState.cargarGuias();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: appState,
      child: const MaterialApp(home: AdminDashboardScreen()),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('El dashboard muestra los indicadores', (tester) async {
    await _abrirPanel(tester);
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.textContaining('Cumplimiento'), findsOneWidget);
    expect(find.text('Guías del periodo'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Estado de las guías'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.dragUntilVisible(
      find.text('0 de 2'),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    expect(find.text('Ranking de transportistas'), findsOneWidget);
    // Ana entregó 2 de sus 3 guías; Juan, ninguna de 2.
    expect(find.text('2 de 3'), findsOneWidget);
    expect(find.text('0 de 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('El panel filtra por En ruta, Entregado y Rechazada', (
    tester,
  ) async {
    await _abrirPanel(tester);

    expect(find.text('Todas · 5'), findsOneWidget);
    expect(find.text('En ruta · 1'), findsOneWidget);
    // Sin filtro de trasbordo (sus guías siguen en "Todas").
    expect(find.textContaining('Trasbordo ·'), findsNothing);
    expect(find.text('Entregado · 2'), findsOneWidget);
    expect(find.text('Rechazada · 0'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(4));

    await tester.tap(find.text('Entregado · 2'));
    await tester.pumpAndSettle();
    expect(find.text('T001-4'), findsOneWidget);
    expect(find.text('T001-5'), findsOneWidget);
    expect(find.text('T001-1'), findsNothing);
  });

  testWidgets('El buscador filtra por cliente o transportista', (tester) async {
    await _abrirPanel(tester);

    await tester.enterText(find.byType(TextField), 'ana');
    await tester.pumpAndSettle();
    expect(find.text('T001-3'), findsOneWidget);
    expect(find.text('T001-1'), findsNothing);
  });

  testWidgets('Recorrido muestra a cada transportista en la línea de tiempo', (
    tester,
  ) async {
    await _abrirPanel(tester);

    await tester.tap(find.text('Recorrido'));
    await tester.pumpAndSettle();

    expect(find.text('Recorrido de hoy'), findsOneWidget);
    expect(find.text('Juan Pérez'), findsOneWidget);
    expect(find.text('1 en ruta · 1 trasbordo'), findsOneWidget);
    expect(find.text('Ana Díaz'), findsOneWidget);
    expect(find.text('2 entregadas · 1 trasbordo'), findsOneWidget);
    for (final n in ['T001-1', 'T001-2', 'T001-3', 'T001-4', 'T001-5']) {
      expect(find.text(n), findsOneWidget);
    }
  });

  testWidgets('Sucursales lista los perímetros marcados', (tester) async {
    await _abrirPanel(tester);

    await tester.tap(find.text('Sucursales'));
    await tester.pumpAndSettle();

    expect(find.text('Sucursal Arequipa'), findsOneWidget);
    expect(find.text('Perímetro de 200 m'), findsOneWidget);
    expect(find.text('Nueva sucursal'), findsOneWidget);
  });

  testWidgets('Transportistas muestra a cada uno y su desglose', (
    tester,
  ) async {
    await _abrirPanel(tester);

    await tester.tap(find.text('Transportistas'));
    await tester.pumpAndSettle();

    expect(find.text('Juan Pérez'), findsOneWidget);
    expect(find.text('Ana Díaz'), findsOneWidget);
    expect(find.text('1 en ruta'), findsOneWidget);
    expect(find.text('2 entregadas'), findsOneWidget);
    // Las finalizadas (entregadas o rechazadas) van en su propio panel;
    // las demás, como casillas en curso. Juan no finalizó ninguna todavía.
    expect(find.text('Finalizadas'), findsNWidgets(2));
    expect(find.text('Aún no finaliza ninguna.'), findsOneWidget);
    final paneles = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_PanelFinalizadas',
    );
    for (final numero in ['T001-4', 'T001-5']) {
      expect(
        find.descendant(of: paneles, matching: find.text(numero)),
        findsOneWidget,
      );
    }
    for (final numero in ['T001-1', 'T001-2', 'T001-3']) {
      expect(
        find.descendant(of: paneles, matching: find.text(numero)),
        findsNothing,
      );
    }
    // Cada casilla dice también a qué cliente va.
    expect(
      find.descendant(of: paneles, matching: find.text('Cliente T001-4')),
      findsOneWidget,
    );
    expect(find.text('Cliente T001-1'), findsOneWidget);
    for (final numero in ['T001-1', 'T001-2', 'T001-3', 'T001-4', 'T001-5']) {
      expect(find.text(numero), findsOneWidget);
    }

    await tester.tap(find.text('Ana Díaz'));
    await tester.pumpAndSettle();

    expect(find.text('Entregó 2 de 2 cerradas (100 %)'), findsOneWidget);
    expect(find.text('Pendientes · 1'), findsOneWidget);
    expect(find.text('Entregadas · 2'), findsOneWidget);
    expect(find.text('T001-3'), findsOneWidget);
    expect(find.text('T001-4'), findsOneWidget);
    expect(find.text('T001-1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('El administrador también rastrea como el comercial', (
    tester,
  ) async {
    await _abrirPanel(tester);

    await tester.tap(find.byTooltip('Rastrear guía'));
    await tester.pumpAndSettle();
    expect(find.text('Rastrea tus guías'), findsOneWidget);

    await tester.tap(find.byTooltip('Volver al panel'));
    await tester.pumpAndSettle();
    expect(find.text('Operación'), findsOneWidget);
  });

  testWidgets('En computadora el riel tiene Transportistas y Rastrear', (
    tester,
  ) async {
    await _abrirPanel(tester);
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();

    // Las secciones van en orden, con el nombre al costado.
    final orden = [
      'Guías',
      'Transportistas',
      'Dashboard',
      'Recorrido',
      'Sucursales',
      'Rastrear',
    ].map((t) => tester.getTopLeft(find.text(t).first).dy).toList();
    for (var i = 1; i < orden.length; i++) {
      expect(orden[i], greaterThan(orden[i - 1]));
    }
    expect(find.text('Cerrar sesión'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'Las pendientes cuentan siempre; las cerradas, si cierran en el periodo',
    () {
      final ahora = DateTime(2026, 9, 28, 12);
      Guia guia(String estado, DateTime fecha) => Guia.fromJson(
        _guia('X', estado, 'Juan Pérez')
          ..['fecha_actualizacion'] = fecha.toUtc().toIso8601String(),
      );
      final vieja = DateTime(2026, 9, 10);
      final pendiente = guia('en_ruta', vieja);
      final entregadaVieja = guia('entregado', vieja);
      final entregadaHoy = guia('entregado', DateTime(2026, 9, 28, 9));

      final hoy = resumirPorTransportista(
        [pendiente, entregadaVieja, entregadaHoy],
        PeriodoResumen.hoy,
        ahora: ahora,
      ).single;
      expect(hoy.guias, hasLength(2));
      expect(hoy.pendientes, 1);

      final todo = resumirPorTransportista(
        [pendiente, entregadaVieja, entregadaHoy],
        PeriodoResumen.todo,
        ahora: ahora,
      ).single;
      expect(todo.guias, hasLength(3));
    },
  );
}
