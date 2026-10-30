/// Sucursal con su perímetro (círculo) marcado por el administrador en el
/// mapa. La llegada de un traslado entre sucursales solo se registra con el
/// GPS dentro de este círculo.
class Sucursal {
  const Sucursal({
    required this.nombre,
    required this.lat,
    required this.lng,
    required this.radioM,
  });

  final String nombre;
  final double lat;
  final double lng;
  final double radioM;

  factory Sucursal.fromJson(Map<String, dynamic> json) {
    return Sucursal(
      nombre: json['nombre'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      radioM: (json['radio_m'] as num).toDouble(),
    );
  }
}
