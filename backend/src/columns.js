/**
 * Estructura de la hoja "Guias" en Google Sheets (ver ARCHITECTURE.md,
 * sección 3). Fila 1 = encabezados; los datos empiezan en la fila 2.
 * El orden de este arreglo es el orden real de las columnas A..S.
 * geo_lat/geo_lng = ubicación del último evento; cierre_* = dónde y cuándo
 * el transportista la cerró (entregado/finalizado), para el mapa del admin.
 * foto_entrega_url = dónde quedó la foto de la entrega en Vercel Blob
 * (privada; se ve con GET /guias/:numeroGuia/foto, ver fotos.js).
 * motivo_rechazo = por qué el transportista rechazó la tarea (estado
 * "rechazado", POST /guias/:numeroGuia/rechazo).
 */
const COLUMNS = [
  'numero_guia',
  'estado',
  'tipo_entrega',
  'origen',
  'destino',
  'transportista',
  'destinatario',
  'geo_lat',
  'geo_lng',
  'corregido_por_admin',
  'fecha_creacion',
  'fecha_actualizacion',
  'numero_pedido',
  'numero_entrega',
  'cierre_lat',
  'cierre_lng',
  'fecha_cierre',
  'foto_entrega_url',
  'motivo_rechazo',
];

const SHEET_NAME = 'Guias';
const DATA_RANGE = `${SHEET_NAME}!A2:${String.fromCharCode(64 + COLUMNS.length)}`;
const HEADER_RANGE = `${SHEET_NAME}!A1:${String.fromCharCode(64 + COLUMNS.length)}1`;

const ESTADOS = Object.freeze({
  EN_RUTA: 'en_ruta',
  EN_PROCESO_TRASBORDO: 'en_proceso_trasbordo',
  RECEPCION_SUCURSAL: 'recepcion_sucursal',
  ENTREGADO: 'entregado',
  FINALIZADO: 'finalizado',
  // El transportista no pudo o no quiso hacer la tarea (con motivo).
  RECHAZADO: 'rechazado',
});

// Entregada (cliente final o agencia). Rechazada NO cuenta como entregada.
const ESTADOS_FINALES = new Set([ESTADOS.ENTREGADO, ESTADOS.FINALIZADO]);
// Ya no está activa: entregada o rechazada. Su número de guía se puede
// volver a registrar.
const ESTADOS_CERRADOS = new Set([...ESTADOS_FINALES, ESTADOS.RECHAZADO]);

const TIPOS_ENTREGA = Object.freeze({
  CLIENTE_FINAL: 'cliente_final',
  AGENCIA: 'agencia',
  ENTRE_SUCURSALES: 'entre_sucursales',
});

/**
 * Estructura de la hoja "Usuarios" (login simple, ver README.md — NO es
 * un mecanismo de autenticación seguro: el PIN se guarda como texto
 * plano en la hoja. Sirve solo para pruebas internas del equipo.
 */
const USUARIOS_COLUMNS = ['nombre', 'rol', 'pin', 'activo'];
const USUARIOS_SHEET_NAME = 'Usuarios';
const USUARIOS_DATA_RANGE = `${USUARIOS_SHEET_NAME}!A2:${String.fromCharCode(
  64 + USUARIOS_COLUMNS.length,
)}`;

/**
 * Hoja "Sucursales": el perímetro (círculo) de cada sucursal, que el
 * administrador marca en el mapa. La recepción de un traslado entre
 * sucursales solo se acepta con el GPS dentro de ese círculo.
 */
const SUCURSALES_COLUMNS = ['nombre', 'lat', 'lng', 'radio_m'];
const SUCURSALES_SHEET_NAME = 'Sucursales';
const SUCURSALES_DATA_RANGE = `${SUCURSALES_SHEET_NAME}!A2:${String.fromCharCode(
  64 + SUCURSALES_COLUMNS.length,
)}`;

const ROLES = Object.freeze({
  TRANSPORTISTA: 'transportista',
  ADMINISTRADOR: 'administrador',
  // Equipo comercial: rastrea todas las guías (solo lectura). Se da de
  // alta a mano en la hoja "Usuarios", igual que los administradores.
  COMERCIAL: 'comercial',
});

module.exports = {
  COLUMNS,
  SHEET_NAME,
  DATA_RANGE,
  HEADER_RANGE,
  ESTADOS,
  ESTADOS_FINALES,
  ESTADOS_CERRADOS,
  TIPOS_ENTREGA,
  USUARIOS_COLUMNS,
  USUARIOS_SHEET_NAME,
  USUARIOS_DATA_RANGE,
  SUCURSALES_COLUMNS,
  SUCURSALES_SHEET_NAME,
  SUCURSALES_DATA_RANGE,
  ROLES,
};
