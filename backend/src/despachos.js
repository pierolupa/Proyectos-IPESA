/*
 * Hoja externa "Despachos Ate" (lógica pura, sin llamar a Google).
 *
 * Es el registro de lo que sale del Almacén Ate, que lleva otra persona. La
 * app solo la lee, nunca escribe en ella, y de cada fila toma lo mínimo:
 * guía, cliente, fecha, pedido y entrega. Las guías que ya están en la base
 * de la app no se repiten.
 */

// Se puede cambiar con DESPACHOS_SHEET_ID (no es un secreto: solo el ID).
const DESPACHOS_SHEET_ID_POR_DEFECTO = '1YZtXTL1eb1enoiTUMR5BQ8VrWhlpx2lqnteMS5a_RhY';
const DESPACHOS_PESTANA = 'Base de datos';

function despachosSheetId() {
  return process.env.DESPACHOS_SHEET_ID || DESPACHOS_SHEET_ID_POR_DEFECTO;
}

const normalizar = (t) =>
  String(t ?? '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .trim()
    .toLowerCase();

/** Dónde está cada dato en la fila de encabezados (por nombre, no posición). */
function columnasDespachos(encabezado) {
  const buscar = (...nombres) =>
    encabezado.findIndex((h) => nombres.some((n) => normalizar(h).startsWith(n)));
  const cols = {
    fecha: buscar('fecha de extraccion', 'fecha'),
    hora: buscar('hora'),
    guia: buscar('nro de guia', 'numero de guia', 'guia'),
    cliente: buscar('cliente'),
    pedido: buscar('pedido'),
    entrega: buscar('entrega'),
    // En la hoja se llama "Surcusal ipesa" (informativo).
    sucursal: buscar('surcusal', 'sucursal'),
    transporte: buscar('transporte'),
  };
  // Si a la columna de fechas le borraron el encabezado, es la que está sin
  // nombre justo antes de "Hora" (o la A, si es la que quedó vacía).
  if (cols.fecha < 0) {
    const sinNombre = (i) => i >= 0 && normalizar(encabezado[i]) === '';
    if (cols.hora > 0 && sinNombre(cols.hora - 1)) cols.fecha = cols.hora - 1;
    else if (sinNombre(0) && cols.guia !== 0) cols.fecha = 0;
  }
  if (cols.fecha < 0 || cols.guia < 0) {
    throw new Error(
      'La hoja Despachos Ate no tiene las columnas "Fecha" y "Nro de guia" en la fila 1 '
      + `de la pestaña "${DESPACHOS_PESTANA}".`,
    );
  }
  return cols;
}

// Perú está en UTC-5 todo el año.
const DESFASE_PERU_MS = 5 * 60 * 60 * 1000;
const DIA_MS = 24 * 60 * 60 * 1000;
// Las fechas de Sheets (SERIAL_NUMBER) cuentan días desde el 30/12/1899.
const SERIAL_EPOCA_MS = Date.UTC(1899, 11, 30);

/** Fecha (y hora) de la hoja, en hora de Perú → instante en ms (UTC). */
function instanteDe(fecha, hora) {
  if (typeof fecha !== 'number' || !Number.isFinite(fecha)) return null;
  const dia = Math.floor(fecha);
  const fraccion = typeof hora === 'number' && Number.isFinite(hora) ? hora % 1 : fecha % 1;
  return SERIAL_EPOCA_MS + Math.round((dia + fraccion) * DIA_MS) + DESFASE_PERU_MS;
}

/** Un número de la hoja como texto: 4900107659 → "4900107659". */
function textoDe(valor) {
  if (valor === null || valor === undefined) return '';
  if (typeof valor === 'number') return Number.isInteger(valor) ? String(valor) : String(valor);
  return String(valor).trim();
}

/**
 * Las filas leídas → despachos { numero_guia, cliente, fecha, numero_pedido,
 * numero_entrega, sucursal, transporte }.
 */
function filasADespachos(filas, cols) {
  const lista = [];
  for (const f of filas) {
    const numero = textoDe(f[cols.guia]);
    const t = instanteDe(f[cols.fecha], cols.hora >= 0 ? f[cols.hora] : null);
    if (!numero || t === null) continue;
    lista.push({
      numero_guia: numero,
      cliente: cols.cliente >= 0 ? textoDe(f[cols.cliente]) : '',
      fecha: new Date(t).toISOString(),
      numero_pedido: cols.pedido >= 0 ? textoDe(f[cols.pedido]) : '',
      numero_entrega: cols.entrega >= 0 ? textoDe(f[cols.entrega]) : '',
      sucursal: cols.sucursal >= 0 ? textoDe(f[cols.sucursal]) : '',
      transporte: cols.transporte >= 0 ? textoDe(f[cols.transporte]) : '',
    });
  }
  return lista;
}

/** El día (serial de Sheets) de un instante, en hora de Perú. */
function serialDeDia(ms) {
  return Math.floor((ms - DESFASE_PERU_MS - SERIAL_EPOCA_MS) / DIA_MS);
}

/**
 * Posiciones de la primera y la última fila cuyo día cae en [desde, hasta),
 * a partir de la columna de fechas (serial). null si ninguna.
 */
function filasDelRango(seriales, desdeMs, hastaMs) {
  const desde = Number.isFinite(desdeMs) ? serialDeDia(desdeMs) : -Infinity;
  // `hasta` es exclusivo: el día de un instante justo a medianoche no entra.
  const hasta = Number.isFinite(hastaMs) ? serialDeDia(hastaMs - 1) : Infinity;
  let primera = -1;
  let ultima = -1;
  seriales.forEach((s, i) => {
    if (typeof s !== 'number') return;
    const dia = Math.floor(s);
    if (dia < desde || dia > hasta) return;
    if (primera === -1) primera = i;
    ultima = i;
  });
  return primera === -1 ? null : { primera, ultima };
}

const claveGuia = (numero) => String(numero).replace(/\s+/g, '').toUpperCase();

/**
 * Empresas de transporte cuyas guías salen siempre, aunque la guía también
 * esté en la base de la app (entonces aparece dos veces).
 */
const TRANSPORTES_SIEMPRE = new Set(['toscano', 'log', 'aval', 'amazon']);

const siempreSale = (d) => TRANSPORTES_SIEMPRE.has(normalizar(d.transporte));

/**
 * Los despachos en [desde, hasta) que NO están en la base de la app
 * (`numerosEnApp`: los números de guía de la app), más los de Toscano, Log,
 * Aval y Amazon aunque estén. Una guía repetida en la hoja sale una vez.
 */
function despachosNuevos(despachos, numerosEnApp, desdeMs, hastaMs) {
  const enApp = new Set([...numerosEnApp].map(claveGuia));
  const vistos = new Set();
  return despachos
    .filter((d) => {
      const t = Date.parse(d.fecha);
      if (Number.isFinite(desdeMs) && t < desdeMs) return false;
      if (Number.isFinite(hastaMs) && t >= hastaMs) return false;
      const clave = claveGuia(d.numero_guia);
      if (vistos.has(clave)) return false;
      if (enApp.has(clave) && !siempreSale(d)) return false;
      vistos.add(clave);
      return true;
    })
    .sort((a, b) => b.fecha.localeCompare(a.fecha));
}

module.exports = {
  DESPACHOS_PESTANA,
  despachosSheetId,
  columnasDespachos,
  filasADespachos,
  filasDelRango,
  despachosNuevos,
  instanteDe,
};
