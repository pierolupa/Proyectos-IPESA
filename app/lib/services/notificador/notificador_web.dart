import 'dart:convert';
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

  /// ¿Este navegador puede recibir avisos con la app cerrada (Web Push)?
  /// En iPhone solo si la app está instalada en la pantalla de inicio.
  static bool get pushSoportado =>
      soportado &&
      web.window.navigator.has('serviceWorker') &&
      globalContext.has('PushManager');

  /// 'default' (aún no decidió), 'granted', 'denied' o 'no' (sin avisos).
  static String get permiso => soportado ? web.Notification.permission : 'no';

  static Future<web.ServiceWorkerRegistration?> _registroListo() async {
    if (await _registrarServiceWorker() == null) return null;
    try {
      return await web.window.navigator.serviceWorker.ready.toDart;
    } catch (_) {
      return null;
    }
  }

  /// Suscribe este celular a los avisos con la [clave] pública del
  /// servidor (base64url). Devuelve la suscripción como mapa
  /// ({endpoint, keys: {p256dh, auth}}) o null si no se pudo.
  static Future<Map<String, dynamic>?> suscribirPush(String clave) async {
    if (!pushSoportado || !permitido) return null;
    final registro = await _registroListo();
    if (registro == null) return null;
    final bytes = base64Url.decode(base64Url.normalize(clave)).toJS;
    Future<web.PushSubscription> nueva() => registro.pushManager
        .subscribe(
          web.PushSubscriptionOptionsInit(
            userVisibleOnly: true,
            applicationServerKey: bytes,
          ),
        )
        .toDart;
    try {
      web.PushSubscription suscripcion;
      try {
        suscripcion = await nueva();
      } catch (_) {
        // Había una con otra clave: se da de baja y se vuelve a pedir.
        final vieja = await registro.pushManager.getSubscription().toDart;
        if (vieja == null) rethrow;
        await vieja.unsubscribe().toDart;
        suscripcion = await nueva();
      }
      final texto = (globalContext['JSON']! as JSObject)
          .callMethod<JSString>('stringify'.toJS, suscripcion)
          .toDart;
      return jsonDecode(texto) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Da de baja los avisos de este celular; devuelve su endpoint (para
  /// avisar al servidor) o null si no tenía.
  static Future<String?> desuscribirPush() async {
    if (!pushSoportado) return null;
    try {
      final registro = await web.window.navigator.serviceWorker
          .getRegistration()
          .toDart;
      final suscripcion = await registro?.pushManager.getSubscription().toDart;
      if (suscripcion == null) return null;
      final endpoint = suscripcion.endpoint;
      await suscripcion.unsubscribe().toDart;
      return endpoint;
    } catch (_) {
      return null;
    }
  }

  /// Android Chrome no permite `new Notification()`: exige mostrarla desde
  /// un service worker. En escritorio funcionan ambas vías.
  static Future<void> mostrar(
    String titulo,
    String cuerpo, {
    String tag = 'ipesa-novedades',
  }) async {
    if (!permitido) return;
    final opciones = web.NotificationOptions(
      body: cuerpo,
      icon: 'icons/rpa-192.png',
      tag: tag,
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
