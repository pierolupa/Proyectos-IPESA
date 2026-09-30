const { google } = require('googleapis');
const { GoogleAuth } = require('google-auth-library');
const {
  COLUMNS,
  SHEET_NAME,
  TRANSBORDO,
  USUARIOS_COLUMNS,
  USUARIOS_DATA_RANGE,
  SUCURSALES_COLUMNS,
  SUCURSALES_SHEET_NAME,
  SUCURSALES_DATA_RANGE,
} = require('./columns');

const SCOPES = ['https://www.googleapis.com/auth/spreadsheets'];

let sheetsClientPromise = null;

/**
 * Cliente autenticado de la API de Sheets.
 *
 * Vercel no es Google Cloud, así que no hay una identidad automática:
 * la cuenta de servicio se pasa completa (JSON) en la variable de entorno
 * GOOGLE_SERVICE_ACCOUNT_KEY. Si esa variable no está (por ejemplo,
 * corriendo dentro de Google Cloud), se usan las credenciales por defecto
 * del entorno (Application Default Credentials) como respaldo.
 */
function getAuthOptions() {
  const rawKey = process.env.GOOGLE_SERVICE_ACCOUNT_KEY;
  if (!rawKey) {
    return { scopes: SCOPES };
  }
  let credentials;
  try {
    credentials = JSON.parse(rawKey);
  } catch (err) {
    throw new Error(
      'GOOGLE_SERVICE_ACCOUNT_KEY no es un JSON válido. Debe ser el contenido completo del archivo de la cuenta de servicio.',
    );
  }
  return { credentials, scopes: SCOPES };
}

function getSheetsClient() {
  if (!sheetsClientPromise) {
    const auth = new GoogleAuth(getAuthOptions());
    sheetsClientPromise = auth.getClient().then(
      (authClient) => google.sheets({ version: 'v4', auth: authClient }),
    );
  }
  return sheetsClientPromise;
}

function requireSheetId() {
  const sheetId = process.env.SHEET_ID;
  if (!sheetId) {
    throw new Error(
      'Falta la variable de entorno SHEET_ID (ID de la hoja de cálculo de guías).',
    );
  }
  return sheetId;
}

/*
 * Columnas de la hoja de guías POR NOMBRE. Cada dato se ubica por el
 * encabezado de su columna (fila 1), no por su posición: si alguien
 * inserta, mueve o agrega columnas propias, todo se sigue leyendo bien y
 * las columnas que el servidor no conoce nunca se tocan. Si falta alguna
 * de las que usa, se agrega sola AL FINAL de los encabezados.
 */
const ULTIMA_COLUMNA = 'ZZ';
const TRANSBORDOS_VALIDOS = new Set(Object.values(TRANSBORDO));

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

const normalizar = (texto) => String(texto ?? '').trim().toLowerCase();

/** Posición de cada columna conocida según la fila de encabezados. */
function mapearColumnas(encabezados) {
  const nombres = (encabezados || []).map(normalizar);
  const indices = {};
  for (const col of COLUMNS) {
    const i = nombres.indexOf(col);
    if (i !== -1) indices[col] = i;
  }
  // Sin ningún encabezado reconocible: el orden de siempre (A..).
  if (Object.keys(indices).length === 0) {
    COLUMNS.forEach((col, i) => {
      indices[col] = i;
    });
  }
  const ancho = Math.max(nombres.length, ...Object.values(indices).map((i) => i + 1));
  return { indices, ancho };
}

// Las columnas de la última lectura (para escribir en las mismas).
let columnasGuias = null;

/**
 * Agrega al final de la fila 1 los encabezados que falten. Si no se puede
 * (por ejemplo, sin permiso de escritura), esas columnas se leen vacías.
 */
