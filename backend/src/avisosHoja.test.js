// La pestaña "Avisos" contra una hoja simulada.
const mockValores = { get: jest.fn(), update: jest.fn(), clear: jest.fn() };
const mockHojas = { get: jest.fn(), batchUpdate: jest.fn() };

jest.mock('googleapis', () => ({
  google: { sheets: () => ({ spreadsheets: { values: mockValores, ...mockHojas } }) },
}));
jest.mock('google-auth-library', () => ({
  GoogleAuth: jest.fn().mockImplementation(() => ({ getClient: async () => ({}) })),
}));

describe('pestaña Avisos', () => {
  let repo;
  let filas;
  let existe;

  beforeEach(() => {
    jest.resetModules();
    process.env.SHEET_ID = 'hoja-de-prueba';
    existe = true;
    filas = [['Juan', 'https://x/1', 'p1', 'a1', '2026-11-01']];
    mockValores.get.mockReset().mockImplementation(async () => {
      if (!existe) throw Object.assign(new Error('Unable to parse range'), { code: 400 });
      return { data: { values: filas } };
    });
    mockValores.update.mockReset().mockResolvedValue({});
    mockValores.clear.mockReset().mockResolvedValue({});
    mockHojas.get.mockReset().mockImplementation(async () => ({
      data: { sheets: existe ? [{ properties: { title: 'Avisos', sheetId: 3 } }] : [] },
    }));
    mockHojas.batchUpdate.mockReset().mockImplementation(async () => {
      existe = true;
      return { data: { replies: [{ addSheet: { properties: { title: 'Avisos', sheetId: 3 } } }] } };
    });
    repo = require('./sheetsRepository');
  });

  it('sin pestaña no hay nadie suscrito', async () => {
    existe = false;
    expect(await repo.listarSuscripciones()).toEqual([]);
  });

  it('el mismo celular queda una sola vez, a nombre del último', async () => {
    await repo.guardarSuscripcion({ nombre: 'Luis', endpoint: 'https://x/1', p256dh: 'p2', auth: 'a2' });
    const escrito = mockValores.update.mock.calls[0][0].requestBody.values;
    expect(escrito[0]).toEqual(['nombre', 'endpoint', 'p256dh', 'auth', 'actualizado']);
    expect(escrito).toHaveLength(2);
    expect(escrito[1].slice(0, 4)).toEqual(['Luis', 'https://x/1', 'p2', 'a2']);
  });

  it('crea la pestaña la primera vez', async () => {
    existe = false;
    filas = [];
    await repo.guardarSuscripcion({ nombre: 'Juan', endpoint: 'https://x/9', p256dh: 'p', auth: 'a' });
    expect(mockHojas.batchUpdate.mock.calls[0][0].requestBody.requests[0].addSheet.properties.title)
      .toBe('Avisos');
  });

  it('quita los celulares dados de baja y deja los demás', async () => {
    filas = [['Juan', 'https://x/1', 'p', 'a', ''], ['Luis', 'https://x/2', 'p', 'a', '']];
    await repo.quitarSuscripciones(['https://x/1']);
    const escrito = mockValores.update.mock.calls[0][0].requestBody.values;
    expect(escrito.slice(1).map((f) => f[1])).toEqual(['https://x/2']);
  });
});
