/*
 * Archiva las guías cerradas anteriores a una fecha en pestañas por año
 * ("Guías 2026"). Sin --ejecutar solo muestra cuántas movería.
 *
 *   node --env-file=.env scripts/archivar.js 2027-01-01
 *   node --env-file=.env scripts/archivar.js 2027-01-01 --ejecutar
 *
 * Después, agrega las pestañas en PESTANAS_ARCHIVO (Vercel) para que las
 * consultas con fechas antiguas las incluyan.
 */
const { archivarGuias } = require('../src/sheetsRepository');

async function main() {
  const [hasta, bandera] = process.argv.slice(2);
  if (!hasta) {
    console.error('Uso: node scripts/archivar.js AAAA-MM-DD [--ejecutar]');
    process.exit(1);
  }
  const ejecutar = bandera === '--ejecutar';
  const res = await archivarGuias(hasta, { ejecutar });
  console.log(ejecutar ? 'Archivado:' : 'Simulación (nada se movió):');
  console.log(`  guías: ${res.total}`);
  for (const [pestana, n] of Object.entries(res.porPestana)) {
    console.log(`  ${pestana}: ${n}`);
  }
  if (!ejecutar) {
    console.log('Para moverlas de verdad, repite con --ejecutar.');
    return;
  }
  console.log('Después, en Vercel (Environment Variables):');
  console.log(`  ARCHIVO_HASTA=${hasta}`);
  console.log('  PESTANAS_ARCHIVO=' + Object.keys(res.porPestana).join(','));
  console.log('Hazlo recién después de archivar: si la pestaña no existe, las consultas antiguas fallan.');
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
