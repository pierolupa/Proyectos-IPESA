class Notificador {
  static bool get soportado => false;
  static bool get permitido => false;
  static bool get paginaOculta => false;
  static bool get pushSoportado => false;
  static String get permiso => 'no';
  static Future<bool> pedirPermiso() async => false;
  static Future<Map<String, dynamic>?> suscribirPush(String clave) async =>
      null;
  static Future<String?> desuscribirPush() async => null;
  static Future<void> mostrar(
    String titulo,
    String cuerpo, {
    String tag = 'ipesa-novedades',
  }) async {}
}
