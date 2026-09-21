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
