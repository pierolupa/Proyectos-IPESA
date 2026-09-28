const { Readable } = require('node:stream');
const { put, get } = require('@vercel/blob');

/**
 * Foto de la entrega al cliente (guía firmada), guardada en PRIVADO: no se
 * puede abrir directo, solo a través de GET /guias/:numeroGuia/foto de
 * este backend. Así la foto de una guía firmada no queda expuesta.
 *
 * Dos lugares posibles (ver README.md, "Fotos"):
 * - Google Drive, en una carpeta de la cuenta de IPESA, a través de un
 *   Apps Script propio (apps-script/fotos-drive.gs). Se usa si están
 *   DRIVE_FOTOS_URL y DRIVE_FOTOS_CLAVE. En la hoja queda `drive:<id>`.
 * - Vercel Blob (BLOB_READ_WRITE_TOKEN, que Vercel pone solo al conectar
 *   el Blob store). En la hoja queda la URL privada del blob.
 *
 * Sin ninguno las fotos no se guardan, pero la guía se registra igual:
 * una entrega nunca debe bloquearse por el almacenamiento de la foto.
 */

const PREFIJO_DRIVE = 'drive:';

function driveConfigurado() {
  return Boolean(process.env.DRIVE_FOTOS_URL && process.env.DRIVE_FOTOS_CLAVE);
}

function blobConfigurado() {
  return Boolean(process.env.BLOB_READ_WRITE_TOKEN || process.env.BLOB_STORE_ID);
}

/** Llama al Apps Script de Drive y devuelve su respuesta JSON. */
async function llamarDrive(datos) {
  let respuesta;
  try {
    respuesta = await fetch(process.env.DRIVE_FOTOS_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...datos, clave: process.env.DRIVE_FOTOS_CLAVE }),
      redirect: 'follow',
      signal: AbortSignal.timeout(25000),
    });
  } catch (err) {
    throw new Error(`No se pudo conectar con Google Drive (${err.message}).`);
  }
  let json;
  try {
    json = await respuesta.json();
  } catch {
    // Si el script no está publicado para "Cualquier persona", Google
    // responde con una página de inicio de sesión en vez de JSON.
    throw new Error(
      'Google Drive no respondió como se esperaba: revisa que el Apps Script '
      + 'esté implementado como aplicación web con acceso "Cualquier persona".',
    );
  }
  if (json.error) throw new Error(`Google Drive: ${json.error}`);
  return json;
}

const MEDIA_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);

function almacenamientoConfigurado() {
  return driveConfigurado() || blobConfigurado();
}

function nombreSeguro(texto) {
  return String(texto).replace(/[^A-Za-z0-9_-]/g, '_').slice(0, 60) || 'guia';
}

/**
 * Sube la foto y devuelve dónde quedó (`drive:<id>` o la URL privada del
 * blob). Lanza un Error con un mensaje legible si no se pudo — quien llama
 * decide si eso bloquea o no.
 */
async function guardarFoto(numeroGuia, foto) {
  if (!almacenamientoConfigurado()) {
    throw new Error('El almacenamiento de fotos no está configurado.');
  }
  const mediaType = MEDIA_TYPES.has(foto.mediaType) ? foto.mediaType : 'image/jpeg';
  const extension = mediaType.split('/')[1].replace('jpeg', 'jpg');
  const datos = Buffer.from(String(foto.base64), 'base64');
  if (datos.length === 0) throw new Error('La foto llegó vacía.');

  if (driveConfigurado()) {
    const fecha = new Date().toISOString().slice(0, 10);
    const { id } = await llamarDrive({
      accion: 'guardar',
      nombre: `${nombreSeguro(numeroGuia)}_${fecha}.${extension}`,
      tipo: mediaType,
      base64: datos.toString('base64'),
    });
    if (!id) throw new Error('Google Drive no devolvió el archivo guardado.');
    return `${PREFIJO_DRIVE}${id}`;
  }

  const blob = await put(
    `entregas/${nombreSeguro(numeroGuia)}.${extension}`,
    datos,
    { access: 'private', contentType: mediaType, addRandomSuffix: true },
  );
  return blob.url;
}

/** Envía la foto guardada en `url` como respuesta HTTP. */
async function enviarFoto(url, res) {
  if (url.startsWith(PREFIJO_DRIVE)) {
    const { base64, tipo } = await llamarDrive({
      accion: 'leer',
      id: url.slice(PREFIJO_DRIVE.length),
    });
    res.set('Content-Type', tipo || 'image/jpeg');
    res.set('Cache-Control', 'private, max-age=86400');
    return res.send(Buffer.from(base64, 'base64'));
  }
  const resultado = await get(url, { access: 'private' });
  if (!resultado || !resultado.stream) {
    return res.status(404).json({ error: 'La foto ya no existe.' });
  }
  res.set('Content-Type', resultado.blob.contentType || 'image/jpeg');
  res.set('Cache-Control', 'private, max-age=86400');
  Readable.fromWeb(resultado.stream).pipe(res);
}

/** true si el body trae una foto con forma válida ({base64, mediaType?}). */
function esFotoValida(foto) {
  return Boolean(foto && typeof foto.base64 === 'string' && foto.base64.length > 0);
}

module.exports = {
  almacenamientoConfigurado,
  guardarFoto,
  enviarFoto,
  esFotoValida,
};
