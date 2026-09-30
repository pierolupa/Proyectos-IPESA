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

  it('agrega al final las columnas que faltan, nunca en medio', async () => {
    const sinTransbordo = COLUMNS.filter((c) => !c.startsWith('transbordo_'));
    mockValores.get.mockReset().mockResolvedValue({
      data: { values: [[...sinTransbordo, 'Mi nota'], ['T1', 'en_ruta']] },
    });
    await repo.listarGuias({ fresco: true });
    const pedido = mockValores.update.mock.calls[0][0];
    // Después de "Mi nota" (columna V): W, X e Y.
    expect(pedido.range).toBe('Guias!W1:Y1');
    expect(pedido.requestBody.values).toEqual([
      ['transbordo_estado', 'transbordo_a', 'transbordo_de'],
    ]);
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
