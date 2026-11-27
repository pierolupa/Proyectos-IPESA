import 'guia.dart';
import 'tipo_entrega.dart';

/// Documento que algunos clientes dan al recibir la mercadería y que el
/// transportista fotografía además de la guía firmada: sin esa foto no
/// puede cerrar la entrega, salvo que marque que no se lo dieron en
/// físico (lo envían por correo al asesor). Solo en entregas a cliente
/// final; esta foto no pasa por la IA.
///
/// La misma lista está en el backend (backend/src/documentoCliente.js).
class DocumentoCliente {
  const DocumentoCliente._(this._cliente, this.nombre, this.ejemplo);

  final String _cliente;

  /// Cómo lo llaman ("MIGO", "H.E.S").
  final String nombre;

  /// Foto de ejemplo para que el transportista sepa cuál es.
  final String ejemplo;

  static const todos = [
    DocumentoCliente._('MOTAENGILPERU', 'MIGO', 'assets/ejemplos/migo.jpg'),
    DocumentoCliente._('SKRENTAL', 'H.E.S', 'assets/ejemplos/hes.jpg'),
  ];

  /// En la hoja, cuando no lo dieron en físico.
  static const porCorreo = 'correo';

  /// El documento que pide el cliente de [guia], o null.
  static DocumentoCliente? de(Guia guia) {
    if (guia.tipoEntrega != TipoEntrega.clienteFinal) return null;
    final clave = claveCliente(guia.destinatario);
    for (final d in todos) {
      if (clave.startsWith(d._cliente)) return d;
    }
    return null;
  }
}

/// "MOTA-ENGIL PERÚ S.A." → "MOTAENGILPERUSA", para comparar.
String claveCliente(String texto) {
  const tildes = {'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U'};
  final mayusculas = texto.toUpperCase().split('').map((c) => tildes[c] ?? c);
  return mayusculas.join().replaceAll(RegExp('[^A-Z0-9]'), '');
}
