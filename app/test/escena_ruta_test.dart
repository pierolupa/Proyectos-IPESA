import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ipesa_guias/widgets/escena_ruta.dart';

void main() {
  test('El cielo cambia con la hora: día, atardecer y noche', () {
    MomentoDia a(int h, int m) => momentoDelDia(DateTime(2026, 11, 13, h, m));
    expect(a(5, 59), MomentoDia.noche);
    expect(a(6, 0), MomentoDia.dia);
    expect(a(17, 29), MomentoDia.dia);
    expect(a(17, 30), MomentoDia.tarde);
    expect(a(18, 44), MomentoDia.tarde);
    expect(a(18, 45), MomentoDia.noche);
    expect(a(23, 0), MomentoDia.noche);
  });

  test('Sobre el cielo oscuro, el texto va claro', () {
    expect(PaletaEscena.de(MomentoDia.dia).oscuro, isFalse);
    expect(PaletaEscena.de(MomentoDia.tarde).texto, Colors.white);
    expect(PaletaEscena.de(MomentoDia.noche).texto, Colors.white);
  });

  testWidgets('De noche el paisaje toma la paleta de noche', (tester) async {
    final antes = PaletaEscena.reloj;
    PaletaEscena.reloj = () => DateTime(2026, 11, 13, 21);
    addTearDown(() => PaletaEscena.reloj = antes);
    late PaletaEscena vista;
    await tester.pumpWidget(
      MaterialApp(
        home: FondoCielo(
          child: Builder(
            builder: (context) {
              vista = FondoCielo.paletaDe(context);
              return const Align(
                alignment: Alignment.bottomCenter,
                child: EscenaRuta(),
              );
            },
          ),
        ),
      ),
    );
    expect(vista.momento, MomentoDia.noche);
    expect(tester.takeException(), isNull);
  });

  test(
    'El camión pasa por las 30 sucursales, una por región en cada vuelta',
    () {
      expect(sucursalEnEscena(7, 2), sucursalEnEscena(7, 2));
      expect(sucursalEnEscena(7, 0), isNot(sucursalEnEscena(8, 0)));
      final vistas = {
        for (var v = 1; v <= 9; v++)
          for (var r = 0; r < 4; r++) sucursalEnEscena(v, r),
      };
      expect(vistas, hasLength(30));
      expect(vistas, containsAll(['Almacen Piura', 'Tienda TR Callao']));
      expect(
        sucursalEnEscena(3, 3),
        anyOf(
          'Almacen Iquitos',
          'Almacen Pucallpa',
          'Almacen Tarapoto',
          'Tienda TR Nueva Cajamarca',
        ),
      );
    },
  );
}
