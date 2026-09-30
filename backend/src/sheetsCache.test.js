// Caché de la hoja de guías (sheetsRepository.listarGuias): la API de
// Google se simula; lo que importa es cuántas veces se la llama.
const mockValores = {
  get: jest.fn(),
  append: jest.fn(),
  update: jest.fn(),
};

jest.mock('googleapis', () => ({
  google: { sheets: () => ({ spreadsheets: { values: mockValores } }) },
}));
jest.mock('google-auth-library', () => ({
  GoogleAuth: jest.fn().mockImplementation(() => ({ getClient: async () => ({}) })),
}));

const { COLUMNS } = require('./columns');

const fila = (numero, creada) => [
  numero, 'en_ruta', 'cliente_final', 'Almacén', 'Destino', 'Juan', 'Cliente',
  '', '', 'FALSE', creada, creada,
];

describe('caché de guías', () => {
  let repo;

  beforeEach(() => {
    jest.resetModules();
    jest.useRealTimers();
    process.env.SHEET_ID = 'hoja-de-prueba';
    mockValores.get.mockReset().mockResolvedValue({
      data: {
        values: [
          COLUMNS,
          fila('T1', '2026-09-28T10:00:00.000Z'),
          fila('T1', '2026-09-28T14:00:00.000Z'),
          fila('T2', '2026-09-28T11:00:00.000Z'),
        ],
      },
    });
    mockValores.append.mockReset().mockResolvedValue({});
    mockValores.update.mockReset().mockResolvedValue({});
    repo = require('./sheetsRepository');
  });

  it('varios pedidos seguidos comparten una sola lectura de la hoja', async () => {
    await Promise.all([repo.listarGuias(), repo.listarGuias(), repo.listarGuias()]);
    await repo.listarGuias();
    expect(mockValores.get).toHaveBeenCalledTimes(1);
  });

  it('vuelve a leer la hoja pasados 10 segundos', async () => {
    jest.useFakeTimers({ now: new Date('2026-09-28T15:00:00Z') });
    await repo.listarGuias();
    jest.setSystemTime(new Date('2026-09-28T15:00:11Z'));
    await repo.listarGuias();
    expect(mockValores.get).toHaveBeenCalledTimes(2);
  });

  it('una escritura borra la caché', async () => {
    await repo.listarGuias();
    await repo.actualizarGuia(2, { numero_guia: 'T1' });
    await repo.listarGuias();
    expect(mockValores.get).toHaveBeenCalledTimes(2);
  });

  it('fresco siempre lee la hoja', async () => {
    await repo.listarGuias();
    await repo.listarGuias({ fresco: true });
    expect(mockValores.get).toHaveBeenCalledTimes(2);
  });

  it('devuelve copias: modificar una guía no cambia la caché', async () => {
    const [primera] = await repo.listarGuias();
    primera.estado = 'entregado';
    const [otraVez] = await repo.listarGuias();
    expect(otraVez.estado).toBe('en_ruta');
  });

  it('buscarPorNumero devuelve el registro más reciente de ese número', async () => {
    const guia = await repo.buscarPorNumero('T1');
    expect(guia.fecha_creacion).toBe('2026-09-28T14:00:00.000Z');
    expect(guia._row).toBe(3);
  });
});

describe('encabezados de la hoja de guías', () => {
  const { COLUMNS } = require('./columns');
  let repo;

  beforeEach(() => {
    jest.resetModules();
    process.env.SHEET_ID = 'hoja-de-prueba';
    mockValores.update.mockReset().mockResolvedValue({});
    repo = require('./sheetsRepository');
  });

  it('escribe en su lugar los encabezados que faltan (columnas vacías)', async () => {
    const sinTransbordo = COLUMNS.filter((c) => !c.startsWith('transbordo_'));
    mockValores.get.mockReset().mockResolvedValue({
      data: { values: [sinTransbordo, ['T1', 'en_ruta']] },
    });
    await repo.listarGuias({ fresco: true });
    const rangos = mockValores.update.mock.calls.map((c) => c[0].range);
    expect(rangos).toEqual(['Guias!V1', 'Guias!W1', 'Guias!X1']);
  });

  it('si otra columna del sistema ocupa su lugar, la agrega al final', async () => {
    const encabezados = COLUMNS.slice(0, 21);
    encabezados[18] = 'mi nota'; // donde iba motivo_rechazo
    encabezados.push('motivo_rechazo'); // movida a la V
    mockValores.get.mockReset().mockResolvedValue({
      data: { values: [encabezados, ['T1', 'en_ruta']] },
    });
    await repo.listarGuias({ fresco: true });
    const pedidos = mockValores.update.mock.calls.map((c) => [
      c[0].range,
      c[0].requestBody.values,
    ]);
    expect(pedidos).toEqual([
      ['Guias!W1', [['transbordo_a']]],
      ['Guias!X1', [['transbordo_de']]],
      ['Guias!Y1:Y1', [['transbordo_estado']]],
    ]);
  });

  it('una lista de encabezados escritos distinto se sigue leyendo por posición', async () => {
    const distintos = COLUMNS.map((c) => `Col ${c}`);
    mockValores.get.mockReset().mockResolvedValue({
      data: { values: [distintos, ['T1', 'entregado']] },
    });
    const [guia] = await repo.listarGuias({ fresco: true });
    expect(guia.numero_guia).toBe('T1');
    expect(guia.estado).toBe('entregado');
    expect(mockValores.update).not.toHaveBeenCalled();
  });

  it('devuelve a la columna A una guía que quedó corrida a la derecha', async () => {
    const corrida = [...Array(21).fill(''), 'T035-7954', 'en_ruta', 'cliente_final', 'Trp Callao'];
    mockValores.get.mockReset().mockResolvedValue({
      data: { values: [COLUMNS, ['T1', 'en_ruta'], corrida] },
    });
    const guias = await repo.listarGuias({ fresco: true });
    expect(guias.map((g) => g.numero_guia)).toEqual(['T1', 'T035-7954']);
    const arreglo = mockValores.update.mock.calls.find((c) => c[0].range.startsWith('Guias!A3:'));
    const fila = arreglo[0].requestBody.values[0];
    expect(fila.slice(0, 4)).toEqual(['T035-7954', 'en_ruta', 'cliente_final', 'Trp Callao']);
    expect(fila.slice(21).every((v) => v === '')).toBe(true);
  });

  it('una guía nueva va en la fila siguiente a la última, desde la columna A', async () => {
    mockValores.get.mockReset().mockResolvedValue({
      data: { values: [COLUMNS, ['T1', 'en_ruta'], ['', '', '', 'algo suelto']] },
    });
    await repo.crearGuia({ numero_guia: 'T9', estado: 'en_ruta' });
    const escritura = mockValores.update.mock.calls.at(-1)[0];
    expect(escritura.range).toMatch(/^Guias!A4:/);
    expect(escritura.requestBody.values[0].slice(0, 2)).toEqual(['T9', 'en_ruta']);
  });

  it('salta las filas sin número de guía', async () => {
    mockValores.get.mockReset().mockResolvedValue({
      data: { values: [COLUMNS, ['T1', 'en_ruta'], [], ['', '', '', 'algo suelto']] },
    });
    const guias = await repo.listarGuias({ fresco: true });
    expect(guias.map((g) => g.numero_guia)).toEqual(['T1']);
    expect(mockValores.update).not.toHaveBeenCalled();
  });
});
