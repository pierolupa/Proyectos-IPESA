/**
 * IPESA · Tracking Distribución — fotos de entregas en Google Drive.
 *
 * Este script vive en la cuenta de Google de IPESA y guarda las fotos de
 * las entregas en la carpeta "IPESA · Fotos de entregas" de su Drive (se
 * crea sola). El backend (backend/src/fotos.js) lo llama con una clave;
 * las fotos NO quedan públicas: solo se ven a través de la app.
 *
 * Cómo instalarlo (una sola vez; pasos completos en backend/README.md):
 *  1. script.google.com → Nuevo proyecto → pega este archivo completo.
 *  2. Cambia CLAVE por una clave larga que inventes (la misma irá en
 *     Vercel como DRIVE_FOTOS_CLAVE). No la compartas.
 *  3. Ejecuta la función `autorizar` una vez y acepta los permisos.
 *  4. Implementar → Nueva implementación → Aplicación web:
 *     Ejecutar como "Yo", Quién tiene acceso "Cualquier persona".
 *     Copia la URL (termina en /exec) → Vercel: DRIVE_FOTOS_URL.
 */

const CLAVE = 'ESCRIBE_AQUI_TU_CLAVE';
const NOMBRE_CARPETA = 'IPESA · Fotos de entregas';

function doPost(e) {
  try {
    const datos = JSON.parse(e.postData.contents);
    if (CLAVE === 'ESCRIBE_AQUI_TU_CLAVE' || datos.clave !== CLAVE) {
      return responder({ error: 'Clave incorrecta.' });
    }
    if (datos.accion === 'guardar') return responder({ id: guardar(datos) });
    if (datos.accion === 'leer') return responder(leer(datos.id));
    return responder({ error: 'Acción desconocida.' });
  } catch (err) {
    return responder({ error: String((err && err.message) || err) });
  }
}

/** Ejecútala una vez desde el editor para dar los permisos de Drive. */
function autorizar() {
  Logger.log('Carpeta lista: ' + carpeta().getUrl());
}

function carpeta() {
  const encontradas = DriveApp.getFoldersByName(NOMBRE_CARPETA);
  return encontradas.hasNext()
    ? encontradas.next()
    : DriveApp.createFolder(NOMBRE_CARPETA);
}

function guardar(datos) {
  const bytes = Utilities.base64Decode(datos.base64);
  const archivo = Utilities.newBlob(
    bytes,
    datos.tipo || 'image/jpeg',
    datos.nombre || 'foto.jpg',
  );
  return carpeta().createFile(archivo).getId();
}

function leer(id) {
  const archivo = DriveApp.getFileById(id);
  // Solo fotos de la carpeta de entregas: la clave no abre cualquier
  // archivo del Drive.
  const idCarpeta = carpeta().getId();
  const padres = archivo.getParents();
  let enCarpeta = false;
  while (padres.hasNext()) {
    if (padres.next().getId() === idCarpeta) enCarpeta = true;
  }
  if (!enCarpeta) return { error: 'No es una foto de entregas.' };
  const contenido = archivo.getBlob();
  return {
    tipo: contenido.getContentType(),
    base64: Utilities.base64Encode(contenido.getBytes()),
  };
}

function responder(objeto) {
  return ContentService.createTextOutput(JSON.stringify(objeto)).setMimeType(
    ContentService.MimeType.JSON,
  );
}
