const { google } = require('googleapis');
const { GoogleAuth } = require('google-auth-library');
const {
  COLUMNS,
  ELIMINACION,
  ESTADOS,
  ESTADOS_FINALES,
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
 * Columnas de la hoja de guías: posición fija, la del arreglo COLUMNS.
 * A..S son las columnas de siempre y se leen por posición, se llame como se
 * llame su encabezado ("Nro Pedido", "Foto"...): esos encabezados nunca se
 * tocan. Las que se agregaron después van a continuación de la S (T..X), y
 * el servidor solo escribe esos encabezados. Lo que haya después de la X
 * se reescribe tal cual estaba.
 */
const ULTIMA_COLUMNA = 'ZZ';
const ANCHO = COLUMNS.length;
const PRIMERA_NUEVA = COLUMNS.indexOf('eliminacion'); // T
const POSICION = Object.fromEntries(COLUMNS.map((col, i) => [col, i]));
const TRANSBORDOS_VALIDOS = new Set(Object.values(TRANSBORDO));
const ELIMINACIONES_VALIDAS = new Set(Object.values(ELIMINACION));
const ESTADOS_VALIDOS = new Set(Object.values(ESTADOS));
const CONOCIDAS = new Set(COLUMNS);
// Columnas que existieron un tiempo y ya no se usan: su lugar se reutiliza.
const RETIRADAS = new Set(['salida_lat', 'salida_lng']);

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
const vacia = (valor) => normalizar(valor) === '';
const celda = (fila, i) => (fila[i] === undefined || fila[i] === null ? '' : fila[i]);

function rowToGuia(row, rowNumber) {
  const guia = {};
  COLUMNS.forEach((col, i) => {
    guia[col] = celda(row, i);
  });
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
  if (!guia.transbordo_estado) {
    guia.transbordo_a = '';
    guia.transbordo_de = '';
  }
  guia._row = rowNumber; // fila real en la hoja (1-indexed), uso interno
  // La fila tal cual, para no borrar lo que haya después de la X
  // (uso interno, como _row: la API no la devuelve).
  guia._fila = row;
  return guia;
}

/** La fila a escribir: la original con A..X al día. */
function guiaToRow(guia) {
  const fila = [...(guia._fila || [])];
  while (fila.length < ANCHO) fila.push('');
  COLUMNS.forEach((col, i) => {
    const value = guia[col];
    fila[i] = value === undefined || value === null ? '' : value;
  });
  return fila.map((v) => (v === undefined || v === null ? '' : v));
}

/**
 * Los encabezados de T en adelante como deben quedar: T..X con su nombre
 * (si están vacíos o tienen el nombre de otra columna del sistema) y,
 * después de la X, sin los nombres de columnas del sistema que una versión
 * anterior agregó ahí. Devuelve { desde, valores } o null si ya están bien.
 * A..S no se tocan nunca.
 */
function encabezadosCorregidos(encabezados) {
  const actuales = (encabezados || []).map((v) => (v === undefined || v === null ? '' : v));
  const nuevos = [...actuales];
  while (nuevos.length < ANCHO) nuevos.push('');
  for (let i = PRIMERA_NUEVA; i < nuevos.length; i++) {
    const nombre = normalizar(nuevos[i]);
    if (i < ANCHO) {
      if (nombre === '' || CONOCIDAS.has(nombre) || RETIRADAS.has(nombre)) {
        nuevos[i] = COLUMNS[i];
      }
    } else if (CONOCIDAS.has(nombre)) {
      nuevos[i] = '';
    }
  }
  const cambiadas = [];
  for (let i = PRIMERA_NUEVA; i < nuevos.length; i++) {
    if (String(nuevos[i]) !== String(actuales[i] ?? '')) cambiadas.push(i);
  }
  if (cambiadas.length === 0) return null;
  const desde = cambiadas[0];
  const hasta = cambiadas[cambiadas.length - 1];
  return { desde, valores: nuevos.slice(desde, hasta + 1) };
}

/**
 * Columnas del sistema cuyo encabezado está (de T en adelante) en otra
 * posición que la suya: así las dejó una versión anterior que leía por
 * nombre de encabezado y agregó T..AE con numero_pedido, numero_entrega...
 * Devuelve { columna: posición }; vacío si la hoja está en orden.
 */
function columnasMovidas(encabezados) {
  const movidas = {};
  (encabezados || []).forEach((valor, i) => {
    const nombre = normalizar(valor);
    if (i < PRIMERA_NUEVA || !CONOCIDAS.has(nombre)) return;
    if (POSICION[nombre] !== i && movidas[nombre] === undefined) movidas[nombre] = i;
  });
  return movidas;
}

/**
 * ¿El valor de la celda `i` es del dato que va en esa posición? Solo se
 * pregunta por T..X, donde la versión anterior escribió otros datos
 * (pedido, entrega, coordenadas y fecha de cierre).
 */
function esDeSuColumna(fila, i) {
  const valor = normalizar(fila[i]);
  switch (COLUMNS[i]) {
    case 'eliminacion':
      return ELIMINACIONES_VALIDAS.has(valor);
    case 'motivo_eliminacion':
      return ELIMINACIONES_VALIDAS.has(normalizar(fila[POSICION.eliminacion]));
    case 'transbordo_estado':
      return TRANSBORDOS_VALIDOS.has(valor);
    case 'transbordo_a':
    case 'transbordo_de':
      return TRANSBORDOS_VALIDOS.has(normalizar(fila[POSICION.transbordo_estado]));
    case 'despacho_corte':
      return valor === '' || valor.startsWith('dc-');
    default:
      return true;
  }
}

/** Los datos movidos que de verdad están en la fila: { columna: valor }. */
function datosMovidos(fila, movidas) {
  const datos = {};
  for (const [col, i] of Object.entries(movidas)) {
    if (i < ANCHO && esDeSuColumna(fila, i)) continue;
    datos[col] = celda(fila, i);
  }
  // Coordenadas de cierre sin fecha de cierre no son de una entrega (por
  // ejemplo, restos de una columna retirada).
  if (vacia(datos.fecha_cierre)) {
    delete datos.cierre_lat;
    delete datos.cierre_lng;
  }
  return datos;
}

/**
 * La fila con cada dato movido de vuelta en su columna (A..X) y las celdas
 * donde estaba, vacías. Un dato movido reemplaza al de su columna solo si
 * no está vacío.
 */
function filaEnOrden(fila, movidas) {
  const datos = {};
  COLUMNS.forEach((col, i) => {
    datos[col] = celda(fila, i);
  });
  const movidos = datosMovidos(fila, movidas);
  for (const col of Object.keys(movidos)) {
    const i = movidas[col];
    if (i < ANCHO) datos[COLUMNS[i]] = '';
  }
  for (const [col, valor] of Object.entries(movidos)) {
    if (!vacia(valor)) datos[col] = valor;
  }
  if (!ELIMINACIONES_VALIDAS.has(normalizar(datos.eliminacion))) {
    datos.eliminacion = '';
    datos.motivo_eliminacion = '';
  }
  if (!TRANSBORDOS_VALIDOS.has(normalizar(datos.transbordo_estado))) {
    datos.transbordo_estado = '';
    datos.transbordo_a = '';
    datos.transbordo_de = '';
  }
  const nueva = fila.map((v) => (v === undefined || v === null ? '' : v));
  while (nueva.length < ANCHO) nueva.push('');
  COLUMNS.forEach((col, i) => {
    nueva[i] = datos[col];
  });
  for (const i of Object.values(movidas)) {
    if (i >= ANCHO && i < nueva.length) nueva[i] = '';
  }
  return nueva;
}

/**
 * Una guía que quedó corrida a la derecha (por ejemplo, desde la columna V
 * en vez de la A): la fila está vacía hasta donde empieza, ahí está el
 * número de guía y en la celda siguiente un estado válido. Devuelve cuántas
 * columnas está corrida, o 0 si la fila está bien.
 */
function desplazamiento(fila) {
  if (!vacia(fila[0])) return 0;
  const inicio = fila.findIndex((v) => !vacia(v));
  if (inicio <= 0) return 0;
  return ESTADOS_VALIDOS.has(normalizar(fila[inicio + 1])) ? inicio : 0;
}

/** La fila corrida, desde la columna A (las celdas donde estaba, vacías). */
function filaDesdeA(fila, corrida) {
  return [...fila.slice(corrida), ...Array(corrida).fill('')];
}

function mismaFila(a, b) {
  const largo = Math.max(a.length, b.length);
  for (let i = 0; i < largo; i++) {
    if (String(a[i] ?? '') !== String(b[i] ?? '')) return false;
  }
  return true;
}

/**
 * Restos sueltos de una entrega (coordenadas, fecha y foto, sin número de
 * guía) que la versión anterior escribió en una fila vacía: se pasan a la
 * guía entregada sin foto cuya última actualización es esa misma fecha de
 * cierre, si hay exactamente una. Si no, la fila queda como está.
 */
function unirRestoDeEntrega(filas, k, movidas) {
  const movidos = datosMovidos(filas[k], movidas);
  const fecha = String(movidos.fecha_cierre ?? '').trim();
  if (fecha === '' || vacia(movidos.foto_entrega_url)) return false;
  const candidatas = [];
  filas.forEach((fila, i) => {
    if (i === k || vacia(fila[0])) return;
    const entregada = ESTADOS_FINALES.has(normalizar(fila[POSICION.estado]));
    const sinFoto = vacia(fila[POSICION.foto_entrega_url]);
    const mismaFecha = [fila[POSICION.fecha_actualizacion], fila[POSICION.fecha_cierre]]
      .some((v) => String(v ?? '').trim() === fecha);
    if (entregada && sinFoto && mismaFecha) candidatas.push(i);
  });
  if (candidatas.length !== 1) return false;
  const destino = [...filas[candidatas[0]]];
  while (destino.length < ANCHO) destino.push('');
  for (const col of ['cierre_lat', 'cierre_lng', 'fecha_cierre', 'foto_entrega_url']) {
    const valor = movidos[col];
    if (valor !== undefined && !vacia(valor) && vacia(destino[POSICION[col]])) {
      destino[POSICION[col]] = valor;
    }
  }
  filas[candidatas[0]] = destino;
  const resto = [...filas[k]];
  for (const col of Object.keys(movidos)) resto[movidas[col]] = '';
  filas[k] = resto;
  return true;
}

/**
 * Pone la hoja en orden: guías corridas a la derecha de vuelta a la
 * columna A y, si una versión anterior dejó datos en otras columnas (ver
 * columnasMovidas), cada uno de vuelta en la suya. Devuelve las filas en
 * orden, los índices de las que cambiaron y los encabezados a corregir.
 */
function ordenarHoja(encabezados, filasLeidas) {
  const movidas = columnasMovidas(encabezados);
  const hayMovidas = Object.keys(movidas).length > 0;
  const filas = filasLeidas.map((f) => [...(f || [])]);
  const sueltas = [];
  filas.forEach((fila, i) => {
    let nueva = fila;
    const corrida = desplazamiento(nueva);
    if (corrida > 0) nueva = filaDesdeA(nueva, corrida);
    if (hayMovidas) {
      if (vacia(nueva[0])) {
        sueltas.push(i);
        return;
      }
      nueva = filaEnOrden(nueva, movidas);
    }
    filas[i] = nueva;
  });
  for (const i of sueltas) unirRestoDeEntrega(filas, i, movidas);
  const cambiadas = [];
  filas.forEach((fila, i) => {
    if (!mismaFila(fila, filasLeidas[i] || [])) cambiadas.push(i);
  });
  return { filas, cambiadas, encabezados: encabezadosCorregidos(encabezados) };
}

/**
 * Lee todas las guías directamente de la hoja (sin caché). Si la hoja no
 * está en orden (ver ordenarHoja), la ordena con una sola escritura. Las
 * filas sin número de guía (vacías o a medio llenar) se saltan.
 */
async function leerGuiasDeHoja() {
  const sheets = await getSheetsClient();
  const spreadsheetId = requireSheetId();
  const res = await sheets.spreadsheets.values.get({
    spreadsheetId,
    range: `${SHEET_NAME}!A1:${ULTIMA_COLUMNA}`,
  });
  const valores = res.data.values || [];
  const [encabezados = [], ...filasLeidas] = valores;

  const orden = ordenarHoja(encabezados, filasLeidas);
  const data = orden.cambiadas.map((i) => {
    const numeroDeFila = i + 2; // por el encabezado
    const fila = orden.filas[i];
    return {
      range: `${SHEET_NAME}!A${numeroDeFila}:${letraColumna(fila.length)}${numeroDeFila}`,
      values: [fila],
    };
  });
  if (orden.encabezados) {
    const { desde, valores: nombres } = orden.encabezados;
    data.push({
      range: `${SHEET_NAME}!${letraColumna(desde + 1)}1:${letraColumna(desde + nombres.length)}1`,
      values: [nombres],
    });
  }
  if (data.length > 0) {
    try {
      await sheets.spreadsheets.values.batchUpdate({
        spreadsheetId,
        requestBody: { valueInputOption: 'RAW', data },
      });
      if (orden.cambiadas.length > 0) {
        console.log(
          `Hoja de guías ordenada: filas ${orden.cambiadas.map((i) => i + 2).join(', ')}.`,
        );
      }
    } catch (err) {
      console.error('No se pudo ordenar la hoja de guías:', err.message);
    }
  }

  const guias = [];
  orden.filas.forEach((fila, i) => {
    const guia = rowToGuia(fila, i + 2);
    if (guia.numero_guia !== '') guias.push(guia);
  });
  return guias;
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

/** Una celda para appendCells, con el mismo tipo que escribiría 'RAW'. */
function celdaNueva(valor) {
  if (typeof valor === 'number' && Number.isFinite(valor)) {
    return { userEnteredValue: { numberValue: valor } };
  }
  if (typeof valor === 'boolean') return { userEnteredValue: { boolValue: valor } };
  return { userEnteredValue: { stringValue: String(valor ?? '') } };
}

// El id (gid) de la pestaña de guías, que no cambia.
let idPestanaGuias = null;

/**
 * Agrega guías nuevas en las filas siguientes a la última con datos de la
 * hoja, siempre desde la columna A, con una sola escritura. Usa
 * appendCells: Google lo hace de una vez en su lado, así que las guías que
 * registran varios transportistas al mismo tiempo (desde distintas
 * instancias del servidor) quedan cada una en su fila. (No se calcula la
 * fila libre aquí: dos instancias calculaban la misma y una guía pisaba a
 * la otra. Tampoco se usa values.append: adivina dónde está la tabla y,
 * con datos sueltos a la derecha, pegaba la fila corrida.)
 */
async function crearGuias(guias) {
  if (guias.length === 0) return;
  const sheets = await getSheetsClient();
  const spreadsheetId = requireSheetId();
  if (idPestanaGuias === null) {
    idPestanaGuias = await idDePestana(sheets, spreadsheetId, SHEET_NAME);
  }
  await sheets.spreadsheets.batchUpdate({
    spreadsheetId,
    requestBody: {
      requests: [
        {
          appendCells: {
            sheetId: idPestanaGuias,
            rows: guias.map((guia) => ({ values: guiaToRow(guia).map(celdaNueva) })),
            fields: 'userEnteredValue',
          },
        },
      ],
    },
  }).finally(invalidarCacheGuias);
}

function crearGuia(guia) {
  return crearGuias([guia]);
}

/**
 * Sobrescribe varias guías existentes con una sola escritura (cada una
 * en su fila, como actualizarGuia).
 */
async function actualizarGuias(guias) {
  if (guias.length === 0) return;
  const sheets = await getSheetsClient();
  const spreadsheetId = requireSheetId();
  const data = guias.map((guia) => {
    const fila = guiaToRow(guia);
    return {
      range: `${SHEET_NAME}!A${guia._row}:${letraColumna(fila.length)}${guia._row}`,
      values: [fila],
    };
  });
  await sheets.spreadsheets.values.batchUpdate({
    spreadsheetId,
    requestBody: { valueInputOption: 'RAW', data },
  }).finally(invalidarCacheGuias);
}

/**
 * Sobrescribe la fila de una guía existente: A..X con sus datos, las
 * columnas siguientes con lo que ya tenían.
 */
async function actualizarGuia(rowNumber, guia) {
  const sheets = await getSheetsClient();
  const spreadsheetId = requireSheetId();
  const fila = guiaToRow(guia);
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
  const actual = await sheets.spreadsheets.values.get({
    spreadsheetId,
    range: `${SHEET_NAME}!A${rowNumber}:${ULTIMA_COLUMNA}${rowNumber}`,
  });
  const fila = rowToGuia(((actual.data.values || [])[0]) || [], rowNumber);
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
  crearGuias,
  actualizarGuia,
  actualizarGuias,
  eliminarGuia,
  listarUsuarios,
  crearUsuario,
  // Exportadas además para poder testear el parseo sin credenciales reales.
  rowToUsuario,
  rowToGuia,
  guiaToRow,
  ordenarHoja,
  letraColumna,
};
