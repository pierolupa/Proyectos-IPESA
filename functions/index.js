const { onRequest } = require('firebase-functions/v2/https');
const app = require('./src/app');

/**
 * API HTTP de "IPESA · Control de Guías". Ver README.md de esta carpeta
 * para las variables de entorno requeridas (SHEET_ID) y cómo desplegar.
 */
exports.api = onRequest({ region: 'us-central1', cors: true }, app);
