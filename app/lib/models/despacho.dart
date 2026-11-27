/// Una guía de la hoja externa "Despachos Ate" que no está en la base de la
/// app: solo se sabe que salió de Ate (no hay seguimiento de la entrega).
class Despacho {
  const Despacho({
    required this.numeroGuia,
    required this.cliente,
    required this.fecha,
    required this.numeroPedido,
    required this.numeroEntrega,
    this.sucursal = '',
    this.transporte = '',
  });

  final String numeroGuia;
  final String cliente;

  /// Fecha y hora en que se registró el despacho.
  final DateTime fecha;
  final String numeroPedido;
  final String numeroEntrega;

  /// Columna "Surcusal ipesa" de la hoja (informativa).
  final String sucursal;

  /// Empresa de transporte a la que se entregó (Natale, Toscano, Amazon...).
  final String transporte;

  factory Despacho.fromJson(Map<String, dynamic> json) => Despacho(
    numeroGuia: json['numero_guia'] as String? ?? '',
    cliente: json['cliente'] as String? ?? '',
    fecha: DateTime.parse(json['fecha'] as String),
    numeroPedido: json['numero_pedido'] as String? ?? '',
    numeroEntrega: json['numero_entrega'] as String? ?? '',
    sucursal: json['sucursal'] as String? ?? '',
    transporte: json['transporte'] as String? ?? '',
  );
}
