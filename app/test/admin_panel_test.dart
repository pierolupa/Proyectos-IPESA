import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/guia.dart';
import 'package:ipesa_guias/screens/admin/admin_dashboard_screen.dart';
import 'package:ipesa_guias/screens/admin/admin_guia_edit_screen.dart';
import 'package:ipesa_guias/screens/admin/dashboard.dart';
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
    expect(find.text('Cierre'), findsOneWidget);
    expect(find.text('Eficiencia'), findsOneWidget);
    expect(find.text('Guías del periodo'), findsOneWidget);
    // Periodo: hoy o un rango de fechas de inicio a fin.
    for (final quitado in ['7 días', 'Mes', 'Todo']) {
      expect(find.text(quitado), findsNothing);
    }
    expect(find.text('Fechas'), findsOneWidget);
    await tester.tap(find.text('Fechas'));
    await tester.pumpAndSettle();
    expect(find.text('Fecha de inicio y fin'), findsOneWidget);
    Navigator.of(tester.element(find.text('Fecha de inicio y fin'))).pop();
    await tester.pumpAndSettle();
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

  testWidgets('Tocar un número del dashboard muestra sus guías', (
    tester,
  ) async {
    await _abrirPanel(tester);
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();

    // Ana entregó T001-4 y T001-5 (finalizada).
    await tester.tap(find.text('Entregadas').first);
    await tester.pumpAndSettle();
    expect(find.text('2 guías · Hoy'), findsOneWidget);
    expect(find.byType(TarjetaGuiaAdmin), findsNWidgets(2));
    expect(find.text('T001-4'), findsOneWidget);
    expect(find.text('T001-1'), findsNothing);

    // Tocar una abre su detalle.
    await tester.tap(find.text('T001-4'));
    await tester.pumpAndSettle();
    expect(find.byType(AdminGuiaEditScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('El panel filtra por estado con una lista desplegable', (
    tester,
  ) async {
    await _abrirPanel(tester);

    // Cerrada muestra solo el estado elegido.
    expect(find.text('Todas · 5'), findsOneWidget);
    expect(find.text('En ruta · 1'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('filtro_estado')));
    await tester.pumpAndSettle();
    expect(find.text('En ruta · 1'), findsOneWidget);
    // Sin filtro de trasbordo (sus guías siguen en "Todas").
    expect(find.textContaining('Trasbordo ·'), findsNothing);
    expect(find.text('Entregado · 2'), findsOneWidget);
    expect(find.text('Rechazada · 0'), findsOneWidget);

    await tester.tap(find.text('Entregado · 2'));
    await tester.pumpAndSettle();
    expect(find.text('Entregado · 2'), findsOneWidget);
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

    // 2 de sus 3 guías cerradas, las 2 entregadas.
    expect(find.text('Cierre · Eficiencia 67 %'), findsOneWidget);
    expect(find.text('Pendientes · 1'), findsOneWidget);
    expect(find.text('Entregadas · 2'), findsOneWidget);
    expect(find.text('T001-3'), findsOneWidget);
    expect(find.text('T001-4'), findsOneWidget);
    expect(find.text('T001-1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('En computadora el desglose tiene tabla, mapa y línea del día', (
    tester,
  ) async {
    await _abrirPanel(tester);
    tester.view.physicalSize = const Size(1440, 900);
    final appState = Provider.of<AppState>(
      tester.element(find.byType(AdminDashboardScreen)),
      listen: false,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(
          home: TransportistaDetalleScreen(nombre: 'Ana Díaz'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MapaGuias), findsOneWidget);
    expect(find.text('Línea del día'), findsOneWidget);
    expect(find.text('Entregó T001-4 · Cliente T001-4'), findsOneWidget);
    // La tabla abre en las pendientes.
    expect(find.text('T001-3'), findsOneWidget);
    expect(find.text('T001-4'), findsNothing);

    await tester.tap(find.text('Entregadas'));
    await tester.pumpAndSettle();
    expect(find.text('T001-4'), findsOneWidget);
    expect(find.text('T001-5'), findsOneWidget);
    expect(find.text('T001-3'), findsNothing);

    await tester.enterText(find.byType(TextField), 'T001-5');
    await tester.pumpAndSettle();
    expect(find.text('T001-4'), findsNothing);
    // La fila y lo escrito en el buscador.
    expect(find.text('T001-5'), findsNWidgets(2));
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

  testWidgets('En computadora las secciones van en el menú ☰', (tester) async {
    await _abrirPanel(tester);
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();

    // Escondidas hasta abrir el menú: el contenido usa todo el ancho.
    expect(find.text('Transportistas'), findsNothing);
    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();

    final orden = [
      'Guías',
      'Transportistas',
      'Dashboard',
      'Sucursales',
      'Rastrear',
    ].map((t) => tester.getTopLeft(find.text(t).first).dy).toList();
    for (var i = 1; i < orden.length; i++) {
      expect(orden[i], greaterThan(orden[i - 1]));
    }
    expect(find.text('Cerrar sesión'), findsOneWidget);

    await tester.tap(find.text('Transportistas'));
    await tester.pumpAndSettle();
    // Se cerró el menú y cambió la sección.
    expect(find.text('Cerrar sesión'), findsNothing);
    expect(find.text('Transportistas'), findsWidgets);
    expect(find.text('Operación'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'Hoy: pendientes y cerradas hoy; un rango: las registradas en esas fechas',
    () {
      final ahora = DateTime(2026, 10, 2, 15);
      Guia guia(
        String numero,
        String estado,
        DateTime creada, [
        DateTime? cerrada,
      ]) => Guia.fromJson(
        _guia(numero, estado, 'Juan Pérez')
          ..['fecha_creacion'] = creada.toUtc().toIso8601String()
          ..['fecha_actualizacion'] = (cerrada ?? creada)
              .toUtc()
              .toIso8601String(),
      );
      final guias = [
        // Del 1/10: una entregada ese día, una entregada hoy y una rechazada.
        guia(
          'A',
          'entregado',
          DateTime(2026, 10, 1, 9),
          DateTime(2026, 10, 1, 12),
        ),
        guia(
          'B',
          'entregado',
          DateTime(2026, 10, 1, 17),
          DateTime(2026, 10, 2, 10),
        ),
        guia(
          'C',
          'rechazado',
          DateTime(2026, 10, 1, 10),
          DateTime(2026, 10, 1, 11),
        ),
        // Del 30/09, sigue en ruta.
        guia('D', 'en_ruta', DateTime(2026, 9, 30, 8)),
        // De hoy: una en ruta y una entregada.
        guia('E', 'en_ruta', DateTime(2026, 10, 2, 9)),
        guia(
          'F',
          'entregado',
          DateTime(2026, 10, 2, 8),
          DateTime(2026, 10, 2, 11),
        ),
      ];
      List<String> numeros(PeriodoResumen p) => (resumirPorTransportista(
        guias,
        p,
        ahora: ahora,
      ).single.guias.map((g) => g.numeroGuia)).toList()..sort();

      // Hoy: lo pendiente (de cualquier día) y lo que se cerró hoy.
      expect(numeros(PeriodoResumen.hoy), ['B', 'D', 'E', 'F']);
      // El 1/10: solo las registradas ese día, con su estado actual.
      final primero = DateTime(2026, 10, 1);
      expect(numeros(PeriodoResumen.fechas(primero, primero)), ['A', 'B', 'C']);
      // Del 30/09 al 1/10 entra también la que sigue en ruta desde el 30.
      expect(numeros(PeriodoResumen.fechas(DateTime(2026, 9, 30), primero)), [
        'A',
        'B',
        'C',
        'D',
      ]);
      // Un rango sin guías no muestra nada de hoy.
      expect(
        resumirPorTransportista(
          guias,
          PeriodoResumen.fechas(DateTime(2026, 9, 1), DateTime(2026, 9, 29)),
          ahora: ahora,
        ),
        isEmpty,
      );
    },
  );

  test('Un solo día se grafica por hora; varios días, por día', () {
    final ahora = DateTime(2026, 10, 2, 15);
    Guia guia(String numero, DateTime creada, DateTime cerrada) =>
        Guia.fromJson(
          _guia(numero, 'entregado', 'Juan Pérez')
            ..['fecha_creacion'] = creada.toUtc().toIso8601String()
            ..['fecha_actualizacion'] = cerrada.toUtc().toIso8601String(),
        );
    final guias = [
      guia('A', DateTime(2026, 10, 1, 8), DateTime(2026, 10, 1, 9, 30)),
      guia('B', DateTime(2026, 10, 1, 8), DateTime(2026, 10, 1, 9, 50)),
      // Del 1/10, pero se entregó el 2/10: no va en las horas del 1/10.
      guia('C', DateTime(2026, 10, 1, 17), DateTime(2026, 10, 2, 10)),
    ];
    final primero = DateTime(2026, 10, 1);
    final unDia = IndicadoresOperacion.calcular(
      guias,
      PeriodoResumen.fechas(primero, primero),
      ahora: ahora,
    );
    expect(unDia.porHora, isTrue);
    expect(unDia.serie.first.etiqueta, '7 h');
    final nueve = unDia.serie.firstWhere((p) => p.etiqueta == '9 h');
    expect(nueve.entregadas, 2);
    expect(unDia.serie.fold(0, (n, p) => n + p.entregadas), 2);

    final dosDias = IndicadoresOperacion.calcular(
      guias,
      PeriodoResumen.fechas(DateTime(2026, 9, 30), primero),
      ahora: ahora,
    );
    expect(dosDias.porHora, isFalse);
    expect(dosDias.serie, hasLength(2));
  });

  test('Costo de agencias: total, promedio y por agencia', () {
    final ahora = DateTime(2026, 10, 2, 15);
    Guia guia(String numero, String? razon, String ruc, Object? monto) =>
        Guia.fromJson(
          _guia(numero, 'entregado', 'Juan Pérez')
            ..['fecha_creacion'] = DateTime(
              2026,
              10,
              2,
              8,
            ).toUtc().toIso8601String()
            ..['fecha_actualizacion'] = DateTime(
              2026,
              10,
              2,
              10,
            ).toUtc().toIso8601String()
            ..['agencia_razon_social'] = razon ?? ''
            ..['agencia_ruc'] = ruc
            ..['agencia_monto'] = monto,
        );
    final datos = IndicadoresOperacion.calcular(
      [
        guia('A', 'TURISMO INTERNACIONAL PALOMINO S.A.C.', '20515659324', 70),
        // La misma agencia con otros espacios y mayúsculas, monto como texto.
        guia('B', 'Turismo  Internacional Palomino S.A.C.', '', '30'),
        guia('C', 'SEÑOR DE LUREN EXPRESS E.I.R.L.', '20601857457', 13),
        // Sin comprobante: no cuenta.
        guia('D', null, '', null),
      ],
      PeriodoResumen.hoy,
      ahora: ahora,
    );
    expect(datos.comprobantes, 3);
    expect(datos.costoAgencias, 113);
    expect(datos.costoPromedioAgencia, closeTo(37.67, 0.01));
    expect(datos.agencias.map((a) => (a.pedidos, a.costo)), [
      (2, 100.0),
      (1, 13.0),
    ]);
    expect(datos.agencias.first.ruc, '20515659324');
    expect(soles(1234.5), 'S/ 1,234.50');
  });

  test('Un rechazo cierra la tarea pero no cuenta como entrega', () {
    final ahora = DateTime(2026, 9, 29, 18);
    Guia guia(String numero, String estado) => Guia.fromJson(
      _guia(numero, estado, 'Juan Pérez')
        ..['fecha_actualizacion'] = DateTime(
          2026,
          9,
          29,
          12,
        ).toUtc().toIso8601String(),
    );
    final guias = [
      for (var i = 0; i < 26; i++) guia('E$i', 'entregado'),
      guia('R1', 'rechazado'),
    ];
    final datos = IndicadoresOperacion.calcular(
      guias,
      PeriodoResumen.hoy,
      ahora: ahora,
    );
    expect(datos.total, 27);
    expect((datos.cierre * 100).round(), 100);
    expect((datos.eficiencia * 100).round(), 96);
  });
}
