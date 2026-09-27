import 'dart:async';

import 'package:web/web.dart' as web;

/// Cuánto falta para que la pantalla de carga se haya visto [minimo],
/// contando desde que se abrió la página (no desde que arrancó Flutter).
Duration esperaMinimaSplash(Duration minimo) {
  final transcurrido = web.window.performance.now();
  final resta = minimo.inMilliseconds - transcurrido;
  return Duration(milliseconds: resta > 0 ? resta.round() : 0);
}

/// Completa el anillo de progreso y luego desvanece y quita la pantalla de
/// carga de web/index.html. Se llama cuando la pantalla siguiente ya está
/// pintada debajo, así no hay ningún parpadeo entre una y otra.
void quitarSplashHtml() {
  final inicio = web.document.getElementById('inicio');
  if (inicio == null) return;
  inicio.classList.add('listo');
  Timer(const Duration(milliseconds: 300), () {
    inicio.classList.add('fuera');
    Timer(const Duration(milliseconds: 450), () => inicio.remove());
  });
}
