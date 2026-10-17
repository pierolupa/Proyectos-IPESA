// Archivo por año contra una hoja simulada: qué se copia, qué se borra y
// que repetirlo no duplique filas.
const mockValores = {
  get: jest.fn(),
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

const fila = (numero, estado, creada) => [
  numero, estado, 'cliente_final', 'Almacén', 'Destino', 'Juan', 'Cliente',
  '', '', 'FALSE', creada, creada,
];

describe('archivar guías en la hoja', () => {
  let repo;
  let activa;
  let archivo;

  beforeEach(() => {
    jest.resetModules();
    process.env.SHEET_ID = 'hoja-de-prueba';
    activa = [
      COLUMNS,
      fila('S1', 'entregado', '2026-09-28T10:00:00.000Z'), // fila 2
      fila('S2', 'en_ruta', '2026-09-28T11:00:00.000Z'), // fila 3: abierta, se queda
      fila('S3', 'finalizado', '2026-09-29T10:00:00.000Z'), // fila 4
      fila('S4', 'rechazado', '2026-09-30T10:00:00.000Z'), // fila 5
      fila('O1', 'entregado', '2026-10-02T10:00:00.000Z'), // fila 6: octubre, se queda
    ];
    archivo = null;
    mockValores.get.mockReset().mockImplementation(async ({ range }) => {
      if (range.startsWith("'Guías 2026'")) return { data: { values: archivo || [] } };
      return { data: { values: activa } };
    });
    mockValores.update.mockReset().mockResolvedValue({});
    mockValores.batchUpdate.mockReset().mockResolvedValue({});
    mockHojas.get.mockReset().mockImplementation(async () => ({
      data: {
        sheets: [
          { properties: { title: 'Guias', sheetId: 0 } },
          ...(archivo ? [{ properties: { title: 'Guías 2026', sheetId: 7 } }] : []),
        ],
      },
    }));
    mockHojas.batchUpdate.mockReset().mockResolvedValue({});
    repo = require('./sheetsRepository');
  });

  it('la simulación no escribe nada', async () => {
    const res = await repo.archivarGuias('2026-10-01');
    expect(res).toEqual({ ejecutar: false, total: 3, porPestana: { 'Guías 2026': 3 } });
    expect(mockValores.update).not.toHaveBeenCalled();
    expect(mockHojas.batchUpdate).not.toHaveBeenCalled();
  });

  it('copia las cerradas con encabezado y borra sus filas, juntando las seguidas', async () => {
    await repo.archivarGuias('2026-10-01', { ejecutar: true });
    const escrito = mockValores.update.mock.calls[0][0];
    expect(escrito.range).toMatch(/^'Guías 2026'!A1:/);
    expect(escrito.requestBody.values.map((f) => f[0])).toEqual([
      'numero_guia', 'S1', 'S3', 'S4',
    ]);
    const crear = mockHojas.batchUpdate.mock.calls[0][0].requestBody.requests[0];
    expect(crear.addSheet.properties.title).toBe('Guías 2026');
    const borrar = mockHojas.batchUpdate.mock.calls[1][0].requestBody.requests;
    // Filas 4-5 (de una vez) y luego la 2; la 3 (abierta) y la 6 se quedan.
    expect(borrar.map((r) => r.deleteDimension.range)).toEqual([
      { sheetId: 0, dimension: 'ROWS', startIndex: 3, endIndex: 5 },
      { sheetId: 0, dimension: 'ROWS', startIndex: 1, endIndex: 2 },
    ]);
  });

  it('si un intento anterior ya las copió, no las repite', async () => {
    archivo = [COLUMNS, fila('S1', 'entregado', '2026-09-28T10:00:00.000Z')];
    await repo.archivarGuias('2026-10-01', { ejecutar: true });
    const escrito = mockValores.update.mock.calls[0][0];
    expect(escrito.range).toMatch(/^'Guías 2026'!A3:/);
    expect(escrito.requestBody.values.map((f) => f[0])).toEqual(['S3', 'S4']);
  });

  it('si la hoja cambió antes de borrar, no borra nada', async () => {
    mockValores.update.mockImplementation(async () => {
      // Alguien borró una fila mientras se copiaba: todo sube una fila.
      activa = [activa[0], ...activa.slice(2)];
      return {};
    });
    await expect(repo.archivarGuias('2026-10-01', { ejecutar: true })).rejects.toMatchObject({
      status: 409,
    });
    const borrados = mockHojas.batchUpdate.mock.calls.filter(
      ([p]) => p.requestBody.requests[0].deleteDimension,
    );
    expect(borrados).toHaveLength(0);
  });

  it('reconoce el archivo solo y recuerda la última fecha archivada', async () => {
    expect(await repo.infoArchivo()).toEqual({ pestanas: [], ultima: null });
    jest.resetModules();
    repo = require('./sheetsRepository');
    archivo = [
      ['fecha_creacion'],
      ['2026-09-28T10:00:00.000Z'],
      ['2026-09-30T10:00:00.000Z'],
    ];
    expect(await repo.infoArchivo()).toEqual({
      pestanas: ['Guías 2026'],
      ultima: Date.parse('2026-09-30T10:00:00.000Z'),
    });
  });
});
