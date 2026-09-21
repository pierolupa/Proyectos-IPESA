// Envoltorio sobre Tesseract.js (cargado como <script> en index.html) para
// que la app Flutter Web solo tenga que llamar a una función async con los
// bytes de la foto y reciba el texto reconocido. Ver
// lib/services/ocr_service.dart, que hace la extracción del número de guía
// a partir de este texto.
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

  const blob = new Blob([bytes], { type: "image/jpeg" });
  // API de Tesseract.js v4: createWorker + worker.recognize (el atajo
  // "Tesseract.recognize(...)" de versiones anteriores ya no existe).
  const worker = await Tesseract.createWorker("spa");
  try {
    const { data } = await worker.recognize(blob);
    return data.text || "";
  } finally {
    await worker.terminate();
  }
};
