const {
  pestanaDeAnio,
  pestanasArchivo,
  hacenFaltaArchivo,
  seleccionarParaArchivar,
  agruparPorAnio,
  anioDePestana,
  anioEnRango,
  rangoDeFilas,
} = require('./archivo');

const g = (numero, estado, fecha, extra = {}) => ({
  numero_guia: numero,
  estado,
  fecha_creacion: fecha,
  fecha_actualizacion: fecha,
  eliminacion: '',
  transbordo_estado: '',
  ...extra,
});

describe('archivo por año', () => {
  afterEach(() => {
    delete process.env.PESTANAS_ARCHIVO;
  });

  it('nombra la pestaña de cada año', () => {
    expect(pestanaDeAnio(2026)).toBe('Guías 2026');
  });

  it('lee la lista de pestañas de PESTANAS_ARCHIVO; vacía sin configurar', () => {
    expect(pestanasArchivo()).toEqual([]);
    process.env.PESTANAS_ARCHIVO = ' Guías 2025 , Guías 2026,';
    expect(pestanasArchivo()).toEqual(['Guías 2025', 'Guías 2026']);
  });

  it('mira el archivo solo si la consulta empieza antes del corte', () => {
    process.env.ARCHIVO_HASTA = '2026-09-01';
    expect(hacenFaltaArchivo(Date.parse('2026-10-01T00:00:00Z'))).toBe(false);
    expect(hacenFaltaArchivo(Date.parse('2026-08-01T00:00:00Z'))).toBe(true);
    expect(hacenFaltaArchivo(NaN)).toBe(false);
    delete process.env.ARCHIVO_HASTA;
    // Sin corte configurado, se mira el archivo siempre que hay fecha de inicio.
    expect(hacenFaltaArchivo(Date.parse('2026-10-01T00:00:00Z'))).toBe(true);
  });

  it('archiva solo cerradas, anteriores al corte, sin nada pendiente', () => {
    const guias = [
      g('viejaEntregada', 'entregado', '2026-03-01T10:00:00.000Z'),
      g('viejaRechazada', 'rechazado', '2026-03-02T10:00:00.000Z'),
      g('viejaAgencia', 'finalizado', '2026-03-03T10:00:00.000Z'),
      g('viejaEnRuta', 'en_ruta', '2026-03-04T10:00:00.000Z'),
      g('viejaConEliminacion', 'entregado', '2026-03-05T10:00:00.000Z', { eliminacion: 'pendiente' }),
      g('viejaConTransbordo', 'entregado', '2026-03-06T10:00:00.000Z', { transbordo_estado: 'pendiente' }),
      g('reciente', 'entregado', '2026-10-01T10:00:00.000Z'),
    ];
    const sel = seleccionarParaArchivar(guias, '2026-09-01');
    expect(sel.map((x) => x.numero_guia)).toEqual([
      'viejaEntregada',
      'viejaRechazada',
      'viejaAgencia',
    ]);
  });

  it('rechaza una fecha de corte inválida', () => {
    expect(() => seleccionarParaArchivar([], 'ayer')).toThrow();
  });

  it('agrupa por año de registro', () => {
    const grupos = agruparPorAnio([
      g('a', 'entregado', '2025-12-31T23:00:00.000Z'),
      g('b', 'entregado', '2026-01-02T10:00:00.000Z'),
    ]);
    expect(Object.keys(grupos).sort()).toEqual(['2025', '2026']);
    expect(grupos['2026'].map((x) => x.numero_guia)).toEqual(['b']);
  });

  it('toma el año de una pestaña de archivo', () => {
    expect(anioDePestana('Guías 2026')).toBe(2026);
    expect(anioDePestana('Guias')).toBeNull();
  });

  it('solo considera los años que tocan el rango pedido', () => {
    const d = Date.parse('2026-03-01T00:00:00Z');
    const h = Date.parse('2026-03-15T00:00:00Z');
    expect(anioEnRango(2025, d, h)).toBe(false);
    expect(anioEnRango(2026, d, h)).toBe(true);
    expect(anioEnRango(2027, d, h)).toBe(false);
    expect(anioEnRango(2026, NaN, NaN)).toBe(true);
  });

  it('elige solo el tramo de filas que cae en el rango', () => {
    const fechas = [
      '2026-02-28T10:00:00.000Z',
      '2026-03-02T10:00:00.000Z',
      '2026-03-10T10:00:00.000Z',
      '2026-03-15T00:00:00.000Z', // justo en el hasta: no entra
      '2026-04-01T10:00:00.000Z',
    ];
    const r = rangoDeFilas(fechas, Date.parse('2026-03-01T00:00:00Z'), Date.parse('2026-03-15T00:00:00Z'));
    expect(r).toEqual({ primera: 1, ultima: 2 });
    expect(rangoDeFilas(fechas, Date.parse('2025-01-01T00:00:00Z'), Date.parse('2025-02-01T00:00:00Z'))).toBeNull();
    expect(rangoDeFilas(['', 'no es fecha'], NaN, NaN)).toBeNull();
  });
});
