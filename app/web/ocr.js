// Envoltorio sobre Tesseract.js (cargado como <script> en index.html) para
// que la app Flutter Web solo tenga que llamar a una función async con los
// bytes de la foto y reciba el texto reconocido. Ver
// lib/services/ocr_service.dart, que hace la extracción del número de guía
// a partir de este texto.

// Umbral óptimo de Otsu: separa la imagen en dos grupos (texto oscuro /
// fondo claro) probando cada nivel de gris posible y quedándose con el que
// maximiza la diferencia entre ambos grupos. Es el método estándar para
// binarizar documentos escaneados/fotografiados antes de un OCR.
function umbralOtsu(histograma, totalPixeles) {
  let sumaTotal = 0;
  for (let i = 0; i < 256; i++) sumaTotal += i * histograma[i];

  let sumaB = 0;
  let pesoB = 0;
  let mejorVarianza = -1;
  // Cuando el histograma tiene un hueco entre el grupo oscuro (texto) y el
  // claro (fondo) — lo normal en un documento escaneado —, la varianza
  // máxima se mantiene constante en todo ese hueco ("meseta"). Hay que
  // quedarse con el punto medio de esa meseta, no con su primer valor,
  // porque el primero cae pegado al borde del grupo oscuro.
  let inicioMeseta = 0;
  let finMeseta = 0;

  for (let t = 0; t < 256; t++) {
    pesoB += histograma[t];
    if (pesoB === 0) continue;
    const pesoF = totalPixeles - pesoB;
    if (pesoF === 0) break;

    sumaB += t * histograma[t];
    const mediaB = sumaB / pesoB;
    const mediaF = (sumaTotal - sumaB) / pesoF;
    const varianzaEntre = pesoB * pesoF * (mediaB - mediaF) * (mediaB - mediaF);

    if (varianzaEntre > mejorVarianza) {
      mejorVarianza = varianzaEntre;
      inicioMeseta = t;
      finMeseta = t;
    } else if (varianzaEntre === mejorVarianza) {
      finMeseta = t;
    }
  }
  return Math.round((inicioMeseta + finMeseta) / 2);
}

// Convierte la foto a blanco/negro puro (binarización de Otsu) antes de
// pasarla al OCR. Las guías tienen letra chica sobre fondo con líneas/
// bordes de tabla; esto separa el texto real del ruido de fondo mucho
// mejor que solo escala de grises. Si algo falla acá (navegador sin
// soporte, etc.), se sigue con la foto original.
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
  const totalPixeles = data.length / 4;
  const grises = new Uint8ClampedArray(totalPixeles);
  const histograma = new Array(256).fill(0);
  for (let i = 0; i < data.length; i += 4) {
    const gris = Math.round(
      0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2],
    );
    grises[i / 4] = gris;
    histograma[gris]++;
  }

  const umbral = umbralOtsu(histograma, totalPixeles);
  for (let i = 0; i < data.length; i += 4) {
    const valor = grises[i / 4] > umbral ? 255 : 0;
    data[i] = data[i + 1] = data[i + 2] = valor;
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
