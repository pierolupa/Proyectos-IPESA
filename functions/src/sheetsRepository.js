const { google } = require('googleapis');
const { GoogleAuth } = require('google-auth-library');
const { COLUMNS, DATA_RANGE, SHEET_NAME } = require('./columns');

const SCOPES = ['https://www.googleapis.com/auth/spreadsheets'];

let sheetsClientPromise = null;

/**
 * Cliente autenticado de la API de Sheets. En Cloud Functions usa las
 * credenciales por defecto de la identidad de servicio de la función
 * (Application Default Credentials) — no se maneja ninguna clave JSON.
 */
function getSheetsClient() {
  if (!sheetsClientPromise) {
    const auth = new GoogleAuth({ scopes: SCOPES });
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

function rowToGuia(row, rowNumber) {
  const guia = {};
  COLUMNS.forEach((col, i) => {
    guia[col] = row[i] ?? '';
  });
  guia.corregido_por_admin = guia.corregido_por_admin === 'true' || guia.corregido_por_admin === true;
  guia._row = rowNumber; // fila real en la hoja (1-indexed), uso interno
  return guia;
}

function guiaToRow(guia) {
  return COLUMNS.map((col) => {
    const value = guia[col];
    return value === undefined || value === null ? '' : value;
  });
}

/** Lee todas las guías de la hoja. */
async function listarGuias() {
  const sheets = await getSheetsClient();
  const spreadsheetId = requireSheetId();
  const res = await sheets.spreadsheets.values.get({
    spreadsheetId,
    range: DATA_RANGE,
  });
  const rows = res.data.values || [];
  // La fila de datos N (0-indexed) corresponde a la fila real N+2 (por el encabezado).
  return rows.map((row, i) => rowToGuia(row, i + 2));
}

async function buscarPorNumero(numeroGuia) {
  const guias = await listarGuias();
  return guias.find((g) => g.numero_guia === numeroGuia) || null;
}

/** Agrega una nueva fila (nueva guía). */
async function crearGuia(guia) {
  const sheets = await getSheetsClient();
  const spreadsheetId = requireSheetId();
  await sheets.spreadsheets.values.append({
    spreadsheetId,
    range: DATA_RANGE,
    valueInputOption: 'RAW',
    insertDataOption: 'INSERT_ROWS',
    requestBody: { values: [guiaToRow(guia)] },
  });
}

/** Sobrescribe la fila completa de una guía existente. */
async function actualizarGuia(rowNumber, guia) {
  const sheets = await getSheetsClient();
  const spreadsheetId = requireSheetId();
  await sheets.spreadsheets.values.update({
    spreadsheetId,
    range: `${SHEET_NAME}!A${rowNumber}:${String.fromCharCode(64 + COLUMNS.length)}${rowNumber}`,
    valueInputOption: 'RAW',
    requestBody: { values: [guiaToRow(guia)] },
  });
}

module.exports = {
  listarGuias,
  buscarPorNumero,
  crearGuia,
  actualizarGuia,
};
