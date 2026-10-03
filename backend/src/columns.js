/**
 * Estructura de la hoja "Guias" en Google Sheets (ver ARCHITECTURE.md,
 * sección 3). Fila 1 = encabezados; los datos empiezan en la fila 2.
 * El orden de este arreglo es el orden real de las columnas A..AC.
 * geo_lat/geo_lng = ubicación del último evento; cierre_* = dónde y cuándo
 * el transportista la cerró (entregado/finalizado), para el mapa del admin.
 * foto_entrega_url = dónde quedó la foto de la entrega en Vercel Blob
 * (privada; se ve con GET /guias/:numeroGuia/foto, ver fotos.js).
 * motivo_rechazo = por qué el transportista rechazó la tarea (estado
 * "rechazado", POST /guias/:numeroGuia/rechazo).
 * eliminacion = el transportista pidió borrar la tarea ('pendiente') y
 * espera que el administrador lo apruebe; 'rechazada' si el administrador
 * no lo aprobó. motivo_eliminacion = por qué lo pidió.
 * transbordo_estado = el transportista pasó la tarea a otro: 'pendiente'
 * (espera que transbordo_a acepte), 'rechazado' (transbordo_a no aceptó;
 * la tarea sigue con quien la envió) o 'aceptado' (transbordo_de la envió
 * y ahora la tiene el transportista actual).
 * despacho_corte = código del Despacho Corte (ej. DC-261001-1542-K7) si la
 * guía salió en uno: todas las de un mismo corte salen juntas y llegan
 * juntas (POST /despachos-corte y /despachos-corte/:id/llegada).
 * agencia_razon_social, agencia_ruc, agencia_monto = el comprobante que da
 * la agencia de transporte (boleta, factura o vale de encomienda) cuando
 * viene pegado en la foto de la guía: quién lo emitió, su RUC y el total
 * pagado; agencia_comprobante es su número (ej. F017-0034441), para no
 * sumar dos veces el monto si el mismo comprobante está en varias guías.
 * La IA los lee aunque la entrega no esté marcada como agencia.
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
  'eliminacion',
  'motivo_eliminacion',
  'transbordo_estado',
  'transbordo_a',
  'transbordo_de',
  'despacho_corte',
  'agencia_razon_social',
  'agencia_ruc',
  'agencia_monto',
  'agencia_comprobante',
];

const ELIMINACION = Object.freeze({
  PENDIENTE: 'pendiente',
  RECHAZADA: 'rechazada',
});

const TRANSBORDO = Object.freeze({
  PENDIENTE: 'pendiente',
  RECHAZADO: 'rechazado',
  ACEPTADO: 'aceptado',
});

/** "A" para 1, "Z" para 26, "AA" para 27... */
function letraColumna(numero) {
  let n = numero;
  let letras = '';
  while (n > 0) {
    const resto = (n - 1) % 26;
    letras = String.fromCharCode(65 + resto) + letras;
    n = Math.floor((n - 1) / 26);
  }
  return letras;
}

const SHEET_NAME = 'Guias';
const DATA_RANGE = `${SHEET_NAME}!A2:${letraColumna(COLUMNS.length)}`;
const HEADER_RANGE = `${SHEET_NAME}!A1:${letraColumna(COLUMNS.length)}1`;

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
  letraColumna,
  SHEET_NAME,
  DATA_RANGE,
  HEADER_RANGE,
  ESTADOS,
  ESTADOS_FINALES,
  ESTADOS_CERRADOS,
  ELIMINACION,
  TIPOS_ENTREGA,
  USUARIOS_COLUMNS,
  USUARIOS_SHEET_NAME,
  USUARIOS_DATA_RANGE,
  SUCURSALES_COLUMNS,
  SUCURSALES_SHEET_NAME,
  SUCURSALES_DATA_RANGE,
  ROLES,
  TRANSBORDO,
};
