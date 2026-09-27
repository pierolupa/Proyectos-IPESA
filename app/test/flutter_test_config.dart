import 'dart:async';

import 'package:ipesa_guias/widgets/carrusel_marcas.dart';

/// Configuración común de todos los tests: el carrusel de marcas se queda
/// quieto (su animación no termina nunca y `pumpAndSettle` esperaría para
/// siempre). El test del carrusel lo vuelve a encender para probarlo.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  CarruselMarcas.animar = false;
  await testMain();
}
