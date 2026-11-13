import 'dart:async';

import 'package:ipesa_guias/widgets/carrusel_marcas.dart';
import 'package:ipesa_guias/widgets/celebracion_jornada.dart';
import 'package:ipesa_guias/widgets/escena_ruta.dart';
import 'package:ipesa_guias/widgets/splash_ipesa.dart';

/// Configuración común de todos los tests: el carrusel de marcas y el
/// paisaje del comercial se quedan quietos (sus animaciones no terminan
/// nunca y `pumpAndSettle` esperaría para siempre). El test del carrusel
/// lo vuelve a encender para probarlo.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  CarruselMarcas.animar = false;
  EscenaRuta.animar = false;
  // El cielo de Rastrear depende de la hora: los tests lo ven de día.
  PaletaEscena.reloj = () => DateTime(2026, 9, 15, 12);
  SplashIpesa.animar = false;
  CelebracionJornada.animar = false;
  await testMain();
}
