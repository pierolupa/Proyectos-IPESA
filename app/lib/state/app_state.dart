import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/estado_guia.dart';
import '../models/guia.dart';
import '../models/rol_usuario.dart';
import '../models/sucursal.dart';
import '../models/tipo_entrega.dart';
import '../services/guias_api.dart';

const _prefNombre = 'sesion_nombre';

/// Novedad detectada al actualizar en segundo plano (para notificar al admin).
class CambioGuia {
  CambioGuia(
    this.guia,
    this.mensaje, {
    this.anterior,
    this.transbordoAntes,
    DateTime? momento,
  }) : momento = momento ?? DateTime.now();
  final Guia guia;
  final String mensaje;

  /// Estado que tenía antes; null si la guía es nueva.
  final EstadoGuia? anterior;
  final DateTime momento;

  /// Cómo estaba el transbordo antes ('' si no había).
  final String? transbordoAntes;

  bool get nueva => anterior == null;

  /// Se pidió, aceptó o rechazó un transbordo (el estado no cambió).
  bool get esTransbordo =>
      anterior != null &&
      anterior == guia.estado &&
      guia.transbordoEstado.isNotEmpty &&
      guia.transbordoEstado != (transbordoAntes ?? '');

  /// El transportista pide borrar la tarea (el estado no cambió).
  bool get pideEliminar =>
      anterior != null &&
      anterior == guia.estado &&
      !esTransbordo &&
      guia.eliminacionPendiente;
}

const _prefRol = 'sesion_rol';

/// Un mismo número de guía se puede volver a registrar pasado este tiempo
/// desde su último registro (lo mismo valida el backend).
const esperaMismaGuia = Duration(hours: 2);

/// Distancia en metros entre dos puntos (haversine).
double distanciaMetros(double lat1, double lng1, double lat2, double lng2) {
  double rad(double g) => g * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * 6371000 * math.asin(math.sqrt(a));
}

DateTime _inicioDelDia(DateTime f) => DateTime(f.year, f.month, f.day);

/// Estado de la app respaldado por la API real (ver ../services/guias_api.dart).
/// Mantiene una copia en memoria de las guías para que las pantallas no
/// tengan que repetir la llamada de red en cada rebuild.
class AppState extends ChangeNotifier {
  AppState({GuiasApi? api}) : _api = api ?? GuiasApi();

  final GuiasApi _api;

  List<Guia> _guias = [];
  List<Sucursal> _sucursales = [];
  bool cargando = false;
  String? error;
  RolUsuario? _rolActual;
  String? _nombreUsuario;

  /// Solo para el equipo comercial: días de la fecha de tarea que se piden
  /// al servidor (así no se descarga toda la hoja). Por defecto, hoy.
  DateTime _desdeTareas = _inicioDelDia(DateTime.now());
  DateTime _hastaTareas = _inicioDelDia(DateTime.now());
  Future<void>? _cargaEnCurso;
  (DateTime, DateTime)? _rangoCargado;

  (DateTime, DateTime) get rangoTareas => (_desdeTareas, _hastaTareas);

  bool get _pideRango => _rolActual == RolUsuario.comercial;

  Future<List<Guia>> _pedirGuias() {
    if (!_pideRango) return _api.listarGuias();
    return _api.listarGuias(
      desde: _desdeTareas,
      hasta: _hastaTareas.add(const Duration(days: 1)),
    );
  }

  /// El comercial busca en otro rango de fechas: se piden al servidor solo
  /// esas guías (si no son las que ya están cargadas). Para los demás
  /// roles no hace nada: ya tienen todas.
  Future<void> asegurarRangoTareas(DateTime desde, DateTime hasta) async {
    _desdeTareas = _inicioDelDia(desde);
    _hastaTareas = _inicioDelDia(hasta);
    if (!_pideRango) return;
    if (_cargaEnCurso case final carga?) await carga;
    if (_rangoCargado == (_desdeTareas, _hastaTareas) && error == null) return;
    await cargarGuias();
  }

  List<Guia> get guias => List.unmodifiable(_guias);
  List<Sucursal> get sucursales => List.unmodifiable(_sucursales);
  RolUsuario? get rolActual => _rolActual;

  /// Nombre del usuario con sesión iniciada (vacío si no hay sesión).
  String get transportistaActual => _nombreUsuario ?? '';

  /// Login simple contra la hoja "Usuarios" (ver backend/README.md — no
  /// es un mecanismo de autenticación real, ver la advertencia ahí).
  /// Deja que el ApiException se propague para que la pantalla de login
  /// muestre el mensaje de error.
  Future<void> iniciarSesion(String nombre, String pin) async {
    await _establecerSesion(await _api.login(nombre, pin));
  }

