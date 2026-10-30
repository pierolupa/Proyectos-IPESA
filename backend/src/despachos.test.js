const {
  columnasDespachos,
  filasADespachos,
  filasDelRango,
  despachosNuevos,
  instanteDe,
} = require('./despachos');

// Serial de Sheets de un día (días desde el 30/12/1899).
const serial = (iso) => (Date.parse(`${iso}T00:00:00Z`) - Date.UTC(1899, 11, 30)) / 86400000;

const ENCABEZADO = [
  'Fecha de Extraccion', 'Hora', 'Nro de guia', 'Cliente', 'RUC', 'Punto de Partida',
  'Punto de Llegada', 'Pedido', 'Entrega', 'Peso', 'Bulto', 'Transporte', 'Usuario',
  'Conductor', 'Tipo', 'Codigo', 'Surcusal ipesa',
];

describe('hoja Despachos Ate', () => {
  it('encuentra las columnas por nombre', () => {
    expect(columnasDespachos(ENCABEZADO)).toEqual({
      fecha: 0, hora: 1, guia: 2, cliente: 3, pedido: 7, entrega: 8, sucursal: 16, transporte: 11,
    });
    expect(() => columnasDespachos(['Cliente'])).toThrow();
  });

  it('la fecha y hora de la hoja son hora de Perú', () => {
    // 10/10/2026 12:22:37 en Perú = 17:22:37 UTC.
    const t = instanteDe(serial('2026-10-10'), (12 * 3600 + 22 * 60 + 37) / 86400);
    expect(new Date(t).toISOString()).toBe('2026-10-10T17:22:37.000Z');
  });

  it('toma solo guía, cliente, fecha, pedido y entrega', () => {
    const cols = columnasDespachos(ENCABEZADO);
    const filas = [
      [serial('2026-10-10'), 0.5, 'T001-95643', 'IPESA S.A.C.', 20101639275, 'Ate', 'Arequipa', 4900109327, 81115782, 2.7, 1, 'Toscano', 'x', '', '', '', 'CERRO COLORADO - AREQUIPA - AREQUIPA'],
      [serial('2026-10-10'), 0.5, '', 'sin guía'],
      ['', '', 'T001-1', 'sin fecha'],
      [serial('2026-10-10'), 0.25, 'T001-95668', 'IPESA S.A.C.', 1, '', '', 4900109360],
    ];
    expect(filasADespachos(filas, cols)).toEqual([
      {
        numero_guia: 'T001-95643',
        cliente: 'IPESA S.A.C.',
        fecha: '2026-10-10T17:00:00.000Z',
        numero_pedido: '4900109327',
        numero_entrega: '81115782',
        sucursal: 'CERRO COLORADO - AREQUIPA - AREQUIPA',
        transporte: 'Toscano',
      },
      {
        numero_guia: 'T001-95668',
        cliente: 'IPESA S.A.C.',
        fecha: '2026-10-10T11:00:00.000Z',
        numero_pedido: '4900109360',
        numero_entrega: '',
        sucursal: '',
        transporte: '',
      },
    ]);
  });

  it('lee solo las filas de los días pedidos', () => {
    const fechas = [serial('2026-10-01'), serial('2026-10-02') + 0.4, serial('2026-10-03'), serial('2026-10-05')];
    // Del 2 al 3 de octubre en Perú (00:00 Perú = 05:00 UTC).
    const r = filasDelRango(fechas, Date.parse('2026-10-02T05:00:00Z'), Date.parse('2026-10-04T05:00:00Z'));
    expect(r).toEqual({ primera: 1, ultima: 2 });
    expect(filasDelRango(fechas, Date.parse('2026-11-01T05:00:00Z'), null)).toBeNull();
  });

  it('omite las guías que ya están en la app y las repetidas', () => {
    const d = (numero, fecha) => ({ numero_guia: numero, cliente: 'C', fecha, numero_pedido: '', numero_entrega: '' });
    const lista = despachosNuevos(
      [
        d('T001-1', '2026-10-10T15:00:00.000Z'),
        d('T001-2', '2026-10-10T16:00:00.000Z'),
        d(' t001-2 ', '2026-10-10T16:30:00.000Z'),
        d('T001-3', '2026-10-10T17:00:00.000Z'),
        d('T001-4', '2026-10-01T17:00:00.000Z'),
      ],
      ['T001-1', 't001-3'],
      Date.parse('2026-10-10T05:00:00Z'),
      Date.parse('2026-10-11T05:00:00Z'),
    );
    expect(lista.map((x) => x.numero_guia)).toEqual(['T001-2']);
  });

  it('las de Toscano, Log, Aval y Amazon salen aunque estén en la app', () => {
    const d = (numero, transporte) => ({
      numero_guia: numero, cliente: 'C', fecha: '2026-10-10T15:00:00.000Z',
      numero_pedido: '', numero_entrega: '', transporte,
    });
    const lista = despachosNuevos(
      [d('T1', 'Toscano'), d('T2', 'Aval '), d('T3', 'LOG'), d('T4', 'Amazon'), d('T5', 'Natale'), d('T6', '')],
      ['T1', 'T2', 'T3', 'T4', 'T5', 'T6'],
      Date.parse('2026-10-10T05:00:00Z'),
      Date.parse('2026-10-11T05:00:00Z'),
    );
    expect(lista.map((x) => x.numero_guia).sort()).toEqual(['T1', 'T2', 'T3', 'T4']);
  });
});

describe('encabezado de fechas borrado', () => {
  // Así quedó la fila 1: la A sin nombre (ahí siguen las fechas).
  const SIN_FECHA = [
    '', 'Hora', 'Nro de guia', 'Cliente', 'RUC', 'Punto de Partida',
    'Punto de Llegada', 'Pedido', 'Entrega', 'Peso', 'Bulto', 'Transporte',
    'Usuario', 'Conductor', 'Tipo', 'Codigo', 'Sucursal ipesa',
  ];

  it('usa la columna sin nombre de antes de "Hora" como fecha', () => {
    const cols = columnasDespachos(SIN_FECHA);
    expect(cols).toMatchObject({ fecha: 0, hora: 1, guia: 2, cliente: 3, pedido: 7, entrega: 8, transporte: 11, sucursal: 16 });
  });

  it('sin "Hora", la A vacía sigue siendo la fecha', () => {
    expect(columnasDespachos(['', 'Nro de guia', 'Cliente']).fecha).toBe(0);
  });

  it('si no hay columna de guía, lo dice claro', () => {
    expect(() => columnasDespachos(['', 'Hora', 'Cliente'])).toThrow(/"Fecha" y "Nro de guia" en la fila 1/);
  });
});
