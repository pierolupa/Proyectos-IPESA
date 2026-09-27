// Pantalla de carga de web/index.html: en web la quita la app cuando ya
// pintó la pantalla siguiente; en los tests (VM) no existe.
export 'splash_html/splash_html_stub.dart'
    if (dart.library.js_interop) 'splash_html/splash_html_web.dart';
