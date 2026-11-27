/*
 * Archiva las guías cerradas anteriores a una fecha en pestañas por año
 * ("Guías 2026"). Sin --ejecutar solo muestra cuántas movería.
 *
 *   node --env-file=.env scripts/archivar.js 2027-01-01
 *   node --env-file=.env scripts/archivar.js 2027-01-01 --ejecutar
 *
 * Lo mismo se puede hacer desde la app (administrador › Archivo de guías).
 * Las pestañas creadas se reconocen solas: no hay nada que configurar.
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
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