async function completarEncabezados(sheets, spreadsheetId, encabezados) {
  const mapa = mapearColumnas(encabezados);
  const faltan = COLUMNS.filter((col) => mapa.indices[col] === undefined);
  if (faltan.length === 0) return mapa;
  // Después de la última columna con encabezado.
  let ultima = 0;
  (encabezados || []).forEach((h, i) => {
    if (normalizar(h)) ultima = i + 1;
  });
  const desde = letraColumna(ultima + 1);
  const hasta = letraColumna(ultima + faltan.length);
  try {
    await sheets.spreadsheets.values.update({
      spreadsheetId,
      range: `${SHEET_NAME}!${desde}1:${hasta}1`,
      valueInputOption: 'RAW',
      requestBody: { values: [faltan] },
    });
    faltan.forEach((col, k) => {
      mapa.indices[col] = ultima + k;
    });
    mapa.ancho = Math.max(mapa.ancho, ultima + faltan.length);
  } catch (err) {
    console.error(`No se pudieron agregar las columnas ${faltan.join(', ')}:`, err.message);
  }
  return mapa;
}

/** Las columnas de la hoja (de la última lectura, o leyendo la fila 1). */
async function obtenerColumnas(sheets, spreadsheetId) {
  if (columnasGuias) return columnasGuias;
  const res = await sheets.spreadsheets.values.get({
    spreadsheetId,
    range: `${SHEET_NAME}!A1:${ULTIMA_COLUMNA}1`,
  });
  const encabezados = (res.data.values || [])[0] || [];
  columnasGuias = await completarEncabezados(sheets, spreadsheetId, encabezados);
  return columnasGuias;
}

const MAPA_POR_POSICION = mapearColumnas([]);

function rowToGuia(row, rowNumber, mapa = MAPA_POR_POSICION) {
  const guia = {};
  for (const col of COLUMNS) {
    const i = mapa.indices[col];
    const valor = i === undefined ? '' : row[i];
    guia[col] = valor === undefined || valor === null ? '' : valor;
  }
  // Ver el comentario equivalente en rowToUsuario: Sheets puede devolver
  // "TRUE"/"FALSE" en mayúsculas para valores que reconoce como booleanos.
  guia.corregido_por_admin =
    guia.corregido_por_admin === true ||
    String(guia.corregido_por_admin).trim().toLowerCase() === 'true';
  guia.estado = String(guia.estado).trim();
  guia.numero_guia = String(guia.numero_guia).trim();
  // Un valor que no es de transbordo (por ejemplo, un dato viejo en esa
  // columna) no cuenta como transbordo.
  const transbordo = normalizar(guia.transbordo_estado);
  guia.transbordo_estado = TRANSBORDOS_VALIDOS.has(transbordo) ? transbordo : '';
  guia._row = rowNumber; // fila real en la hoja (1-indexed), uso interno
  // La fila tal cual, para no borrar columnas que el servidor no conoce
  // (uso interno, como _row: la API no la devuelve).
  guia._fila = row;
  return guia;
}

/** La fila a escribir: la original con las columnas conocidas al día. */
function guiaToRow(guia, mapa = MAPA_POR_POSICION) {
  const fila = [...(guia._fila || [])];
  while (fila.length < mapa.ancho) fila.push('');
  for (const col of COLUMNS) {
    const i = mapa.indices[col];
    if (i === undefined) continue;
    const value = guia[col];
    fila[i] = value === undefined || value === null ? '' : value;
  }
  return fila.map((v) => (v === undefined || v === null ? '' : v));
}

/**
 * Lee todas las guías directamente de la hoja (sin caché). Las filas sin
 * número de guía (vacías o a medio llenar) se saltan.
 */
async function leerGuiasDeHoja() {
  const sheets = await getSheetsClient();
  const spreadsheetId = requireSheetId();
  const res = await sheets.spreadsheets.values.get({
    spreadsheetId,
    range: `${SHEET_NAME}!A1:${ULTIMA_COLUMNA}`,
  });
  const [encabezados = [], ...filas] = res.data.values || [];
  columnasGuias = await completarEncabezados(sheets, spreadsheetId, encabezados);
  // La fila de datos N (0-indexed) corresponde a la fila real N+2 (por el encabezado).
  return filas
    .map((fila, i) => rowToGuia(fila, i + 2, columnasGuias))
    .filter((g) => g.numero_guia !== '');
}

