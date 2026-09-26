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
