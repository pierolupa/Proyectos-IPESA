const app = require('../src/app');

// Entrypoint de Vercel: todo lo que llega a /api/* se enruta aquí (ver
// vercel.json). Vercel entrega el path completo en req.url, pero las
// rutas de Express están definidas sin el prefijo /api (p. ej. "/guias"),
// así que lo quitamos antes de delegar.
module.exports = (req, res) => {
  req.url = req.url.replace(/^\/api/, '') || '/';
  return app(req, res);
};