/*
 * Caché corta de la hoja de guías. Cada celular pide la lista cada 15-60 s
 * y Google Sheets permite ~60 lecturas por minuto a la cuenta de servicio:
 * sin caché, cada pedido era una lectura. Con ella, la hoja se lee como
 * mucho una vez cada TTL_CACHE_MS por instancia del servidor, y los pedidos
 * que llegan juntos comparten la misma lectura. Cualquier escritura desde
 * esta instancia la borra. Las rutas que escriben (asignar, cambiar estado,
 * rechazar, corregir) leen con { fresco: true }: nunca deciden ni
 * sobrescriben una fila con datos de hace unos segundos.
 */
const TTL_CACHE_MS = 10000;
let cacheGuias = null; // { guias, vence }
let lecturaEnCurso = null;

// Copias: quien llama puede modificar la guía antes de guardarla.
function copiar(guias) {
  return guias.map((g) => ({ ...g }));
}

/** Lee todas las guías (de la caché si es reciente, salvo `fresco`). */
async function listarGuias({ fresco = false } = {}) {
  if (!fresco && cacheGuias && Date.now() < cacheGuias.vence) {
    return copiar(cacheGuias.guias);
  }
  if (!fresco && lecturaEnCurso) return copiar(await lecturaEnCurso);
  const lectura = leerGuiasDeHoja();
  if (!fresco) lecturaEnCurso = lectura;
  try {
    const guias = await lectura;
    cacheGuias = { guias, vence: Date.now() + TTL_CACHE_MS };
    return copiar(guias);
  } finally {
    if (lecturaEnCurso === lectura) lecturaEnCurso = null;
  }
}

function invalidarCacheGuias() {
  cacheGuias = null;
}

function momentoDeRegistro(guia) {
  const t = Date.parse(guia.fecha_creacion || guia.fecha_actualizacion);
  return Number.isNaN(t) ? 0 : t;
}

/**
 * La guía con ese número. Un mismo número puede registrarse más de una
 * vez (con 2 horas de diferencia, ver app.js): se devuelve el registro
 * más reciente.
 */
async function buscarPorNumero(numeroGuia, opciones) {
  const guias = (await listarGuias(opciones)).filter(
    (g) => g.numero_guia === numeroGuia,
  );
  if (guias.length === 0) return null;
  return guias.reduce((a, b) =>
    momentoDeRegistro(b) > momentoDeRegistro(a) ||
    (momentoDeRegistro(b) === momentoDeRegistro(a) && b._row > a._row)
      ? b
      : a,
  );
}

/** Agrega una nueva fila (nueva guía). */
async function crearGuia(guia) {
  const sheets = await getSheetsClient();
  const spreadsheetId = requireSheetId();
  const mapa = await obtenerColumnas(sheets, spreadsheetId);
  await sheets.spreadsheets.values.append({
    spreadsheetId,
    range: `${SHEET_NAME}!A1`,
    valueInputOption: 'RAW',
    insertDataOption: 'INSERT_ROWS',
    requestBody: { values: [guiaToRow(guia, mapa)] },
  }).finally(invalidarCacheGuias);
}

/**
 * Sobrescribe la fila de una guía existente: las columnas conocidas con
 * sus datos, las demás con lo que ya tenían.
 */
async function actualizarGuia(rowNumber, guia) {
  const sheets = await getSheetsClient();
  const spreadsheetId = requireSheetId();
  const mapa = await obtenerColumnas(sheets, spreadsheetId);
  const fila = guiaToRow(guia, mapa);
  await sheets.spreadsheets.values.update({
    spreadsheetId,
    range: `${SHEET_NAME}!A${rowNumber}:${letraColumna(fila.length)}${rowNumber}`,
    valueInputOption: 'RAW',
    requestBody: { values: [fila] },
  }).finally(invalidarCacheGuias);
}

