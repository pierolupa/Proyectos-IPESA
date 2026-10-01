// Caché de la hoja de guías (sheetsRepository.listarGuias): la API de
// Google se simula; lo que importa es cuántas veces se la llama.
const mockValores = {
  get: jest.fn(),
  append: jest.fn(),
  update: jest.fn(),
  batchUpdate: jest.fn(),
};

const mockHojas = { get: jest.fn(), batchUpdate: jest.fn() };

jest.mock('googleapis', () => ({
  google: {
    sheets: () => ({ spreadsheets: { values: mockValores, ...mockHojas } }),
  },
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
    mockValores.batchUpdate.mockReset().mockResolvedValue({});
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

describe('orden de la hoja de guías', () => {
  const { COLUMNS } = require('./columns');
  let repo;

  // Lo que se escribió en la hoja en la única escritura de orden.
  const escrito = () => {
    const llamadas = mockValores.batchUpdate.mock.calls;
    expect(llamadas).toHaveLength(1);
    return llamadas[0][0].requestBody.data;
  };

  beforeEach(() => {
    jest.resetModules();
    process.env.SHEET_ID = 'hoja-de-prueba';
    mockValores.update.mockReset().mockResolvedValue({});
    mockValores.batchUpdate.mockReset().mockResolvedValue({});
    repo = require('./sheetsRepository');
  });

  it('escribe solo los encabezados de T a X, después de la S', async () => {
    const propios = [...COLUMNS.slice(0, 12), 'Nro Pedido', 'Nro Entrega',
      'Latitud entrega', 'Longitud entrega', 'fecha_entrega', 'Foto', 'Observacion'];
    mockValores.get.mockReset().mockResolvedValue({
      data: { values: [propios, ['T1', 'en_ruta']] },
    });
    await repo.listarGuias({ fresco: true });
    expect(escrito()).toEqual([
      { range: 'Guias!T1:X1', values: [COLUMNS.slice(19)] },
    ]);
  });

  it('reemplaza encabezados de columnas retiradas', async () => {
    const encabezados = [...COLUMNS.slice(0, 21), 'salida_lat', 'salida_lng', 'transbordo_de'];
    mockValores.get.mockReset().mockResolvedValue({
      data: { values: [encabezados, ['T1', 'en_ruta']] },
    });
    await repo.listarGuias({ fresco: true });
    expect(escrito()).toEqual([
      { range: 'Guias!V1:W1', values: [['transbordo_estado', 'transbordo_a']] },
    ]);
  });

  it('una hoja en orden no se escribe', async () => {
    mockValores.get.mockReset().mockResolvedValue({
      data: { values: [COLUMNS, ['T1', 'entregado']] },
    });
    const [guia] = await repo.listarGuias({ fresco: true });
    expect(guia.estado).toBe('entregado');
    expect(mockValores.batchUpdate).not.toHaveBeenCalled();
  });

  it('devuelve cada dato a su columna y vacía las que se agregaron de más', async () => {
    const movidos = [...COLUMNS.slice(0, 19), ...COLUMNS.slice(12)];
    const fila = ['T2', 'entregado', ...Array(17).fill(''),
      'P-2', 'E-2', '-9.5', '-77.5', '2026-09-29T10:00:00.000Z', 'drive:foto'];
    mockValores.get.mockReset().mockResolvedValue({
      data: { values: [movidos, fila] },
    });
    const [guia] = await repo.listarGuias({ fresco: true });
    expect(guia.foto_entrega_url).toBe('drive:foto');
    expect(guia.numero_pedido).toBe('P-2');
    const [datos, encabezados] = escrito();
    expect(datos.range).toBe('Guias!A2:Y2');
    expect(datos.values[0][17]).toBe('drive:foto'); // R
    expect(datos.values[0].slice(19)).toEqual(Array(6).fill(''));
    expect(encabezados).toEqual({
      range: 'Guias!T1:AE1',
      values: [[...COLUMNS.slice(19), ...Array(7).fill('')]],
    });
  });

  it('devuelve a la columna A una guía que quedó corrida a la derecha', async () => {
    const corrida = [...Array(21).fill(''), 'T035-7954', 'en_ruta', 'cliente_final', 'Trp Callao'];
    mockValores.get.mockReset().mockResolvedValue({
      data: { values: [COLUMNS, ['T1', 'en_ruta'], corrida] },
    });
    const guias = await repo.listarGuias({ fresco: true });
    expect(guias.map((g) => g.numero_guia)).toEqual(['T1', 'T035-7954']);
    const [arreglo] = escrito();
    expect(arreglo.range).toBe('Guias!A3:Y3');
    const fila = arreglo.values[0];
    expect(fila.slice(0, 4)).toEqual(['T035-7954', 'en_ruta', 'cliente_final', 'Trp Callao']);
    expect(fila.slice(4).every((v) => v === '')).toBe(true);
  });

  it('una guía nueva se agrega después de la última fila, desde la columna A', async () => {
    mockHojas.get.mockReset().mockResolvedValue({
      data: { sheets: [{ properties: { sheetId: 77, title: 'Guias' } }] },
    });
    mockHojas.batchUpdate.mockReset().mockResolvedValue({});
    await repo.crearGuia({
      numero_guia: 'T9', estado: 'en_ruta', geo_lat: -12.1, corregido_por_admin: false,
    });
    const pedido = mockHojas.batchUpdate.mock.calls[0][0].requestBody.requests[0];
    expect(pedido.appendCells.sheetId).toBe(77);
    expect(pedido.appendCells.fields).toBe('userEnteredValue');
    const [fila] = pedido.appendCells.rows;
    expect(fila.values).toHaveLength(COLUMNS.length);
    expect(fila.values[0]).toEqual({ userEnteredValue: { stringValue: 'T9' } });
    expect(fila.values[7]).toEqual({ userEnteredValue: { numberValue: -12.1 } });
    expect(fila.values[9]).toEqual({ userEnteredValue: { boolValue: false } });
    // No calcula la fila: no escribe con values.update.
    expect(mockValores.update).not.toHaveBeenCalled();
  });

  it('varias guías al mismo tiempo: cada una se agrega por separado', async () => {
    mockHojas.get.mockReset().mockResolvedValue({
      data: { sheets: [{ properties: { sheetId: 77, title: 'Guias' } }] },
    });
    mockHojas.batchUpdate.mockReset().mockResolvedValue({});
    await Promise.all(
      ['T1', 'T2', 'T3', 'T4', 'T5'].map((n) => repo.crearGuia({ numero_guia: n })),
    );
    const numeros = mockHojas.batchUpdate.mock.calls.map(
      (c) => c[0].requestBody.requests[0].appendCells.rows[0].values[0].userEnteredValue.stringValue,
    );
    expect(numeros.sort()).toEqual(['T1', 'T2', 'T3', 'T4', 'T5']);
  });

  it('salta las filas sin número de guía', async () => {
    mockValores.get.mockReset().mockResolvedValue({
      data: { values: [COLUMNS, ['T1', 'en_ruta'], [], ['', '', '', 'algo suelto']] },
    });
    const guias = await repo.listarGuias({ fresco: true });
    expect(guias.map((g) => g.numero_guia)).toEqual(['T1']);
    expect(mockValores.batchUpdate).not.toHaveBeenCalled();
  });
});
