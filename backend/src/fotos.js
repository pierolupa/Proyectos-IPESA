const { Readable } = require('node:stream');
const { put, get } = require('@vercel/blob');

/**
 * Fotos de las guías (la de la asignación y la de la entrega) en Vercel
 * Blob, en modo PRIVADO: las URLs no se pueden abrir directamente, solo a
 * través de GET /guias/:numeroGuia/foto/:tipo de este backend. Así la foto
 * de una guía firmada no queda expuesta en una URL pública.
 *
 * El token lo pone Vercel solo al conectar el Blob store al proyecto
 * (BLOB_READ_WRITE_TOKEN; ver README.md). Sin él las fotos no se guardan,
 * pero la guía se registra igual: una entrega nunca debe bloquearse por
 * el almacenamiento de la foto.
 */

const TIPOS_FOTO = Object.freeze({ GUIA: 'guia', ENTREGA: 'entrega' });
const COLUMNA_POR_TIPO = Object.freeze({
  [TIPOS_FOTO.GUIA]: 'foto_guia_url',
  [TIPOS_FOTO.ENTREGA]: 'foto_entrega_url',
});

const MEDIA_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);

function almacenamientoConfigurado() {
  return Boolean(process.env.BLOB_READ_WRITE_TOKEN || process.env.BLOB_STORE_ID);
}

function nombreSeguro(texto) {
  return String(texto).replace(/[^A-Za-z0-9_-]/g, '_').slice(0, 60) || 'guia';
}

/**
 * Sube la foto y devuelve su URL (privada). Lanza un Error con un mensaje
 * legible si no se pudo — quien llama decide si eso bloquea o no.
 */
async function guardarFoto(numeroGuia, tipo, foto) {
  if (!almacenamientoConfigurado()) {
    throw new Error('El almacenamiento de fotos no está configurado en Vercel.');
  }
  const mediaType = MEDIA_TYPES.has(foto.mediaType) ? foto.mediaType : 'image/jpeg';
  const extension = mediaType.split('/')[1].replace('jpeg', 'jpg');
  const datos = Buffer.from(String(foto.base64), 'base64');
  if (datos.length === 0) throw new Error('La foto llegó vacía.');

  const blob = await put(
    `guias/${nombreSeguro(numeroGuia)}/${tipo}.${extension}`,
    datos,
    { access: 'private', contentType: mediaType, addRandomSuffix: true },
  );
  return blob.url;
}

/** Envía la foto guardada en `url` como respuesta HTTP. */
async function enviarFoto(url, res) {
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
  TIPOS_FOTO,
  COLUMNA_POR_TIPO,
  almacenamientoConfigurado,
  guardarFoto,
  enviarFoto,
  esFotoValida,
};