function rowToUsuario(row) {
  const usuario = {};
  USUARIOS_COLUMNS.forEach((col, i) => {
    usuario[col] = row[i] ?? '';
  });
  // Google Sheets autoformatea "true"/"false" escrito a mano como
  // "TRUE"/"FALSE" (mayúsculas) al mostrarlo, y la API de Sheets devuelve
  // ese mismo texto formateado — de ahí la comparación insensible a
  // mayúsculas en vez de solo 'true'.
  usuario.activo =
    usuario.activo === true ||
    String(usuario.activo).trim().toLowerCase() === 'true';
  return usuario;
}

function usuarioToRow(usuario) {
  return USUARIOS_COLUMNS.map((col) => {
    const value = usuario[col];
    return value === undefined || value === null ? '' : value;
  });
}

/** Lee todos los usuarios de la hoja "Usuarios" (login simple). */
async function listarUsuarios() {
  const sheets = await getSheetsClient();
  const spreadsheetId = requireSheetId();
  const res = await sheets.spreadsheets.values.get({
    spreadsheetId,
    range: USUARIOS_DATA_RANGE,
  });
  const rows = res.data.values || [];
  return rows.map(rowToUsuario);
}

/** Agrega una nueva fila a la hoja "Usuarios" (auto-registro). */
async function crearUsuario(usuario) {
  const sheets = await getSheetsClient();
  const spreadsheetId = requireSheetId();
  await sheets.spreadsheets.values.append({
    spreadsheetId,
    range: USUARIOS_DATA_RANGE,
    valueInputOption: 'RAW',
    insertDataOption: 'INSERT_ROWS',
    requestBody: { values: [usuarioToRow(usuario)] },
  });
}

function numeroDeHoja(valor) {
  if (typeof valor === 'number') return valor;
  const n = Number(String(valor).trim().replace(',', '.'));
  return Number.isFinite(n) ? n : null;
}

function rowToSucursal(row, rowNumber) {
  const [nombre = '', lat = '', lng = '', radio = ''] = row;
  return {
    nombre: String(nombre).trim(),
    lat: numeroDeHoja(lat),
    lng: numeroDeHoja(lng),
    radio_m: numeroDeHoja(radio),
    _row: rowNumber,
  };
}

// La pestaña "Sucursales" se crea sola la primera vez, para no pedirle al
// usuario un paso manual más en la hoja.
async function crearHojaSucursales(sheets, spreadsheetId) {
  await sheets.spreadsheets.batchUpdate({
    spreadsheetId,
    requestBody: {
      requests: [{ addSheet: { properties: { title: SUCURSALES_SHEET_NAME } } }],
    },
  });
  await sheets.spreadsheets.values.update({
    spreadsheetId,
    range: `${SUCURSALES_SHEET_NAME}!A1`,
    valueInputOption: 'RAW',
    requestBody: { values: [SUCURSALES_COLUMNS] },
  });
}

/** Lee las sucursales (omite filas borradas/vacías). */
async function listarSucursales() {
  const sheets = await getSheetsClient();
  const spreadsheetId = requireSheetId();
  let res;
  try {
    res = await sheets.spreadsheets.values.get({
      spreadsheetId,
      range: SUCURSALES_DATA_RANGE,
    });
  } catch (err) {
    if (!String(err.message).includes('Unable to parse range')) throw err;
    await crearHojaSucursales(sheets, spreadsheetId);
    return [];
  }
  const rows = res.data.values || [];
  return rows
    .map((row, i) => rowToSucursal(row, i + 2))
    .filter((s) => s.nombre && s.lat !== null && s.lng !== null && s.radio_m !== null);
}

function sucursalToRow(sucursal) {
  return [sucursal.nombre, sucursal.lat, sucursal.lng, sucursal.radio_m];
}

