import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GPS del transportista, compartido entre "Nuevas guías" y "Entregar".
///
/// Se enciende una vez y queda encendido: la elección se recuerda en el
/// celular, y si el celular ya dio permiso de ubicación a la app el GPS se
/// activa solo al abrir la pantalla, sin volver a pedir nada.
class Ubicacion {
  Ubicacion._();

  static const _clave = 'gps_activo';

  /// Última posición leída, para mostrar el GPS activo al instante
  /// mientras se lee una nueva.
  static Position? _ultima;

  /// Cuánto sirve la última posición para activar el GPS al instante.
  static const _vigencia = Duration(minutes: 2);

  /// Con más error que esto (en metros) la ubicación es aproximada: viene
  /// de la antena o del wifi, o el celular tiene apagada la "ubicación
  /// precisa", y puede caer a uno o dos kilómetros de donde está.
  static const precisionAceptable = 100.0;

  /// Lecturas extra para afinar una ubicación aproximada (el GPS suele
  /// fijarse en unos segundos) y cuánto esperar como máximo.
  static const _reintentos = 3;
  static const _esperaMaxima = Duration(seconds: 15);

  /// Los tests los reemplazan (no hay GPS ahí).
  @visibleForTesting
  static Future<Position> Function() leer = _leerDelDispositivo;
  @visibleForTesting
  static Future<bool> Function() permisoConcedido = _permisoDelDispositivo;

  @visibleForTesting
  static void olvidarUltima() => _ultima = null;

  /// ¿La posición tiene demasiado error? (0 = el celular no lo informó).
  static bool esAproximada(Position p) => p.accuracy > precisionAceptable;

  /// "± 1,8 km" / "± 350 m": el error de una posición, para mostrarlo.
  static String textoPrecision(Position p) {
    final m = p.accuracy;
    if (m >= 1000) {
      return '± ${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
    }
    return '± ${m.round()} m';
  }

  /// Posición actual; pide permiso si hace falta y lanza un texto si no se
  /// puede. Si la primera lectura es aproximada, vuelve a leer unas veces
  /// (el GPS se fija en segundos) y se queda con la más precisa.
  static Future<Position> actual() async {
    var mejor = await leer();
    final limite = DateTime.now().add(_esperaMaxima);
    for (
      var i = 0;
      i < _reintentos && esAproximada(mejor) && DateTime.now().isBefore(limite);
      i++
    ) {
      try {
        final otra = await leer();
        if (otra.accuracy < mejor.accuracy) mejor = otra;
      } catch (_) {
        break;
      }
    }
    _ultima = mejor;
    return mejor;
  }

  /// La última posición si es reciente y precisa (para no hacer esperar).
  static Position? get reciente {
    final p = _ultima;
    if (p == null || esAproximada(p)) return null;
    return DateTime.now().difference(p.timestamp) <= _vigencia ? p : null;
  }

  /// ¿Hay que activar el GPS solo al abrir la pantalla? Sí, si el
  /// transportista ya lo había encendido (y no lo apagó) o si el celular ya
  /// dio permiso de ubicación.
  static Future<bool> debeActivarseSolo() async {
    final recordado = await _recordado();
    if (recordado == false) return false;
    if (recordado == true) return true;
    return permisoConcedido();
  }

  /// Guarda si el transportista dejó el GPS encendido o lo apagó.
  static Future<void> recordar(bool activo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_clave, activo);
    } catch (_) {
      // Sin almacenamiento solo se pierde el recuerdo.
    }
  }

  static Future<bool?> _recordado() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_clave);
    } catch (_) {
      return null;
    }
  }
}

Future<Position> _leerDelDispositivo() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw 'La ubicación está desactivada en tu dispositivo.';
  }
  var permiso = await Geolocator.checkPermission();
  if (permiso == LocationPermission.denied) {
    permiso = await Geolocator.requestPermission();
  }
  if (permiso == LocationPermission.denied ||
      permiso == LocationPermission.deniedForever) {
    throw 'Debes dar permiso de ubicación para continuar.';
  }
  // Sin posiciones guardadas: siempre una lectura nueva.
  return Geolocator.getCurrentPosition(
    locationSettings: kIsWeb
        ? WebSettings(
            accuracy: LocationAccuracy.best,
            maximumAge: Duration.zero,
            timeLimit: const Duration(seconds: 20),
          )
        : const LocationSettings(accuracy: LocationAccuracy.best),
  );
}

/// Pregunta al celular si ya hay permiso, SIN mostrar ningún aviso.
Future<bool> _permisoDelDispositivo() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final permiso = await Geolocator.checkPermission();
    return permiso == LocationPermission.whileInUse ||
        permiso == LocationPermission.always;
  } catch (_) {
    return false;
  }
}
