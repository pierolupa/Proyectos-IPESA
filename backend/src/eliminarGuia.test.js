// Borrar la fila de una guía (sheetsRepository.eliminarGuia): la API de
// Google se simula.
const mockValores = { get: jest.fn(), update: jest.fn() };
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

// La fila 1 (encabezados) o la fila que se va a borrar, según el rango.
const hoja = (filaDeDatos) => async ({ range }) => ({
  data: { values: [range.endsWith('1:ZZ1') ? COLUMNS : filaDeDatos] },
});

const fila = (numero, creada) => [
  numero, 'en_ruta', 'cliente_final', 'Almacén', 'Destino', 'Juan', 'Cliente',
  '', '', 'FALSE', creada, creada,
];

describe('eliminarGuia', () => {
  let repo;

  beforeEach(() => {
    jest.resetModules();
    process.env.SHEET_ID = 'hoja-de-prueba';
    mockHojas.get.mockReset().mockResolvedValue({
      data: { sheets: [{ properties: { sheetId: 77, title: 'Guias' } }] },
    });
    mockHojas.batchUpdate.mockReset().mockResolvedValue({});
    repo = require('./sheetsRepository');
  });

  it('borra la fila de la guía en la pestaña Guias', async () => {
    mockValores.get.mockReset().mockImplementation(
      hoja(fila('T1', '2026-09-28T10:00:00.000Z')),
    );
    await repo.eliminarGuia({
      numero_guia: 'T1',
      fecha_creacion: '2026-09-28T10:00:00.000Z',
      _row: 5,
    });
    const pedido = mockHojas.batchUpdate.mock.calls[0][0].requestBody.requests[0];
    expect(pedido.deleteDimension.range).toEqual({
      sheetId: 77,
      dimension: 'ROWS',
      startIndex: 4,
      endIndex: 5,
    });
  });

  it('no borra si en esa fila ya hay otra guía', async () => {
    mockValores.get.mockReset().mockImplementation(
      hoja(fila('T9', '2026-09-28T10:00:00.000Z')),
    );
    await expect(
      repo.eliminarGuia({
        numero_guia: 'T1',
        fecha_creacion: '2026-09-28T10:00:00.000Z',
        _row: 5,
      }),
    ).rejects.toMatchObject({ status: 409 });
    expect(mockHojas.batchUpdate).not.toHaveBeenCalled();
  });
});
