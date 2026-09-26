class Notificador {
  static bool get soportado => false;
  static bool get permitido => false;
  static bool get paginaOculta => false;
  static Future<bool> pedirPermiso() async => false;
  static Future<void> mostrar(String titulo, String cuerpo) async {}
}
