import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

const _swUrl = 'notificaciones_sw.js';

class Notificador {
  static bool get soportado => globalContext.has('Notification');

  static bool get permitido =>
      soportado && web.Notification.permission == 'granted';

  static bool get paginaOculta => web.document.hidden;

  static Future<bool> pedirPermiso() async {
    if (!soportado) return false;
    final resultado = await web.Notification.requestPermission().toDart;
    if (resultado.toDart != 'granted') return false;
    await _registrarServiceWorker();
    return true;
  }

  static Future<web.ServiceWorkerRegistration?>
  _registrarServiceWorker() async {
    if (!web.window.navigator.has('serviceWorker')) return null;
    try {
      return await web.window.navigator.serviceWorker
          .register(_swUrl.toJS)
          .toDart;
    } catch (_) {
      return null;
    }
  }

  /// Android Chrome no permite `new Notification()`: exige mostrarla desde
  /// un service worker. En escritorio funcionan ambas vías.
  static Future<void> mostrar(String titulo, String cuerpo) async {
    if (!permitido) return;
    final opciones = web.NotificationOptions(
      body: cuerpo,
      icon: 'icons/Icon-192.png',
      tag: 'ipesa-novedades',
      renotify: true,
    );
    final registro = await _registrarServiceWorker();
    if (registro != null) {
      try {
        await registro.showNotification(titulo, opciones).toDart;
        return;
      } catch (_) {}
    }
    try {
      web.Notification(titulo, opciones);
    } catch (_) {}
  }
}
