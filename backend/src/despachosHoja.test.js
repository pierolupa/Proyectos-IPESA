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
      // Como Sheets: solo las filas del rango pedido (A<fila inicial>:<final>).
      const [, inicio, fin] = /!A(\d+):I(\d+)$/.exec(range);
      // Fila i de la hoja (desde la 2) ↔ fechas[i-2]: aquí una fila por cada fecha.
      const filas = [
        [fechas[0], 0.4, 'T001-1', 'Cliente 1', 1, '', '', 11, 22], // 01/10: fuera del rango
        [fechas[1], 0.5, 'T001-2', 'Cliente 2', 1, '', '', 11, 22],
        [fechas[2], 0.6, 'T001-3', 'Cliente 3', 1, '', '', 33, 44],
        [fechas[3], 0.7, 'T001-4', 'Cliente 4', 1, '', '', 33, 44], // 03/10 (hasta es exclusivo)
        // Fila nueva: al principio no tiene fecha (se omite).
        [fechas[4], 0.7, 'T001-9', 'Cliente 9', 1, '', '', 55, 66],
      ];
      return { data: { values: filas.slice(+inicio - 2, +fin - 1) } };
    });
    const repo = require('./sheetsRepository');
    const desde = Date.parse('2026-10-02T05:00:00Z');
    const hasta = Date.parse('2026-10-03T05:00:00Z');
    const lista = await repo.listarDespachos({ desde, hasta });
    expect(lista.map((d) => d.numero_guia)).toEqual(['T001-2', 'T001-3']);
    const rangos = mockValores.get.mock.calls.map(([p]) => p.range);
    expect(rangos).toEqual(["'Base de datos'!1:1", "'Base de datos'!A2:A", "'Base de datos'!A3:I4"]);

    // Una fila nueva aparece cuando vence la caché de fechas (1 minuto).
    fechas.push(serial('2026-10-02'));
    const t0 = Date.now();
    const ahora = jest.spyOn(Date, 'now').mockReturnValue(t0 + 30 * 1000);
    mockValores.get.mockClear();
    const dentroDeLaCache = await repo.listarDespachos({ desde, hasta });
    expect(dentroDeLaCache.map((d) => d.numero_guia)).toEqual(['T001-2', 'T001-3']);
    expect(mockValores.get).toHaveBeenCalledTimes(1);

    ahora.mockReturnValue(t0 + 61 * 1000);
    const despues = await repo.listarDespachos({ desde, hasta });
    ahora.mockRestore();
    expect(despues.map((d) => d.numero_guia)).toEqual(['T001-2', 'T001-3', 'T001-9']);
  });
});
