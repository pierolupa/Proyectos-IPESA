// Notificaciones del navegador: implementación real solo en web; en los
// tests (VM) se usa un stub que no hace nada.
export 'notificador/notificador_stub.dart'
    if (dart.library.js_interop) 'notificador/notificador_web.dart';
