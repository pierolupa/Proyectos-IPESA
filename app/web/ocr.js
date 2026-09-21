// Envoltorio sobre Tesseract.js (cargado como <script> en index.html) para
// que la app Flutter Web solo tenga que llamar a una función async con los
// bytes de la foto y reciba el texto reconocido. Ver
// lib/services/ocr_service.dart, que hace la extracción del número de guía
// a partir de este texto.

// Convierte la foto a escala de grises y estira el contraste (el píxel más
// oscuro pasa a negro puro, el más claro a blanco puro) antes de pasarla al
// OCR. Las guías tienen letra chica sobre fondo con líneas/bordes de tabla;
// esto ayuda a separar el texto real del ruido de fondo. Si algo falla acá
// (navegador sin soporte, etc.), se sigue con la foto original.
async function preprocesarParaOcr(bytes) {
  const blobOriginal = new Blob([bytes], { type: "image/jpeg" });
  const bitmap = await createImageBitmap(blobOriginal);
  const canvas = document.createElement("canvas");
  canvas.width = bitmap.width;
  canvas.height = bitmap.height;
  const ctx = canvas.getContext("2d");
  ctx.drawImage(bitmap, 0, 0);

  const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const data = imageData.data;
  const grises = new Float32Array(data.length / 4);
  let min = 255;
  let max = 0;
  for (let i = 0; i < data.length; i += 4) {
    const gris = 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];
    grises[i / 4] = gris;
    if (gris < min) min = gris;
    if (gris > max) max = gris;
  }
  const rango = Math.max(1, max - min);
  for (let i = 0; i < data.length; i += 4) {
    const estirado = Math.round(((grises[i / 4] - min) / rango) * 255);
    data[i] = data[i + 1] = data[i + 2] = estirado;
  }
  ctx.putImageData(imageData, 0, 0);

  return await new Promise((resolve, reject) =>
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(new Error("toBlob falló"))),
      "image/png",
    ),
  );
}

window.ipesaReconocerGuia = async function (bytes) {
  // Tesseract.js se carga con <script defer>, así que normalmente ya está
  // listo; este loop es solo un colchón por si la red del dispositivo es
  // lenta (hasta 10s).
  for (let i = 0; i < 100 && typeof Tesseract === "undefined"; i++) {
    await new Promise((resolver) => setTimeout(resolver, 100));
  }
  if (typeof Tesseract === "undefined") {
    throw new Error("No se pudo cargar el lector de texto (revisa tu conexión).");
  }

  let blob;
  try {
    blob = await preprocesarParaOcr(bytes);
  } catch (error) {
    console.warn("[ocr] no se pudo preprocesar la imagen, uso la original", error);
    blob = new Blob([bytes], { type: "image/jpeg" });
  }

  // "spa": el documento tiene etiquetas en español con tildes/eñes
  // ("Señor(es)", "Número") — el modelo en inglés las leía mal y esos
  // campos no se detectaban nunca.
  let worker;
  try {
    worker = await Tesseract.createWorker("spa");
  } catch (error) {
    console.error("[ocr] no se pudo inicializar Tesseract.js", error);
    throw new Error("No se pudo iniciar el lector de texto.");
  }

  try {
    // La guía es un formulario con tablas, no un documento de texto
    // corrido: el modo automático (por defecto) confunde el layout y
    // pierde secciones enteras. "Sparse text" busca bloques de texto sin
    // asumir una estructura de página única, que rinde mejor en este caso.
    try {
      await worker.setParameters({ tessedit_pageseg_mode: "11" });
    } catch (error) {
      console.warn("[ocr] no se pudo ajustar el modo de segmentación", error);
    }

    const { data } = await worker.recognize(blob);
    return data.text || "";
  } catch (error) {
    console.error("[ocr] Tesseract.js falló al leer la foto", error);
    throw new Error("El lector de texto no pudo procesar la foto.");
  } finally {
    try {
      await worker.terminate();
    } catch (_) {
      // Si el worker ya quedó en mal estado, no hay nada más que hacer.
    }
  }
};
