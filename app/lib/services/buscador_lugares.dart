import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class LugarEncontrado {
  const LugarEncontrado({
    required this.nombre,
    required this.direccion,
    required this.punto,
  });

  /// Nombre corto (p. ej. "Plaza Vea"); vacío si es solo una dirección.
  final String nombre;
  final String direccion;
  final LatLng punto;
}

/// Búsqueda de direcciones y tiendas con Nominatim (OpenStreetMap): gratis,
/// sin API key. Su política de uso no permite autocompletar mientras se
/// escribe, así que solo se busca al confirmar (Enter o botón).
class BuscadorLugares {
  BuscadorLugares({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<LugarEncontrado>> buscar(String texto, {LatLng? cerca}) async {
    final params = {
      'q': texto,
      'format': 'jsonv2',
      'countrycodes': 'pe',
      'accept-language': 'es',
      'limit': '6',
      // Prioriza (sin limitar) resultados cerca de donde está el mapa.
      if (cerca != null)
        'viewbox':
            '${cerca.longitude - 0.3},${cerca.latitude + 0.3},'
            '${cerca.longitude + 0.3},${cerca.latitude - 0.3}',
    };
    final res = await _client.get(
      Uri.https('nominatim.openstreetmap.org', '/search', params),
    );
    if (res.statusCode != 200) {
      throw Exception('El buscador respondió ${res.statusCode}.');
    }
    final lista = jsonDecode(res.body) as List<dynamic>;
    return [
      for (final e in lista.cast<Map<String, dynamic>>())
        LugarEncontrado(
          nombre: (e['name'] as String?) ?? '',
          direccion: e['display_name'] as String,
          punto: LatLng(
            double.parse(e['lat'] as String),
            double.parse(e['lon'] as String),
          ),
        ),
    ];
  }
}
