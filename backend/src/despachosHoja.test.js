// Lectura de la hoja Despachos Ate contra una hoja simulada: solo la columna
// de fechas y después solo las filas del rango.
const mockValores = { get: jest.fn() };

jest.mock('googleapis', () => ({
  google: { sheets: () => ({ spreadsheets: { values: mockValores } }) },
}));
jest.mock('google-auth-library', () => ({
  GoogleAuth: jest.fn().mockImplementation(() => ({ getClient: async () => ({}) })),
}));

const serial = (iso) => (Date.parse(`${iso}T00:00:00Z`) - Date.UTC(1899, 11, 30)) / 86400000;

describe('listarDespachos', () => {
  it('lee la columna de fechas una vez y luego solo las filas pedidas', async () => {
    jest.resetModules();
    const fechas = [serial('2026-10-01'), serial('2026-10-02'), serial('2026-10-02'), serial('2026-10-03')];
    mockValores.get.mockImplementation(async ({ range }) => {
      if (range.endsWith('!1:1')) {
        return { data: { values: [['Fecha de Extraccion', 'Hora', 'Nro de guia', 'Cliente', 'RUC', 'P', 'L', 'Pedido', 'Entrega']] } };
      }
      if (range.endsWith('!A2:A')) return { data: { values: fechas.map((f) => [f]) } };
      return {
        data: {
          values: [
            [fechas[1], 0.5, 'T001-2', 'Cliente 2', 1, '', '', 11, 22],
            [fechas[2], 0.6, 'T001-3', 'Cliente 3', 1, '', '', 33, 44],
          ],
        },
      };
    });
    const repo = require('./sheetsRepository');
    const desde = Date.parse('2026-10-02T05:00:00Z');
    const hasta = Date.parse('2026-10-03T05:00:00Z');
    const lista = await repo.listarDespachos({ desde, hasta });
    expect(lista.map((d) => d.numero_guia)).toEqual(['T001-2', 'T001-3']);
    const rangos = mockValores.get.mock.calls.map(([p]) => p.range);
    expect(rangos).toEqual(["'Base de datos'!1:1", "'Base de datos'!A2:A", "'Base de datos'!A3:I4"]);

    // La columna de fechas queda guardada unos minutos.
    await repo.listarDespachos({ desde, hasta });
    expect(mockValores.get).toHaveBeenCalledTimes(4);
  });
});
