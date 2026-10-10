import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/app.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

http.Response _json(Object body, {int status = 200}) {
  return http.Response(jsonEncode(body), status);
}

/// Cliente simulado que responde POST /auth/login y GET /guias, para
/// probar el flujo completo de login sin red real.
MockClient _clienteConSesion({
  required String nombre,
  required String rol,
  List<Map<String, dynamic>> guias = const [],
}) {
  return MockClient((request) async {
    if (request.method == 'POST' && request.url.path.endsWith('/auth/login')) {
      return _json({'nombre': nombre, 'rol': rol});
    }
    if (request.method == 'GET' && request.url.path.endsWith('/guias')) {
      return _json(guias);
    }
    return http.Response('No mockeado: ${request.method} ${request.url}', 404);
  });
}

/// Pantalla de celular (390×900): el login tiene la portada arriba y el
/// formulario abajo, que en la de 800×600 por defecto quedaría fuera.
void _pantallaCelular(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Cuánto se puede desplazar hacia abajo el login (0 = todo entra).
double _desplazamientoVertical(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    )
    .position
    .maxScrollExtent;

void main() {
  // AppState ahora guarda la sesión en SharedPreferences (ver
  // restaurarSesion/_establecerSesion) — sin este mock, getInstance()
  // fallaría en los tests por no tener un canal de plataforma real. Se
  // resetea antes de cada test para que ninguno herede la sesión guardada
  // por el anterior.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Muestra el login como pantalla de inicio', (
    WidgetTester tester,
  ) async {
    _pantallaCelular(tester);
    await tester.pumpWidget(const IpesaGuiasApp());
    // La pantalla de carga es estática: se avanza el reloj hasta que termina.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // El nombre de la app, lo que significa y su eslogan.
    expect(find.text('RPA'), findsOneWidget);
    expect(find.text('REGISTRO DE PEDIDOS ATENDIDOS'), findsOneWidget);
    expect(find.text('La IA lo vio, el cliente lo firmó.'), findsOneWidget);
    expect(find.text('Ingresa a tu cuenta'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Ingresar'), findsOneWidget);
    expect(find.text('Crea tu cuenta'), findsOneWidget);
    expect(find.text('¿Eres cliente? Rastrea tu envío'), findsNothing);
  });

  testWidgets('El transportista inicia sesión y ve sus tareas', (
    WidgetTester tester,
  ) async {
    final client = _clienteConSesion(
      nombre: 'Juan Pérez',
      rol: 'transportista',
      guias: [
        {
          'numero_guia': 'IPE-2026-000123',
          'estado': 'en_ruta',
          'tipo_entrega': 'cliente_final',
          'origen': 'Almacén Callao',
          'destino': 'Av. Siempre Viva 742',
          'transportista': 'Juan Pérez',
          'destinatario': 'María Torres',
          'fecha_actualizacion': '2026-01-01T00:00:00.000Z',
          'corregido_por_admin': false,
        },
      ],
    );
    final appState = AppState(api: GuiasApi(client: client));

    _pantallaCelular(tester);
    await tester.pumpWidget(IpesaGuiasApp(appState: appState));
    // La pantalla de carga es estática: se avanza el reloj hasta que termina.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Juan Pérez');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Ingresar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pendientes · 1'), findsOneWidget);
    expect(find.text('IPE-2026-000123'), findsOneWidget);
  });

  testWidgets('El login rechaza credenciales inválidas', (
    WidgetTester tester,
  ) async {
    final client = MockClient(
      (request) async =>
          _json({'error': 'Nombre o PIN incorrecto.'}, status: 401),
    );
    final appState = AppState(api: GuiasApi(client: client));

    _pantallaCelular(tester);
    await tester.pumpWidget(IpesaGuiasApp(appState: appState));
    // La pantalla de carga es estática: se avanza el reloj hasta que termina.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Nadie');
    await tester.enterText(find.byType(TextField).at(1), '0000');
    await tester.tap(find.widgetWithText(FilledButton, 'Ingresar'));
    await tester.pumpAndSettle();

    expect(find.text('Nombre o PIN incorrecto.'), findsOneWidget);
  });

  testWidgets('Crear cuenta registra al usuario como transportista', (
    WidgetTester tester,
  ) async {
    final client = MockClient((request) async {
      if (request.method == 'POST' &&
          request.url.path.endsWith('/auth/registro')) {
        return _json({
          'nombre': 'Chofer Nuevo',
          'rol': 'transportista',
        }, status: 201);
      }
      if (request.method == 'GET' && request.url.path.endsWith('/guias')) {
        return _json([]);
      }
      return http.Response(
        'No mockeado: ${request.method} ${request.url}',
        404,
      );
    });
    final appState = AppState(api: GuiasApi(client: client));

    _pantallaCelular(tester);
    await tester.pumpWidget(IpesaGuiasApp(appState: appState));
    // La pantalla de carga es estática: se avanza el reloj hasta que termina.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crea tu cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Crear cuenta'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'Chofer Nuevo');
    await tester.enterText(find.byType(TextField).at(1), '9999');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pendientes'), findsOneWidget);
  });

  for (final (ancho, alto) in [
    (390.0, 700.0),
    (360.0, 640.0),
    (412.0, 780.0),
  ]) {
    testWidgets(
      'En un celular de ${ancho.toInt()}×${alto.toInt()} el login entra '
      'sin bajar',
      (tester) async {
        tester.view.physicalSize = Size(ancho, alto);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(const IpesaGuiasApp());
        // La pantalla de carga es estática: se avanza el reloj hasta que termina.
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();

        expect(_desplazamientoVertical(tester), 0);
        for (final texto in [
          'Ingresa a tu cuenta',
          'Ingresar',
          'Crea tu cuenta',
        ]) {
          expect(
            tester.getRect(find.text(texto)).bottom,
            lessThanOrEqualTo(alto),
          );
        }
        expect(tester.takeException(), isNull);

        // En modo "crear cuenta" (título más largo y ayuda del PIN) tampoco.
        await tester.tap(find.text('Crea tu cuenta'));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.text('Ingresa')).bottom,
          lessThanOrEqualTo(alto),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  // Antes, al abrirse el teclado el login cambiaba de estructura, el campo
  // perdía el foco y el teclado se cerraba solo.
  for (final (caso, abrirTeclado) in <(String, void Function(WidgetTester))>[
    (
      'teclado como inset (app)',
      (t) => t.view.viewInsets = const FakeViewPadding(bottom: 320),
    ),
    (
      'ventana que se achica (navegador)',
      (t) => t.view.physicalSize = const Size(390, 440),
    ),
  ]) {
    testWidgets('Al abrir el teclado no se pierde el foco: $caso', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const IpesaGuiasApp());
      // La pantalla de carga es estática: se avanza el reloj hasta que termina.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      final nombre = find.byType(TextField).first;
      await tester.tap(nombre);
      await tester.pump();
      abrirTeclado(tester);
      await tester.pumpAndSettle();

      final editable = tester.widget<EditableText>(
        find.descendant(of: nombre, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      await tester.enterText(nombre, 'Carlos Ruiz');
      await tester.pump();
      expect(find.text('Carlos Ruiz'), findsOneWidget);
      expect(editable.focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('La cuenta queda guardada y escrita al volver a abrir la app', (
    WidgetTester tester,
  ) async {
    final client = _clienteConSesion(
      nombre: 'Juan Pérez',
      rol: 'transportista',
    );
    _pantallaCelular(tester);
    await tester.pumpWidget(
      IpesaGuiasApp(
        appState: AppState(api: GuiasApi(client: client)),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Juan Pérez');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Ingresar'));
    await tester.pumpAndSettle();

    // Cerrar sesión borra la sesión, pero no la cuenta recordada.
    final appState = AppState(api: GuiasApi(client: client));
    await appState.cerrarSesion();
    expect(await appState.cuentaGuardada(), ('Juan Pérez', '1234'));

    // Al abrir la app de nuevo, nombre y PIN ya están escritos.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(IpesaGuiasApp(appState: appState));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    final campos = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(campos[0].controller!.text, 'Juan Pérez');
    expect(campos[1].controller!.text, '1234');

    // Un toque y entra.
    await tester.tap(find.widgetWithText(FilledButton, 'Ingresar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pendientes'), findsOneWidget);
  });
}