/** Crea la sucursal o, si ya existe una con ese nombre, la reemplaza. */
async function guardarSucursal(sucursal) {
  const sheets = await getSheetsClient();
  const spreadsheetId = requireSheetId();
  const existentes = await listarSucursales();
  const existente = existentes.find(
    (s) => s.nombre.toLowerCase() === sucursal.nombre.toLowerCase(),
  );
  if (existente) {
    await sheets.spreadsheets.values.update({
      spreadsheetId,
      range: `${SUCURSALES_SHEET_NAME}!A${existente._row}:D${existente._row}`,
      valueInputOption: 'RAW',
      requestBody: { values: [sucursalToRow({ ...sucursal, nombre: existente.nombre })] },
    });
    return;
  }
  await sheets.spreadsheets.values.append({
    spreadsheetId,
    range: SUCURSALES_DATA_RANGE,
    valueInputOption: 'RAW',
    insertDataOption: 'INSERT_ROWS',
    requestBody: { values: [sucursalToRow(sucursal)] },
  });
}

/** Borra el contenido de la fila (la fila vacía se ignora al listar). */
/** El id numérico (gid) de una pestaña, necesario para borrar filas. */
async function idDePestana(sheets, spreadsheetId, titulo) {
  const res = await sheets.spreadsheets.get({
    spreadsheetId,
    fields: 'sheets.properties(sheetId,title)',
  });
  const pestana = (res.data.sheets || []).find(
    (s) => s.properties && s.properties.title === titulo,
  );
  if (!pestana) throw new Error(`No existe la pestaña "${titulo}".`);
  return pestana.properties.sheetId;
}

/**
 * Borra de la hoja la fila de una guía (las de abajo suben). Antes vuelve a
 * leer esa fila y confirma que sigue siendo la misma guía: si alguien
 * agregó o borró filas entre medio, no borra la equivocada.
 */
async function eliminarGuia(guia) {
  const sheets = await getSheetsClient();
  const spreadsheetId = requireSheetId();
  const rowNumber = guia._row;
  const mapa = await obtenerColumnas(sheets, spreadsheetId);
  const actual = await sheets.spreadsheets.values.get({
    spreadsheetId,
    range: `${SHEET_NAME}!A${rowNumber}:${ULTIMA_COLUMNA}${rowNumber}`,
  });
  const fila = rowToGuia(((actual.data.values || [])[0]) || [], rowNumber, mapa);
  if (
    fila.numero_guia !== guia.numero_guia ||
    fila.fecha_creacion !== guia.fecha_creacion
  ) {
    invalidarCacheGuias();
    throw Object.assign(new Error('La hoja cambió mientras se borraba; inténtalo de nuevo.'), {
      status: 409,
    });
  }
  const sheetId = await idDePestana(sheets, spreadsheetId, SHEET_NAME);
  await sheets.spreadsheets.batchUpdate({
    spreadsheetId,
    requestBody: {
      requests: [
        {
          deleteDimension: {
            range: {
              sheetId,
              dimension: 'ROWS',
              startIndex: rowNumber - 1,
              endIndex: rowNumber,
            },
          },
        },
      ],
    },
  }).finally(invalidarCacheGuias);
}

async function eliminarSucursal(rowNumber) {
  const sheets = await getSheetsClient();
  const spreadsheetId = requireSheetId();
  await sheets.spreadsheets.values.clear({
    spreadsheetId,
    range: `${SUCURSALES_SHEET_NAME}!A${rowNumber}:D${rowNumber}`,
  });
}

module.exports = {
  listarSucursales,
  guardarSucursal,
  eliminarSucursal,
  rowToSucursal,
  listarGuias,
  invalidarCacheGuias,
  buscarPorNumero,
  crearGuia,
  actualizarGuia,
  eliminarGuia,
  listarUsuarios,
  crearUsuario,
  // Exportadas además para poder testear el parseo sin credenciales reales.
  rowToUsuario,
  rowToGuia,
  guiaToRow,
  mapearColumnas,
  letraColumna,
};
