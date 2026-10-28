import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ipesa_guias/widgets/volver_con_esc.dart';

void main() {
  testWidgets('Esc vuelve a la pantalla anterior; con un diálogo abierto, '
      'solo lo cierra', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => VolverConEsc(
                  child: Scaffold(
                    body: TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            const AlertDialog(content: Text('Foto')),
                      ),
                      child: const Text('Ver foto'),
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('Buscar'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver foto'));
    await tester.pumpAndSettle();
    expect(find.text('Foto'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Foto'), findsNothing);
    expect(find.text('Ver foto'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Ver foto'), findsNothing);
    expect(find.text('Buscar'), findsOneWidget);
  });
}
