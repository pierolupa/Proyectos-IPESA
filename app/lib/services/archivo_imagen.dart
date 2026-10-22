// Descargar, copiar y compartir una imagen (la foto de la entrega). En web
// usa el navegador; en los tests (VM) no existe y avisa que no se puede.
export 'archivo_imagen/archivo_imagen_stub.dart'
    if (dart.library.js_interop) 'archivo_imagen/archivo_imagen_web.dart';
