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

describe('columnas por posición (hoja de guías)', () => {
  const { guiaToRow, letraColumna, ordenarHoja } = require('./sheetsRepository');
  const { COLUMNS } = require('./columns');
  const col = (nombre) => COLUMNS.indexOf(nombre);

  // Encabezados como en la hoja real: A..S con nombres propios.
  const PROPIOS = [
    ...COLUMNS.slice(0, 12),
    'Nro Pedido', 'Nro Entrega', 'Latitud entrega', 'Longitud entrega',
    'fecha_entrega', 'Foto', 'Observacion',
  ];
  // Los que agregó la versión que leía por nombre: T..AE.
  const MOVIDOS = [...PROPIOS, ...COLUMNS.slice(12)];

  const base = (numero, estado = 'en_ruta', actualizada = '2026-09-29T10:00:00.000Z') => [
    numero, estado, 'cliente_final', 'Trp Callao', 'Huaraz', 'Diego', 'Cliente',
    '-12.1', '-77.1', 'FALSE', '2026-09-29T09:00:00.000Z', actualizada,
  ];

  it('lee la foto de la columna R aunque el encabezado se llame "Foto"', () => {
    const fila = base('T1', 'entregado');
    fila[col('foto_entrega_url')] = 'drive:abc';
    const guia = rowToGuia(fila, 2);
    expect(col('foto_entrega_url')).toBe(17); // R
    expect(guia.foto_entrega_url).toBe('drive:abc');
  });

  it('al escribir no toca las columnas después de la X', () => {
    const fila = base('T1');
    fila[26] = 'nota mía';
    const guia = rowToGuia(fila, 2);
    guia.estado = 'entregado';
    const escrita = guiaToRow(guia);
    expect(escrita[1]).toBe('entregado');
    expect(escrita[26]).toBe('nota mía');
  });

  it('un valor que no es de transbordo no cuenta como transbordo', () => {
    const fila = base('T1');
    fila[col('transbordo_estado')] = '-12.0464';
    fila[col('transbordo_a')] = '-77.03';
    const guia = rowToGuia(fila, 2);
    expect(guia.transbordo_estado).toBe('');
    expect(guia.transbordo_a).toBe('');
  });

  it('solo escribe los encabezados de T a X; A..S no se tocan', () => {
    const { encabezados, cambiadas } = ordenarHoja(PROPIOS, [base('T1')]);
    expect(cambiadas).toEqual([]);
    expect(encabezados).toEqual({ desde: 19, valores: COLUMNS.slice(19) });
  });

  it('con la hoja en orden no cambia nada', () => {
    const orden = ordenarHoja([...PROPIOS, ...COLUMNS.slice(19)], [base('T1')]);
    expect(orden.cambiadas).toEqual([]);
    expect(orden.encabezados).toBeNull();
  });

  describe('devuelve a su columna lo que quedó después de la S', () => {
    const movida = (datos) => {
      const fila = base('T2', 'entregado');
      Object.entries(datos).forEach(([nombre, valor]) => {
        fila[19 + col(nombre) - 12] = valor;
      });
      return fila;
    };

    it('guía registrada o entregada con las columnas corridas', () => {
      const fila = movida({
        numero_pedido: 'P-1', numero_entrega: 'E-1', cierre_lat: '-9.5',
        cierre_lng: '-77.5', fecha_cierre: '2026-09-29T10:00:00.000Z',
        foto_entrega_url: 'drive:foto', eliminacion: '', transbordo_estado: '',
      });
      const orden = ordenarHoja(MOVIDOS, [fila]);
      const g = rowToGuia(orden.filas[0], 2);
      expect(g.numero_pedido).toBe('P-1');
      expect(g.numero_entrega).toBe('E-1');
      expect(g.cierre_lat).toBe('-9.5');
      expect(g.cierre_lng).toBe('-77.5');
      expect(g.fecha_cierre).toBe('2026-09-29T10:00:00.000Z');
      expect(g.foto_entrega_url).toBe('drive:foto');
      expect(g.eliminacion).toBe('');
      expect(g.transbordo_estado).toBe('');
      expect(orden.filas[0].slice(24).every((v) => v === '')).toBe(true);
      expect(orden.cambiadas).toEqual([0]);
      // Encabezados: T..X correctos y los de más allá, vacíos.
      expect(orden.encabezados).toEqual({
        desde: 19,
        valores: [...COLUMNS.slice(19), '', '', '', '', '', '', ''],
      });
    });

    it('una guía de antes conserva sus datos de A..S y su eliminación', () => {
      const fila = base('T3');
      fila[col('numero_pedido')] = 'P-3';
      fila[col('foto_entrega_url')] = 'drive:vieja';
      fila[col('eliminacion')] = 'pendiente';
      fila[col('motivo_eliminacion')] = 'duplicada';
      fila[col('transbordo_estado')] = 'pendiente';
      fila[col('transbordo_a')] = 'Juan';
      const orden = ordenarHoja(MOVIDOS, [fila]);
      const g = rowToGuia(orden.filas[0], 2);
      expect(g.numero_pedido).toBe('P-3');
      expect(g.foto_entrega_url).toBe('drive:vieja');
      expect(g.eliminacion).toBe('pendiente');
      expect(g.motivo_eliminacion).toBe('duplicada');
      expect(g.transbordo_estado).toBe('pendiente');
      expect(g.transbordo_a).toBe('Juan');
      expect(orden.cambiadas).toEqual([]);
    });

    it('la eliminación y el transbordo escritos después de la X también vuelven', () => {
      const fila = movida({
        numero_pedido: 'P-4', eliminacion: 'pendiente', motivo_eliminacion: 'error',
      });
      const g = rowToGuia(ordenarHoja(MOVIDOS, [fila]).filas[0], 2);
      expect(g.numero_pedido).toBe('P-4');
      expect(g.eliminacion).toBe('pendiente');
      expect(g.motivo_eliminacion).toBe('error');
    });

    it('coordenadas sueltas sin fecha de cierre se descartan', () => {
      const fila = base('T5');
      fila[col('cierre_lat')] = '-8.1';
      fila[col('transbordo_estado')] = '-12.05'; // resto de salida_lat
      fila[col('transbordo_a')] = '-77.04';
      const g = rowToGuia(ordenarHoja(MOVIDOS, [fila]).filas[0], 2);
      expect(g.cierre_lat).toBe('-8.1');
      expect(g.cierre_lng).toBe('');
    });

    it('un resto suelto de entrega pasa a la guía entregada sin foto de esa fecha', () => {
      const fecha = '2026-09-29T15:00:00.000Z';
      const guia = base('T035-7954', 'entregado', fecha);
      const resto = [];
      resto[21] = '-9.53';
      resto[22] = '-77.52';
      resto[23] = fecha;
      resto[24] = 'drive:la-foto';
      const orden = ordenarHoja(MOVIDOS, [resto, guia]);
      const g = rowToGuia(orden.filas[1], 3);
      expect(g.foto_entrega_url).toBe('drive:la-foto');
      expect(g.cierre_lat).toBe('-9.53');
      expect(g.fecha_cierre).toBe(fecha);
      expect(orden.filas[0].every((v) => v === '' || v === undefined)).toBe(true);
      expect(orden.cambiadas).toEqual([0, 1]);
    });

    it('un resto suelto sin una guía que le corresponda queda como está', () => {
      const resto = [];
      resto[23] = '2026-09-29T15:00:00.000Z';
      resto[24] = 'drive:la-foto';
      const orden = ordenarHoja(MOVIDOS, [resto, base('T6', 'en_ruta')]);
      expect(orden.cambiadas).toEqual([]);
      expect(orden.filas[0][24]).toBe('drive:la-foto');
    });
  });

  it('nombra columnas más allá de la Z', () => {
    expect(letraColumna(1)).toBe('A');
    expect(letraColumna(26)).toBe('Z');
    expect(letraColumna(27)).toBe('AA');
    expect(letraColumna(52)).toBe('AZ');
  });
});