  /// Auto-registro; siempre crea la cuenta como transportista (ver
  /// backend/src/app.js).
  Future<void> registrarUsuario(String nombre, String pin) async {
    await _establecerSesion(await _api.registrar(nombre, pin));
  }

  void _rangoDeHoy() {
    _desdeTareas = _hastaTareas = _inicioDelDia(DateTime.now());
    _rangoCargado = null;
  }

  Future<void> _establecerSesion(SesionUsuario sesion) async {
    _nombreUsuario = sesion.nombre;
    _rolActual = sesion.rol;
    _rangoDeHoy();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefNombre, sesion.nombre);
    await prefs.setString(_prefRol, sesion.rol.name);
    await cargarGuias();
  }

  /// Restaura la sesión guardada (si hay una) al abrir la app — sin esto,
  /// recargar la página siempre volvía al login aunque ya se hubiera
  /// iniciado sesión antes, porque el estado solo vivía en memoria.
  /// No hace nada si no hay nada guardado (deja `rolActual` en null).
  Future<void> restaurarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    final nombre = prefs.getString(_prefNombre);
    final rolTexto = prefs.getString(_prefRol);
    if (nombre == null || rolTexto == null) return;

    final rol = RolUsuario.values.asNameMap()[rolTexto];
    if (rol == null) return;

    _nombreUsuario = nombre;
    _rolActual = rol;
    _rangoDeHoy();
    notifyListeners();
    await cargarGuias();
  }

  Future<void> cerrarSesion() async {
    _rolActual = null;
    _nombreUsuario = null;
    _guias = [];
    _sucursales = [];
    error = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefNombre);
    await prefs.remove(_prefRol);
  }

  Future<void> cargarGuias() {
    final carga = _cargar();
    _cargaEnCurso = carga;
    return carga.whenComplete(() {
      if (identical(_cargaEnCurso, carga)) _cargaEnCurso = null;
    });
  }

  Future<void> _cargar() async {
    cargando = true;
    error = null;
    notifyListeners();
    try {
      final rango = (_desdeTareas, _hastaTareas);
      _guias = await _pedirGuias();
      _rangoCargado = _pideRango ? rango : null;
    } catch (e) {
      error = e.toString();
    }
    // Las sucursales son secundarias: si fallan no bloquean la lista.
    try {
      _sucursales = await _api.listarSucursales();
    } catch (_) {
      _sucursales = [];
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  /// Recarga las guías sin mostrar carga ni borrar la lista si falla (para
  /// el refresco automático) y devuelve lo que cambió desde la última vez.
  Future<List<CambioGuia>> actualizarEnSegundoPlano() async {
    if (cargando) return const [];
    final List<Guia> nuevas;
    try {
      nuevas = await _pedirGuias();
    } catch (_) {
      return const [];
    }
    final anteriores = {for (final g in _guias) g.clave: g};
    final cambios = <CambioGuia>[
      for (final g in nuevas)
        if (_describirCambio(anteriores[g.clave], g) case final mensaje?)
          CambioGuia(
            g,
            mensaje,
            anterior: anteriores[g.clave]?.estado,
            transbordoAntes: anteriores[g.clave]?.transbordoEstado,
          ),
    ];
    _guias = nuevas;
    error = null;
    notifyListeners();
    return cambios;
  }

  static String? _describirCambio(Guia? antes, Guia ahora) {
    final quien = ahora.transportista;
    final n = ahora.numeroGuia;
    if (antes == null) {
      return '$quien registró la guía $n (${ahora.tipoEntrega.etiqueta}).';
    }
    if (antes.estado == ahora.estado) {
      if (ahora.transbordoEstado != antes.transbordoEstado) {
        if (ahora.transbordoPendiente) {
          return '$quien quiere pasar la guía $n a ${ahora.transbordoA}.';
        }
        if (ahora.transbordoAceptado) {
          return '$quien aceptó la guía $n que le pasó ${ahora.transbordoDe}.';
        }
        if (ahora.transbordoRechazado) {
          return '${ahora.transbordoA} no aceptó la guía $n que le pasaba '
              '$quien.';
        }
      }
      if (ahora.eliminacionPendiente && !antes.eliminacionPendiente) {
        return '$quien pide eliminar la guía $n: ${ahora.motivoEliminacion}';
      }
      return null;
    }
    switch (ahora.estado) {
      case EstadoGuia.enRuta:
        return 'La guía $n volvió a "En ruta".';
      case EstadoGuia.enProcesoTrasbordo:
        return '$quien inició el traslado de $n a ${ahora.destino}.';
      case EstadoGuia.recepcionSucursal:
        return '$quien llegó con $n a ${ahora.destino}.';
      case EstadoGuia.entregado:
        return '$quien entregó la guía $n.';
      case EstadoGuia.finalizado:
        return '$quien entregó la guía $n en agencia.';
      case EstadoGuia.rechazado:
        return ahora.motivoRechazo.isEmpty
            ? '$quien rechazó la guía $n.'
            : '$quien rechazó la guía $n: ${ahora.motivoRechazo}';
    }
  }

  /// La sucursal cuyo perímetro contiene el punto (la más cercana si hay
  /// varias); null si no está dentro de ninguna. Lo mismo decide el backend.
  Sucursal? sucursalEnPunto(double lat, double lng) {
    Sucursal? mejor;
    var menor = double.infinity;
    for (final s in _sucursales) {
      final d = distanciaMetros(lat, lng, s.lat, s.lng);
      if (d <= s.radioM && d < menor) {
        mejor = s;
        menor = d;
      }
    }
    return mejor;
  }

  Sucursal? sucursalPorNombre(String nombre) {
    final clave = nombre.trim().toLowerCase();
    for (final s in _sucursales) {
      if (s.nombre.toLowerCase() == clave) return s;
    }
    return null;
  }

  Future<void> guardarSucursal(Sucursal sucursal) async {
    await _api.guardarSucursal(sucursal);
    _sucursales = await _api.listarSucursales();
    notifyListeners();
  }

  Future<void> eliminarSucursal(String nombre) async {
    await _api.eliminarSucursal(nombre);
    _sucursales = await _api.listarSucursales();
    notifyListeners();
  }

  List<Guia> guiasDelTransportista(String nombre) {
    return _guias.where((g) => g.transportista == nombre).toList()
      ..sort((a, b) => b.fechaActualizacion.compareTo(a.fechaActualizacion));
  }

  /// Tareas que otro transportista le quiere pasar a [nombre] (esperan que
  /// acepte o rechace).
  List<Guia> transbordosPara(String nombre) => [
    for (final g in _guias)
      if (g.transportista != nombre && g.esTransbordoPara(nombre)) g,
  ];

  /// Transportistas activos a quienes se puede pasar una tarea.
  Future<List<String>> listarTransportistas() => _api.listarTransportistas();

  Future<Guia> pedirTransbordo(Guia guia, String a) async {
    final nueva = await _api.pedirTransbordo(
      guia,
      de: guia.transportista,
      a: a,
    );
    _reemplazar(guia, nueva);
    return nueva;
  }

  Future<Guia> cancelarTransbordo(Guia guia) async {
    final nueva = await _api.cancelarTransbordo(guia);
    _reemplazar(guia, nueva);
    return nueva;
  }

  /// El transportista actual acepta o rechaza el transbordo que le pasaron.
  /// Si lo rechaza, la tarea sale de su vista (vuelve a quien la envió).
  Future<Guia> responderTransbordo(Guia guia, {required bool acepta}) async {
    final nueva = await _api.responderTransbordo(
      guia,
      quien: transportistaActual,
      acepta: acepta,
    );
    _reemplazar(guia, nueva);
    return nueva;
  }

  /// Posición del registro más reciente con ese número (-1 si no hay).
  int _indiceDe(String numeroGuia) {
    var indice = -1;
    for (var i = 0; i < _guias.length; i++) {
      final g = _guias[i];
      if (g.numeroGuia != numeroGuia) continue;
      if (indice == -1 ||
          !g.fechaCreacion.isBefore(_guias[indice].fechaCreacion)) {
        indice = i;
      }
    }
    return indice;
  }

  /// El registro más reciente con ese número de guía.
  Guia? buscarPorNumero(String numeroGuia) {
    final i = _indiceDe(numeroGuia);
    return i == -1 ? null : _guias[i];
  }

  /// Si ese número se registró hace menos de [esperaMismaGuia], desde
  /// cuándo se podrá registrar otra vez; si no, null. Un registro
  /// rechazado no bloquea. Validación local rápida contra la última lista
  /// cargada; la definitiva la hace el backend al confirmar (409).
  DateTime? registroBloqueadoHasta(String numeroGuia, {DateTime? ahora}) {
    final ultima = buscarPorNumero(numeroGuia);
    if (ultima == null || ultima.estado == EstadoGuia.rechazado) return null;
    final libre = ultima.fechaCreacion.add(esperaMismaGuia);
    return (ahora ?? DateTime.now()).isBefore(libre) ? libre : null;
  }

  bool esDuplicado(String numeroGuia) =>
      registroBloqueadoHasta(numeroGuia) != null;

  /// Lee los datos de la foto de una guía con IA (ver
  /// ../services/guias_api.dart). No toca `_guias`/no notifica — es solo
  /// para pre-llenar el formulario de asignación.
  Future<DatosGuiaLeida> leerGuiaConIA(Uint8List fotoBytes) =>
      _api.leerGuiaConIA(fotoBytes);

  Future<Guia> asignarNuevaGuia({
    required String numeroGuia,
    required TipoEntrega tipoEntrega,
    required String origen,
    required String destino,
    required String destinatario,
    required double lat,
    required double lng,
    String? numeroPedido,
    String? numeroEntrega,
  }) async {
    final nueva = await _api.asignarNuevaGuia(
      numeroGuia: numeroGuia,
      tipoEntrega: tipoEntrega,
      origen: origen,
      destino: destino,
      transportista: transportistaActual,
      destinatario: destinatario,
      lat: lat,
      lng: lng,
      numeroPedido: numeroPedido,
      numeroEntrega: numeroEntrega,
    );
    _guias.insert(0, nueva);
    notifyListeners();
    return nueva;
  }

  /// Devuelve el aviso si la foto no se pudo guardar (null si todo bien).
  Future<String?> actualizarEstado(
    String numeroGuia,
    EstadoGuia nuevoEstado, {
    double? lat,
    double? lng,
    bool porAdmin = false,
    Uint8List? foto,
  }) async {
    final (actualizada, avisoFoto) = await _api.actualizarEstado(
      numeroGuia,
      nuevoEstado,
      lat: lat,
      lng: lng,
      porAdmin: porAdmin,
      foto: foto,
    );
    final index = _indiceDe(numeroGuia);
    if (index != -1) {
      _guias[index] = actualizada;
    }
    notifyListeners();
    return avisoFoto;
  }

  Future<Uint8List> fotoEntrega(Guia guia) => _api.fotoEntrega(guia);

  /// null mientras no se sabe (o si no se pudo consultar).
  Future<bool?> almacenamientoFotosConfigurado() async {
    try {
      return await _api.almacenamientoFotosConfigurado();
    } catch (_) {
      return null;
    }
  }

  Future<void> rechazarGuia(
    String numeroGuia,
    String motivo, {
    double? lat,
    double? lng,
  }) async {
    final actualizada = await _api.rechazarGuia(
      numeroGuia,
      motivo,
      lat: lat,
      lng: lng,
    );
    final index = _indiceDe(numeroGuia);
    if (index != -1) _guias[index] = actualizada;
    notifyListeners();
  }

  Future<void> corregirNumeroGuia(
    String numeroAnterior,
    String numeroNuevo,
  ) async {
    final actualizada = await _api.corregirNumeroGuia(
      numeroAnterior,
      numeroNuevo,
    );
    final index = _indiceDe(numeroAnterior);
    if (index != -1) {
      _guias[index] = actualizada;
    }
    notifyListeners();
  }

  /// Reemplaza en la lista el registro exacto de [guia] (mismo número y
  /// fecha de creación) por [nueva]; null lo quita.
  void _reemplazar(Guia guia, Guia? nueva) {
    final i = _guias.indexWhere((g) => g.clave == guia.clave);
    if (i == -1) return;
    if (nueva == null) {
      _guias.removeAt(i);
    } else {
      _guias[i] = nueva;
    }
    notifyListeners();
  }

  Future<Guia> cambiarTipoEntrega(
    Guia guia,
    TipoEntrega tipo, {
    String? destino,
    bool porAdmin = false,
  }) async {
    final nueva = await _api.cambiarTipoEntrega(
      guia,
      tipo,
      destino: destino,
      porAdmin: porAdmin,
    );
    _reemplazar(guia, nueva);
    return nueva;
  }

  Future<Guia> pedirEliminacion(Guia guia, String motivo) async {
    final nueva = await _api.pedirEliminacion(guia, motivo);
    _reemplazar(guia, nueva);
    return nueva;
  }

  Future<Guia> retirarPedidoEliminacion(Guia guia) async {
    final nueva = await _api.retirarPedidoEliminacion(guia);
    _reemplazar(guia, nueva);
    return nueva;
  }

  Future<Guia> rechazarEliminacion(Guia guia) async {
    final nueva = await _api.rechazarEliminacion(guia);
    _reemplazar(guia, nueva);
    return nueva;
  }

  Future<void> eliminarGuia(Guia guia) async {
    await _api.eliminarGuia(guia);
    _reemplazar(guia, null);
  }

  Future<String?> eliminarFotoEntrega(Guia guia) async {
    final (nueva, aviso) = await _api.eliminarFotoEntrega(guia);
    _reemplazar(guia, nueva);
    return aviso;
  }

  /// La versión actual (en la lista) de un registro, o null si ya no está.
  Guia? guiaActual(Guia guia) {
    for (final g in _guias) {
      if (g.clave == guia.clave) return g;
    }
    return null;
  }
}
