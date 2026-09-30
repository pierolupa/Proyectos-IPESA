// jest.mock automático de googleapis/google-auth-library no aplica aquí:
// rowToUsuario/rowToGuia son funciones puras, no llaman a la API.
const { rowToUsuario, rowToGuia } = require('./sheetsRepository');

describe('rowToUsuario', () => {
  it('interpreta "TRUE" (mayúsculas, como autoformatea Google Sheets) como activo', () => {
    const usuario = rowToUsuario(['Juan Pérez', 'transportista', '1234', 'TRUE']);
    expect(usuario.activo).toBe(true);
  });

  it('interpreta "true" (minúsculas) como activo', () => {
    const usuario = rowToUsuario(['Juan Pérez', 'transportista', '1234', 'true']);
    expect(usuario.activo).toBe(true);
  });

  it('interpreta "FALSE" como inactivo', () => {
    const usuario = rowToUsuario(['Juan Pérez', 'transportista', '1234', 'FALSE']);
    expect(usuario.activo).toBe(false);
  });

  it('interpreta una celda vacía como inactivo', () => {
    const usuario = rowToUsuario(['Juan Pérez', 'transportista', '1234']);
    expect(usuario.activo).toBe(false);
  });
});

describe('rowToGuia', () => {
  it('interpreta "TRUE" en corregido_por_admin sin importar mayúsculas', () => {
    const guia = rowToGuia(
      [
        'IPE-2026-000123',
        'en_ruta',
        'cliente_final',
        'Almacén Callao',
        'Av. Siempre Viva 742',
        'Juan Pérez',
        'María Torres',
        '-12.05',
        '-77.04',
        'TRUE',
        '2026-01-01T00:00:00.000Z',
        '2026-01-01T00:00:00.000Z',
      ],
      2,
    );
    expect(guia.corregido_por_admin).toBe(true);
  });
});

describe('rowToSucursal', () => {
  const { rowToSucursal } = require('./sheetsRepository');

  it('lee coordenadas con coma decimal', () => {
    expect(rowToSucursal(['Sucursal Arequipa', '-16,4', '-71,53', '200'], 3)).toEqual({
      nombre: 'Sucursal Arequipa',
      lat: -16.4,
      lng: -71.53,
      radio_m: 200,
      _row: 3,
    });
  });
});

describe('columnas por nombre (hoja de guías)', () => {
  const { mapearColumnas, guiaToRow, letraColumna } = require('./sheetsRepository');
  const { COLUMNS } = require('./columns');

  it('lee cada dato por su encabezado aunque las columnas estén en otro orden', () => {
    const encabezados = ['estado', 'Mi nota', 'numero_guia', ...COLUMNS.slice(2)];
    const mapa = mapearColumnas(encabezados);
    const fila = ['entregado', 'algo mío', 'T1', 'cliente_final'];
    const guia = rowToGuia(fila, 2, mapa);
    expect(guia.numero_guia).toBe('T1');
    expect(guia.estado).toBe('entregado');
    expect(guia.tipo_entrega).toBe('cliente_final');
  });

  it('al escribir no toca las columnas que no conoce', () => {
    const encabezados = ['numero_guia', 'Mi nota', ...COLUMNS.slice(1)];
    const mapa = mapearColumnas(encabezados);
    const guia = rowToGuia(['T1', 'no borrar', 'en_ruta'], 2, mapa);
    guia.estado = 'entregado';
    const escrita = guiaToRow(guia, mapa);
    expect(escrita[0]).toBe('T1');
    expect(escrita[1]).toBe('no borrar');
    expect(escrita[2]).toBe('entregado');
  });

  it('un valor que no es de transbordo no cuenta como transbordo', () => {
    const mapa = mapearColumnas(COLUMNS);
    const fila = [];
    fila[COLUMNS.indexOf('numero_guia')] = 'T1';
    fila[COLUMNS.indexOf('estado')] = 'en_ruta';
    fila[COLUMNS.indexOf('transbordo_estado')] = '-12.0464';
    expect(rowToGuia(fila, 2, mapa).transbordo_estado).toBe('');
  });

  it('nombra columnas más allá de la Z', () => {
    expect(letraColumna(1)).toBe('A');
    expect(letraColumna(26)).toBe('Z');
    expect(letraColumna(27)).toBe('AA');
    expect(letraColumna(52)).toBe('AZ');
  });
});

