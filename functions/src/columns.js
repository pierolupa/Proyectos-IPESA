/**
 * Estructura de la hoja "Guias" en Google Sheets (ver ARCHITECTURE.md,
 * sección 3). Fila 1 = encabezados; los datos empiezan en la fila 2.
 * El orden de este arreglo es el orden real de las columnas A..L.
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
});

const ESTADOS_FINALES = new Set([ESTADOS.ENTREGADO, ESTADOS.FINALIZADO]);

const TIPOS_ENTREGA = Object.freeze({
  CLIENTE_FINAL: 'cliente_final',
  AGENCIA: 'agencia',
  ENTRE_SUCURSALES: 'entre_sucursales',
});

module.exports = {
  COLUMNS,
  SHEET_NAME,
  DATA_RANGE,
  HEADER_RANGE,
  ESTADOS,
  ESTADOS_FINALES,
  TIPOS_ENTREGA,
};
