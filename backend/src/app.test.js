jest.mock('./sheetsRepository');
// La IA se simula; la limpieza de lo que lee (comprobanteDe...) es la real.
jest.mock('./ocrAgente', () => ({
  ...jest.requireActual('./ocrAgente'),
  leerGuiaConIA: jest.fn(),
  leerNumeroGuia: jest.fn(),
  leerComprobante: jest.fn(),
}));
jest.mock('./fotos', () => ({
  ...jest.requireActual('./fotos'),
  guardarFoto: jest.fn(),
  enviarFoto: jest.fn(),
  eliminarFoto: jest.fn(),
}));

const request = require('supertest');
const repo = require('./sheetsRepository');
const { leerGuiaConIA, leerNumeroGuia, leerComprobante } = require('./ocrAgente');
const fotos = require('./fotos');
const { ESTADOS, TIPOS_ENTREGA, ROLES, TRANSBORDO } = require('./columns');

const app = require('./app');

function guia(overrides = {}) {
  return {
    numero_guia: 'IPE-2026-000123',
    estado: ESTADOS.EN_RUTA,
    tipo_entrega: TIPOS_ENTREGA.CLIENTE_FINAL,
    origen: 'Almacén Callao',
    destino: 'Av. Siempre Viva 742',
    transportista: 'Juan Pérez',
    destinatario: 'María Torres',
    geo_lat: -12.05,
    geo_lng: -77.04,
    corregido_por_admin: false,
    fecha_creacion: '2026-01-01T00:00:00.000Z',
    fecha_actualizacion: '2026-01-01T00:00:00.000Z',
    _row: 2,
    ...overrides,
  };
}

beforeEach(() => {
  jest.resetAllMocks();
  repo.listarGuias.mockResolvedValue([]);
  repo.listarSucursales.mockResolvedValue([]);
});

describe('POST /guias (asignación)', () => {
  const payload = {
    numeroGuia: 'IPE-2026-000999',
    tipoEntrega: TIPOS_ENTREGA.CLIENTE_FINAL,
    origen: 'Almacén Callao',
    destino: 'Av. Siempre Viva 742',
    transportista: 'Juan Pérez',
    destinatario: 'María Torres',
    geo: { lat: -12.05, lng: -77.04 },
  };

  it('rechaza la asignación si no hay GPS', async () => {
    const res = await request(app)
      .post('/guias')
      .send({ ...payload, geo: undefined });
    expect(res.status).toBe(400);
    expect(repo.crearGuias).not.toHaveBeenCalled();
  });

  // Hora fija para que "el mismo día" no dependa de cuándo corre la prueba:
  // 2026-10-02 18:00 en Perú (23:00 UTC).
  const ahoraPeru = Date.parse('2026-10-02T23:00:00.000Z');
  const haceMin = (min) => new Date(ahoraPeru - min * 60000).toISOString();

  it('el mismo transportista no registra la misma guía el mismo día', async () => {
    jest.spyOn(Date, 'now').mockReturnValue(ahoraPeru);
    // Hoy a las 07:00 de Perú: 11 horas antes, pero el mismo día.
    repo.listarGuias.mockResolvedValue([
      guia({ numero_guia: payload.numeroGuia, transportista: 'juan pérez ', fecha_creacion: haceMin(11 * 60) }),
    ]);
    const res = await request(app).post('/guias').send(payload);
    Date.now.mockRestore();
    expect(res.status).toBe(409);
    expect(res.body.error).toMatch(/Ya registraste .* hoy a las 07:00/);
    expect(res.body.error).toMatch(/mismo día/);
    expect(repo.crearGuias).not.toHaveBeenCalled();
    // La comprobación lee la hoja sin caché.
    expect(repo.listarGuias).toHaveBeenCalledWith({ fresco: true });
  });

  it('el mismo transportista la puede registrar otra vez al día siguiente', async () => {
    jest.spyOn(Date, 'now').mockReturnValue(ahoraPeru);
    // Ayer a las 23:30 de Perú: menos de 24 horas, pero otro día.
    repo.listarGuias.mockResolvedValue([
      guia({ numero_guia: payload.numeroGuia, fecha_creacion: haceMin(18 * 60 + 30) }),
    ]);
    const res = await request(app).post('/guias').send(payload);
    Date.now.mockRestore();
    expect(res.status).toBe(201);
    expect(repo.crearGuias).toHaveBeenCalledTimes(1);
  });

  it('otro transportista la puede registrar al momento, aunque siga activa', async () => {
    const hace5 = new Date(Date.now() - 5 * 60000).toISOString();
    repo.listarGuias.mockResolvedValue([
      guia({ numero_guia: payload.numeroGuia, transportista: 'Diego', fecha_creacion: hace5 }),
    ]);
    const res = await request(app).post('/guias').send(payload);
    expect(res.status).toBe(201);
    expect(repo.crearGuias).toHaveBeenCalledTimes(1);
  });

  it('crea la guía en estado en_ruta cuando no hay duplicado', async () => {
    repo.buscarPorNumero.mockResolvedValue(null);
    const res = await request(app).post('/guias').send(payload);
    expect(res.status).toBe(201);
    expect(res.body.estado).toBe(ESTADOS.EN_RUTA);
    // Devuelve la guía completa para que la app no recargue todo.
    expect(res.body).toMatchObject({
      numero_guia: payload.numeroGuia,
      destinatario: payload.destinatario,
      transportista: payload.transportista,
    });
    expect(res.body.fecha_creacion).toBeTruthy();
    expect(repo.crearGuias).toHaveBeenCalledWith([
      expect.objectContaining({ numero_guia: payload.numeroGuia, estado: ESTADOS.EN_RUTA }),
    ]);
  });
});

describe('Despacho Corte', () => {
  const datos = (numero, extra = {}) => ({
    numeroGuia: numero,
    tipoEntrega: TIPOS_ENTREGA.CLIENTE_FINAL,
    origen: 'Almacén Callao',
    destino: 'Av. Siempre Viva 742',
    transportista: 'Juan Pérez',
    destinatario: 'María Torres',
    geo: { lat: -12.05, lng: -77.04 },
    ...extra,
  });

  it('registra todas las guías con un mismo código de corte', async () => {
    const res = await request(app)
      .post('/despachos-corte')
      .send({ guias: [datos('T1'), datos('T2'), datos('T3', { geo: undefined })] });
    expect(res.status).toBe(200);
    expect(res.body.despacho_corte).toMatch(/^DC-\d{6}-\d{4}-[A-Z0-9]{2}$/);
    const creadas = repo.crearGuias.mock.calls[0][0];
    expect(creadas.map((g) => g.numero_guia)).toEqual(['T1', 'T2']);
    expect(creadas.every((g) => g.despacho_corte === res.body.despacho_corte)).toBe(true);
    expect(res.body.resultados[2].error).toMatch(/GPS obligatorio/);
    expect(repo.listarGuias).toHaveBeenCalledTimes(1);
  });

  it('con el código de un corte en camino, las suma a ese corte', async () => {
    repo.listarGuias.mockResolvedValue([guia({ numero_guia: 'T0', despacho_corte: 'DC-1' })]);
    const res = await request(app)
      .post('/despachos-corte')
      .send({ guias: [datos('T5')], despachoCorte: 'DC-1' });
    expect(res.body.despacho_corte).toBe('DC-1');
    expect(repo.crearGuias.mock.calls[0][0][0].despacho_corte).toBe('DC-1');
  });

  it('no suma guías a un corte que ya llegó', async () => {
    repo.listarGuias.mockResolvedValue([
      guia({ despacho_corte: 'DC-1', estado: ESTADOS.ENTREGADO }),
    ]);
    const res = await request(app)
      .post('/despachos-corte')
      .send({ guias: [datos('T5')], despachoCorte: 'DC-1' });
    expect(res.status).toBe(409);
    expect(repo.crearGuias).not.toHaveBeenCalled();
  });

  it('al llegar, todas las guías en camino pasan a entregado de una vez', async () => {
    const corte = 'DC-261001-1542-K7';
    repo.listarGuias.mockResolvedValue([
      guia({ numero_guia: 'T1', despacho_corte: corte, _row: 2 }),
      guia({ numero_guia: 'T2', despacho_corte: corte, _row: 3 }),
      guia({ numero_guia: 'T3', despacho_corte: corte, estado: ESTADOS.RECHAZADO, _row: 4 }),
      guia({ numero_guia: 'T4', despacho_corte: '', _row: 5 }),
    ]);
    const res = await request(app)
      .post(`/despachos-corte/${corte}/llegada`)
      .send({ geo: { lat: -12.1, lng: -77.0 }, transportista: 'Juan Pérez' });
    expect(res.status).toBe(200);
    expect(repo.actualizarGuias).toHaveBeenCalledTimes(1);
    const actualizadas = repo.actualizarGuias.mock.calls[0][0];
    expect(actualizadas.map((g) => g.numero_guia)).toEqual(['T1', 'T2']);
    for (const g of actualizadas) {
      expect(g.estado).toBe(ESTADOS.ENTREGADO);
      expect(g.cierre_lat).toBe(-12.1);
      expect(g.fecha_cierre).toBe(g.fecha_actualizacion);
    }
    expect(res.body.guias).toHaveLength(2);
    expect(res.body.guias[0]._row).toBeUndefined();
  });

  it('la llegada exige GPS y que el corte tenga guías en camino', async () => {
    let res = await request(app).post('/despachos-corte/DC-X/llegada').send({});
    expect(res.status).toBe(400);
    res = await request(app)
      .post('/despachos-corte/DC-X/llegada')
      .send({ geo: { lat: -12.1, lng: -77.0 } });
    expect(res.status).toBe(404);
    expect(repo.actualizarGuias).not.toHaveBeenCalled();
  });

  it('otro transportista no puede marcar la llegada', async () => {
    repo.listarGuias.mockResolvedValue([guia({ despacho_corte: 'DC-1' })]);
    const res = await request(app)
      .post('/despachos-corte/DC-1/llegada')
      .send({ geo: { lat: -12.1, lng: -77.0 }, transportista: 'Diego' });
    expect(res.status).toBe(403);
    expect(repo.actualizarGuias).not.toHaveBeenCalled();
  });

  it('quitar una guía del corte la deja como tarea normal', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia({ despacho_corte: 'DC-1' }));
    const res = await request(app)
      .post('/despachos-corte/DC-1/quitar')
      .send({ numeroGuia: 'IPE-2026-000123' });
    expect(res.status).toBe(200);
    expect(res.body.despacho_corte).toBe('');
    expect(repo.actualizarGuia).toHaveBeenCalledWith(
      2,
      expect.objectContaining({ despacho_corte: '' }),
    );
  });

  it('no quita una guía de otro corte', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia({ despacho_corte: 'DC-2' }));
    const res = await request(app)
      .post('/despachos-corte/DC-1/quitar')
      .send({ numeroGuia: 'IPE-2026-000123' });
    expect(res.status).toBe(404);
    expect(repo.actualizarGuia).not.toHaveBeenCalled();
  });
});

describe('POST /guias/lote (carga masiva)', () => {
  const datos = (numero, extra = {}) => ({
    numeroGuia: numero,
    tipoEntrega: TIPOS_ENTREGA.CLIENTE_FINAL,
    origen: 'Almacén Callao',
    destino: 'Av. Siempre Viva 742',
    transportista: 'Juan Pérez',
    destinatario: 'María Torres',
    geo: { lat: -12.05, lng: -77.04 },
    ...extra,
  });

  it('registra 30 guías con una sola lectura y una sola escritura', async () => {
    const guias = Array.from({ length: 30 }, (_, i) => datos(`T${i}`));
    const res = await request(app).post('/guias/lote').send({ guias });
    expect(res.status).toBe(200);
    expect(res.body.resultados).toHaveLength(30);
    expect(res.body.resultados.every((r) => r.guia && !r.error)).toBe(true);
    expect(res.body.resultados[29].guia.numero_guia).toBe('T29');
    expect(repo.listarGuias).toHaveBeenCalledTimes(1);
    expect(repo.crearGuias).toHaveBeenCalledTimes(1);
    expect(repo.crearGuias.mock.calls[0][0]).toHaveLength(30);
  });

  it('no acepta más de 30', async () => {
    const guias = Array.from({ length: 31 }, (_, i) => datos(`T${i}`));
    const res = await request(app).post('/guias/lote').send({ guias });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Máximo 30/);
    expect(repo.crearGuias).not.toHaveBeenCalled();
  });

  it('las que fallan vuelven con su error y las demás se registran', async () => {
    const hace5 = new Date(Date.now() - 5 * 60000).toISOString();
    repo.listarGuias.mockResolvedValue([
      guia({ numero_guia: 'T1', fecha_creacion: hace5 }),
    ]);
    const res = await request(app).post('/guias/lote').send({
      guias: [datos('T1'), datos('T2'), datos('T3', { geo: undefined }), datos('T2')],
    });
    const [yaRegistrada, nueva, sinGps, repetida] = res.body.resultados;
    expect(yaRegistrada.error).toMatch(/Ya registraste la guía T1/);
    expect(nueva.guia.numero_guia).toBe('T2');
    expect(sinGps.error).toMatch(/GPS obligatorio/);
    // La misma guía dos veces en la misma carga: una sola vez.
    expect(repetida.error).toMatch(/Ya registraste la guía T2/);
    expect(repo.crearGuias.mock.calls[0][0].map((g) => g.numero_guia)).toEqual(['T2']);
  });

  it('si ninguna es válida, no escribe en la hoja', async () => {
    const res = await request(app).post('/guias/lote').send({
      guias: [datos('T1', { destinatario: '' })],
    });
    expect(res.status).toBe(200);
    expect(res.body.resultados[0].error).toBe('Faltan campos obligatorios.');
    expect(repo.crearGuias).not.toHaveBeenCalled();
  });
});

describe('PATCH /guias/:numeroGuia/estado', () => {
  it('exige GPS cuando no lo hace un administrador', async () => {
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ estado: ESTADOS.ENTREGADO });
    expect(res.status).toBe(400);
  });

  it('permite a un administrador cambiar el estado sin GPS', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ estado: ESTADOS.ENTREGADO, porAdmin: true });
    expect(res.status).toBe(200);
    expect(res.body.corregido_por_admin).toBe(true);
    expect(repo.actualizarGuia).toHaveBeenCalledWith(2, expect.objectContaining({
      estado: ESTADOS.ENTREGADO,
    }));
  });

  it('guarda la ubicación y fecha de cierre cuando el transportista entrega', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ estado: ESTADOS.ENTREGADO, geo: { lat: -12.1, lng: -77.02 } });
    expect(res.status).toBe(200);
    expect(res.body.cierre_lat).toBe(-12.1);
    expect(res.body.cierre_lng).toBe(-77.02);
    expect(res.body.fecha_cierre).toBe(res.body.fecha_actualizacion);
  });

  it('con la fecha de creación actualiza ese registro, no el más reciente del número', async () => {
    const deDiego = guia({ transportista: 'Diego', fecha_creacion: '2026-10-01T14:10:00.000Z', _row: 2 });
    const deJuan = guia({ fecha_creacion: '2026-10-01T14:30:00.000Z', _row: 3 });
    repo.listarGuias.mockResolvedValue([deDiego, deJuan]);
    repo.buscarPorNumero.mockResolvedValue(deJuan);
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({
        estado: ESTADOS.ENTREGADO,
        geo: { lat: -12.1, lng: -77.02 },
        fechaCreacion: '2026-10-01T14:10:00.000Z',
      });
    expect(res.status).toBe(200);
    expect(res.body.transportista).toBe('Diego');
    expect(repo.actualizarGuia).toHaveBeenCalledWith(2, expect.anything());
  });

  it('no marca cierre en un estado intermedio', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ estado: ESTADOS.EN_PROCESO_TRASBORDO, geo: { lat: -12.1, lng: -77.02 } });
    expect(res.status).toBe(200);
    expect(res.body.cierre_lat).toBeUndefined();
  });

  it('un cierre manual del administrador no inventa ubicación de cierre', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ estado: ESTADOS.ENTREGADO, porAdmin: true });
    expect(res.body.cierre_lat).toBeUndefined();
  });

  it('responde 404 si la guía no existe', async () => {
    repo.buscarPorNumero.mockResolvedValue(null);
    const res = await request(app)
      .patch('/guias/NO-EXISTE/estado')
      .send({ estado: ESTADOS.ENTREGADO, porAdmin: true });
    expect(res.status).toBe(404);
  });
});

describe('PATCH /guias/:numeroGuia/numero', () => {
  it('rechaza si el número nuevo ya está activo en otra guía', async () => {
    repo.buscarPorNumero.mockImplementation((numero) => {
      if (numero === 'IPE-2026-000123') return Promise.resolve(guia());
      return Promise.resolve(guia({ numero_guia: 'IPE-2026-000777', _row: 5 }));
    });
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/numero')
      .send({ numeroNuevo: 'IPE-2026-000777' });
    expect(res.status).toBe(409);
    expect(repo.actualizarGuia).not.toHaveBeenCalled();
  });

  it('corrige el número y marca corregido_por_admin', async () => {
    repo.buscarPorNumero.mockImplementation((numero) => {
      if (numero === 'IPE-2026-000123') return Promise.resolve(guia());
      return Promise.resolve(null);
    });
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/numero')
      .send({ numeroNuevo: 'IPE-2026-000777' });
    expect(res.status).toBe(200);
    expect(res.body.numero_guia).toBe('IPE-2026-000777');
    expect(res.body.corregido_por_admin).toBe(true);
  });
});

describe('POST /auth/login', () => {
  const usuario = (overrides = {}) => ({
    nombre: 'Juan Pérez',
    rol: ROLES.TRANSPORTISTA,
    pin: '1234',
    activo: true,
    ...overrides,
  });

  it('exige nombre y pin', async () => {
    const res = await request(app).post('/auth/login').send({ nombre: 'Juan' });
    expect(res.status).toBe(400);
  });

  it('rechaza un pin incorrecto', async () => {
    repo.listarUsuarios.mockResolvedValue([usuario()]);
    const res = await request(app)
      .post('/auth/login')
      .send({ nombre: 'Juan Pérez', pin: '9999' });
    expect(res.status).toBe(401);
  });

  it('rechaza un usuario inactivo', async () => {
    repo.listarUsuarios.mockResolvedValue([usuario({ activo: false })]);
    const res = await request(app)
      .post('/auth/login')
      .send({ nombre: 'Juan Pérez', pin: '1234' });
    expect(res.status).toBe(401);
  });

  it('rechaza un nombre que no existe', async () => {
    repo.listarUsuarios.mockResolvedValue([usuario()]);
    const res = await request(app)
      .post('/auth/login')
      .send({ nombre: 'No Existe', pin: '1234' });
    expect(res.status).toBe(401);
  });

  it('acepta nombre/pin correctos, sin importar mayúsculas/espacios', async () => {
    repo.listarUsuarios.mockResolvedValue([usuario()]);
    const res = await request(app)
      .post('/auth/login')
      .send({ nombre: '  juan pérez  ', pin: '1234' });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ nombre: 'Juan Pérez', rol: ROLES.TRANSPORTISTA });
  });

  it('acepta cuentas del equipo comercial', async () => {
    repo.listarUsuarios.mockResolvedValue([
      usuario({ nombre: 'Lucía Ramos', rol: 'comercial', pin: '5678' }),
    ]);
    const res = await request(app)
      .post('/auth/login')
      .send({ nombre: 'Lucía Ramos', pin: '5678' });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ nombre: 'Lucía Ramos', rol: 'comercial' });
  });
});

describe('POST /auth/registro', () => {
  it('exige nombre y pin', async () => {
    const res = await request(app).post('/auth/registro').send({ nombre: 'Juan' });
    expect(res.status).toBe(400);
    expect(repo.crearUsuario).not.toHaveBeenCalled();
  });

  it('rechaza un nombre ya usado, sin importar mayúsculas/espacios', async () => {
    repo.listarUsuarios.mockResolvedValue([
      { nombre: 'Juan Pérez', rol: ROLES.TRANSPORTISTA, pin: '1234', activo: true },
    ]);
    const res = await request(app)
      .post('/auth/registro')
      .send({ nombre: '  juan pérez  ', pin: '0000' });
    expect(res.status).toBe(409);
    expect(repo.crearUsuario).not.toHaveBeenCalled();
  });

  it('crea el usuario siempre como transportista, nunca administrador', async () => {
    repo.listarUsuarios.mockResolvedValue([]);
    const res = await request(app)
      .post('/auth/registro')
      .send({ nombre: 'Nuevo Chofer', pin: '4321' });
    expect(res.status).toBe(201);
    expect(res.body).toEqual({ nombre: 'Nuevo Chofer', rol: ROLES.TRANSPORTISTA });
    expect(repo.crearUsuario).toHaveBeenCalledWith(
      expect.objectContaining({
        nombre: 'Nuevo Chofer',
        rol: ROLES.TRANSPORTISTA,
        pin: '4321',
        activo: true,
      }),
    );
  });
});

describe('POST /ocr/leer-guia', () => {
  it('rechaza si falta la imagen', async () => {
    const res = await request(app).post('/ocr/leer-guia').send({});
    expect(res.status).toBe(400);
    expect(leerGuiaConIA).not.toHaveBeenCalled();
  });

  it('devuelve los datos extraídos por la IA', async () => {
    leerGuiaConIA.mockResolvedValue({
      numero_guia: 'T028-130133',
      destinatario: 'GENUS SVC S.A.C.',
      destino: 'JR. SAN LORENZO 330, LA VICTORIA, LIMA',
      numero_pedido: '0188173910',
      numero_entrega: '0080216544',
    });
    const res = await request(app)
      .post('/ocr/leer-guia')
      .send({ imagenBase64: 'ZmFrZQ==', mediaType: 'image/png' });
    expect(res.status).toBe(200);
    expect(res.body.numero_guia).toBe('T028-130133');
    expect(leerGuiaConIA).toHaveBeenCalledWith('ZmFrZQ==', 'image/png');
  });

  it('usa image/jpeg por defecto si no se manda mediaType', async () => {
    leerGuiaConIA.mockResolvedValue({
      numero_guia: null,
      destinatario: null,
      destino: null,
      numero_pedido: null,
      numero_entrega: null,
    });
    await request(app).post('/ocr/leer-guia').send({ imagenBase64: 'ZmFrZQ==' });
    expect(leerGuiaConIA).toHaveBeenCalledWith('ZmFrZQ==', 'image/jpeg');
  });

  it('propaga un error de la IA como 500 con el mensaje real', async () => {
    leerGuiaConIA.mockRejectedValue(new Error('falló la IA'));
    const res = await request(app)
      .post('/ocr/leer-guia')
      .send({ imagenBase64: 'ZmFrZQ==' });
    expect(res.status).toBe(500);
    expect(res.body.error).toContain('falló la IA');
  });
  it('con el límite por minuto de la IA responde 429 para reintentar', async () => {
    leerGuiaConIA.mockRejectedValue(Object.assign(new Error('RESOURCE_EXHAUSTED'), { status: 429 }));
    const res = await request(app)
      .post('/ocr/leer-guia')
      .send({ imagenBase64: 'ZmFrZQ==' });
    expect(res.status).toBe(429);
    expect(res.body.error).toMatch(/ocupada/);
  });
});

describe('POST /ocr/numero-guia', () => {
  it('rechaza si falta la imagen', async () => {
    const res = await request(app).post('/ocr/numero-guia').send({ candidatos: ['T1'] });
    expect(res.status).toBe(400);
    expect(leerNumeroGuia).not.toHaveBeenCalled();
  });

  it('pasa a la IA las guías en ruta como candidatos, sin repetidos ni vacíos', async () => {
    leerNumeroGuia.mockResolvedValue({ numero_guia: 'T001-93506' });
    const res = await request(app)
      .post('/ocr/numero-guia')
      .send({
        imagenBase64: 'ZmFrZQ==',
        candidatos: ['T001-93506', ' T001-93507 ', 'T001-93506', '', 5],
      });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ numero_guia: 'T001-93506' });
    expect(leerNumeroGuia).toHaveBeenCalledWith('ZmFrZQ==', 'image/jpeg', [
      'T001-93506',
      'T001-93507',
    ]);
  });

  it('con el límite por minuto de la IA responde 429 para reintentar', async () => {
    leerNumeroGuia.mockRejectedValue(Object.assign(new Error('RESOURCE_EXHAUSTED'), { status: 429 }));
    const res = await request(app).post('/ocr/numero-guia').send({ imagenBase64: 'ZmFrZQ==' });
    expect(res.status).toBe(429);
  });
});

describe('Sucursales y geocerca', () => {
  // Sucursal de ejemplo con un radio de 200 m alrededor de este punto.
  const sucursal = { nombre: 'Sucursal Arequipa', lat: -16.4, lng: -71.53, radio_m: 200, _row: 2 };

  it('lista las sucursales sin campos internos', async () => {
    repo.listarSucursales.mockResolvedValue([sucursal]);
    const res = await request(app).get('/sucursales');
    expect(res.status).toBe(200);
    expect(res.body).toEqual([
      { nombre: 'Sucursal Arequipa', lat: -16.4, lng: -71.53, radio_m: 200 },
    ]);
  });

  it('guarda el perímetro de una sucursal', async () => {
    const res = await request(app)
      .put('/sucursales/Sucursal%20Arequipa')
      .send({ lat: -16.4, lng: -71.53, radioM: 150 });
    expect(res.status).toBe(200);
    expect(repo.guardarSucursal).toHaveBeenCalledWith({
      nombre: 'Sucursal Arequipa',
      lat: -16.4,
      lng: -71.53,
      radio_m: 150,
    });
  });

  it('rechaza un radio fuera de rango', async () => {
    const res = await request(app)
      .put('/sucursales/X')
      .send({ lat: -16.4, lng: -71.53, radioM: 5 });
    expect(res.status).toBe(400);
    expect(repo.guardarSucursal).not.toHaveBeenCalled();
  });

  it('elimina una sucursal existente', async () => {
    repo.listarSucursales.mockResolvedValue([sucursal]);
    const res = await request(app).delete('/sucursales/sucursal%20arequipa');
    expect(res.status).toBe(204);
    expect(repo.eliminarSucursal).toHaveBeenCalledWith(2);
  });

  it('ya no crea traslados entre sucursales', async () => {
    repo.listarSucursales.mockResolvedValue([sucursal]);
    const res = await request(app).post('/guias').send({
      numeroGuia: 'T001-1',
      tipoEntrega: TIPOS_ENTREGA.ENTRE_SUCURSALES,
      origen: 'Almacén Callao',
      destino: 'Sucursal Arequipa',
      transportista: 'Juan Pérez',
      destinatario: 'Sucursal',
      geo: { lat: -12.05, lng: -77.04 },
    });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Ya no se registran traslados/);
    expect(repo.crearGuias).not.toHaveBeenCalled();
  });

  it('acepta la llegada dentro del perímetro', async () => {
    repo.listarSucursales.mockResolvedValue([sucursal]);
    repo.buscarPorNumero.mockResolvedValue(
      guia({ tipo_entrega: TIPOS_ENTREGA.ENTRE_SUCURSALES, destino: 'Sucursal Arequipa', estado: ESTADOS.EN_PROCESO_TRASBORDO }),
    );
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ estado: ESTADOS.RECEPCION_SUCURSAL, geo: { lat: -16.4005, lng: -71.5302 } });
    expect(res.status).toBe(200);
    expect(res.body.estado).toBe(ESTADOS.RECEPCION_SUCURSAL);
  });

  it('rechaza la llegada fuera del perímetro e indica la distancia', async () => {
    repo.listarSucursales.mockResolvedValue([sucursal]);
    repo.buscarPorNumero.mockResolvedValue(
      guia({ tipo_entrega: TIPOS_ENTREGA.ENTRE_SUCURSALES, destino: 'Sucursal Arequipa', estado: ESTADOS.EN_PROCESO_TRASBORDO }),
    );
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ estado: ESTADOS.RECEPCION_SUCURSAL, geo: { lat: -16.41, lng: -71.53 } });
    expect(res.status).toBe(403);
    expect(res.body.error).toMatch(/Estás a 11\d\d m de Sucursal Arequipa/);
    expect(repo.actualizarGuia).not.toHaveBeenCalled();
  });

  it('pide marcar el perímetro si la sucursal destino no lo tiene', async () => {
    repo.listarSucursales.mockResolvedValue([]);
    repo.buscarPorNumero.mockResolvedValue(
      guia({ tipo_entrega: TIPOS_ENTREGA.ENTRE_SUCURSALES, destino: 'Sucursal Cusco', estado: ESTADOS.EN_PROCESO_TRASBORDO }),
    );
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ estado: ESTADOS.RECEPCION_SUCURSAL, geo: { lat: -13.5, lng: -71.9 } });
    expect(res.status).toBe(409);
  });
});

describe('comprobante de agencia', () => {
  const foto = { base64: Buffer.from('jpg').toString('base64'), mediaType: 'image/jpeg' };
  const entrega = { estado: ESTADOS.ENTREGADO, geo: { lat: -12.1, lng: -77.02 }, foto };

  it('al registrar guarda el comprobante leído de la foto, aunque no sea entrega en agencia', async () => {
    repo.listarGuias.mockResolvedValue([]);
    const res = await request(app).post('/guias').send({
      numeroGuia: 'T017-1',
      tipoEntrega: TIPOS_ENTREGA.CLIENTE_FINAL,
      origen: 'Almacén Callao',
      destino: 'Cusco',
      transportista: 'Juan Pérez',
      destinatario: 'WILMAQ E.I.R.L.',
      geo: { lat: -12, lng: -77 },
      comprobante: {
        razonSocial: 'TURISMO INTERNACIONAL PALOMINO S.A.C.',
        ruc: '20515659324',
        monto: '70.00',
        numero: 'F017-0034441',
      },
    });
    expect(res.status).toBe(201);
    expect(res.body).toMatchObject({
      agencia_razon_social: 'TURISMO INTERNACIONAL PALOMINO S.A.C.',
      agencia_ruc: '20515659324',
      agencia_monto: 70,
      agencia_comprobante: 'F017-0034441',
    });
  });

  it('al entregar, la IA lee el comprobante de la foto y se guarda', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    fotos.guardarFoto.mockResolvedValue('drive:foto');
    leerComprobante.mockResolvedValue({
      agencia_razon_social: 'SEÑOR DE LUREN EXPRESS E.I.R.L.',
      agencia_ruc: '20601857457',
      agencia_monto: 13,
    });
    const res = await request(app).patch('/guias/IPE-2026-000123/estado').send(entrega);
    expect(res.status).toBe(200);
    expect(leerComprobante).toHaveBeenCalledWith(foto.base64, 'image/jpeg');
    expect(res.body).toMatchObject({
      agencia_razon_social: 'SEÑOR DE LUREN EXPRESS E.I.R.L.',
      agencia_ruc: '20601857457',
      agencia_monto: 13,
    });
  });

  it('si la app ya lo leyó (Entrega inteligente), no se vuelve a pedir a la IA', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    fotos.guardarFoto.mockResolvedValue('drive:foto');
    leerComprobante.mockClear();
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ ...entrega, comprobante: { razonSocial: 'ITTSA', ruc: '20132272418', monto: 24 } });
    expect(leerComprobante).not.toHaveBeenCalled();
    expect(res.body).toMatchObject({ agencia_razon_social: 'ITTSA', agencia_monto: 24 });
  });

  it('si la IA falla, la entrega se registra igual', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    fotos.guardarFoto.mockResolvedValue('drive:foto');
    leerComprobante.mockRejectedValue(new Error('RESOURCE_EXHAUSTED'));
    const res = await request(app).patch('/guias/IPE-2026-000123/estado').send(entrega);
    expect(res.status).toBe(200);
    expect(res.body.estado).toBe(ESTADOS.ENTREGADO);
    expect(res.body.agencia_ruc).toBeFalsy();
  });
});

describe('foto de la entrega', () => {
  const foto = { base64: Buffer.from('jpg').toString('base64'), mediaType: 'image/jpeg' };

  it('no guarda ninguna foto al asignar la guía', async () => {
    repo.buscarPorNumero.mockResolvedValue(null);
    const res = await request(app).post('/guias').send({
      numeroGuia: 'IPE-1',
      tipoEntrega: TIPOS_ENTREGA.CLIENTE_FINAL,
      origen: 'Almacén Callao',
      destino: 'Av. 1',
      transportista: 'Juan Pérez',
      destinatario: 'María',
      geo: { lat: -12, lng: -77 },
      foto,
    });
    expect(res.status).toBe(201);
    expect(fotos.guardarFoto).not.toHaveBeenCalled();
  });

  it('no guarda la foto en un paso intermedio (inicio de traslado)', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia({ tipo_entrega: TIPOS_ENTREGA.ENTRE_SUCURSALES }));
    await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ estado: ESTADOS.EN_PROCESO_TRASBORDO, geo: { lat: -12.1, lng: -77.02 }, foto });
    expect(fotos.guardarFoto).not.toHaveBeenCalled();
  });

  it('registra la entrega aunque la foto no se pueda guardar, y avisa', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    fotos.guardarFoto.mockRejectedValue(new Error('sin almacenamiento'));
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ estado: ESTADOS.ENTREGADO, geo: { lat: -12.1, lng: -77.02 }, foto });
    expect(res.status).toBe(200);
    expect(repo.actualizarGuia).toHaveBeenCalled();
    expect(res.body.estado).toBe(ESTADOS.ENTREGADO);
    expect(res.body.aviso_foto).toMatch(/sin almacenamiento/);
  });

  it('guarda la foto de la entrega al cliente en la guía', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    fotos.guardarFoto.mockResolvedValue('https://blob/entregas/X.jpg');
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ estado: ESTADOS.ENTREGADO, geo: { lat: -12.1, lng: -77.02 }, foto });
    expect(fotos.guardarFoto).toHaveBeenCalledWith('IPE-2026-000123', foto);
    expect(res.body.foto_entrega_url).toBe('https://blob/entregas/X.jpg');
  });

  it('sirve la foto guardada y da 404 si la guía no tiene foto', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia({ foto_entrega_url: 'https://blob/e.jpg' }));
    fotos.enviarFoto.mockImplementation((_url, res) => res.type('image/jpeg').send('x'));
    const ok = await request(app).get('/guias/IPE-2026-000123/foto');
    expect(ok.status).toBe(200);
    expect(fotos.enviarFoto.mock.calls[0][0]).toBe('https://blob/e.jpg');

    repo.buscarPorNumero.mockResolvedValue(guia());
    const sinFoto = await request(app).get('/guias/IPE-2026-000123/foto');
    expect(sinFoto.status).toBe(404);
  });

  it('informa si el almacenamiento de fotos está conectado', async () => {
    const antes = process.env.BLOB_READ_WRITE_TOKEN;
    delete process.env.BLOB_READ_WRITE_TOKEN;
    expect((await request(app).get('/fotos/estado')).body).toEqual({ configurado: false });
    process.env.BLOB_READ_WRITE_TOKEN = 'x';
    expect((await request(app).get('/fotos/estado')).body).toEqual({ configurado: true });
    if (antes === undefined) delete process.env.BLOB_READ_WRITE_TOKEN;
    else process.env.BLOB_READ_WRITE_TOKEN = antes;
  });
});

describe('POST /guias/:numeroGuia/rechazo', () => {
  it('exige un motivo', async () => {
    const res = await request(app).post('/guias/IPE-2026-000123/rechazo').send({ motivo: ' ' });
    expect(res.status).toBe(400);
    expect(repo.actualizarGuia).not.toHaveBeenCalled();
  });

  it('rechaza la tarea y guarda el motivo', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    const res = await request(app)
      .post('/guias/IPE-2026-000123/rechazo')
      .send({ motivo: 'Cliente ausente', geo: { lat: -12.1, lng: -77.02 } });
    expect(res.status).toBe(200);
    expect(res.body.estado).toBe(ESTADOS.RECHAZADO);
    expect(res.body.motivo_rechazo).toBe('Cliente ausente');
    expect(res.body.geo_lat).toBe(-12.1);
    expect(repo.actualizarGuia.mock.calls[0][1].estado).toBe(ESTADOS.RECHAZADO);
  });

  it('no se puede rechazar una guía ya entregada', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia({ estado: ESTADOS.ENTREGADO }));
    const res = await request(app)
      .post('/guias/IPE-2026-000123/rechazo')
      .send({ motivo: 'Cliente ausente' });
    expect(res.status).toBe(409);
  });

  it('el transportista no puede pasar a rechazado sin motivo por PATCH', async () => {
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ estado: ESTADOS.RECHAZADO, geo: { lat: -12, lng: -77 } });
    expect(res.status).toBe(400);
  });

  it('un número de guía rechazado se puede volver a registrar al momento', async () => {
    repo.listarGuias.mockResolvedValue([
      guia({ estado: ESTADOS.RECHAZADO, fecha_creacion: new Date().toISOString() }),
    ]);
    const res = await request(app).post('/guias').send({
      numeroGuia: 'IPE-2026-000123',
      tipoEntrega: TIPOS_ENTREGA.CLIENTE_FINAL,
      origen: 'Almacén Callao',
      destino: 'Av. 1',
      transportista: 'Juan Pérez',
      destinatario: 'María',
      geo: { lat: -12, lng: -77 },
    });
    expect(res.status).toBe(201);
  });
});

describe('GET /guias con rango de fechas', () => {
  it('devuelve solo las tareas creadas en el rango (desde incluido, hasta excluido)', async () => {
    repo.listarGuias.mockResolvedValue([
      guia({ numero_guia: 'A', fecha_creacion: '2026-09-27T23:59:00.000Z' }),
      guia({ numero_guia: 'B', fecha_creacion: '2026-09-28T05:00:00.000Z' }),
      guia({ numero_guia: 'C', fecha_creacion: '2026-09-29T05:00:00.000Z' }),
    ]);
    const res = await request(app)
      .get('/guias')
      .query({ desde: '2026-09-28T05:00:00.000Z', hasta: '2026-09-29T05:00:00.000Z' });
    expect(res.status).toBe(200);
    expect(res.body.map((g) => g.numero_guia)).toEqual(['B']);
  });

  it('rechaza fechas inválidas', async () => {
    repo.listarGuias.mockResolvedValue([]);
    const res = await request(app).get('/guias').query({ desde: 'ayer' });
    expect(res.status).toBe(400);
  });
});

describe('Tipo de entrega editable', () => {
  it('el transportista cambia el tipo mientras está en ruta', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/tipo')
      .send({ tipoEntrega: TIPOS_ENTREGA.AGENCIA, destino: 'Agencia Shalom Ate' });
    expect(res.status).toBe(200);
    expect(res.body.tipo_entrega).toBe(TIPOS_ENTREGA.AGENCIA);
    expect(res.body.destino).toBe('Agencia Shalom Ate');
    expect(repo.actualizarGuia).toHaveBeenCalledTimes(1);
  });

  it('no deja cambiarlo si ya no está en ruta', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia({ estado: ESTADOS.ENTREGADO }));
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/tipo')
      .send({ tipoEntrega: TIPOS_ENTREGA.AGENCIA });
    expect(res.status).toBe(409);
    expect(repo.actualizarGuia).not.toHaveBeenCalled();
  });

  it('ya no deja cambiar a entre sucursales', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/tipo')
      .send({ tipoEntrega: TIPOS_ENTREGA.ENTRE_SUCURSALES, destino: 'Sucursal Arequipa' });
    expect(res.status).toBe(400);
    expect(repo.actualizarGuia).not.toHaveBeenCalled();
  });

  it('una guía antigua entre sucursales puede pasar a cliente final', async () => {
    repo.buscarPorNumero.mockResolvedValue(
      guia({ tipo_entrega: TIPOS_ENTREGA.ENTRE_SUCURSALES, destino: 'Sucursal Arequipa' }),
    );
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/tipo')
      .send({ tipoEntrega: TIPOS_ENTREGA.CLIENTE_FINAL, destino: 'Av. Ejército 101' });
    expect(res.status).toBe(200);
    expect(res.body.tipo_entrega).toBe(TIPOS_ENTREGA.CLIENTE_FINAL);
    expect(res.body.destino).toBe('Av. Ejército 101');
  });
});

describe('Eliminar una tarea con aprobación del administrador', () => {
  it('el transportista pide eliminar una tarea en ruta', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    const res = await request(app)
      .post('/guias/IPE-2026-000123/solicitud-eliminacion')
      .send({ motivo: 'La registré por error' });
    expect(res.status).toBe(200);
    expect(res.body.eliminacion).toBe('pendiente');
    expect(res.body.motivo_eliminacion).toBe('La registré por error');
    // Todavía no se borra nada.
    expect(repo.eliminarGuia).not.toHaveBeenCalled();
  });

  it('no se puede pedir si ya se entregó', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia({ estado: ESTADOS.ENTREGADO }));
    const res = await request(app)
      .post('/guias/IPE-2026-000123/solicitud-eliminacion')
      .send({ motivo: 'La registré por error' });
    expect(res.status).toBe(409);
  });

  it('el administrador aprueba y se borra de la hoja', async () => {
    const pendiente = guia({ eliminacion: 'pendiente', motivo_eliminacion: 'Error' });
    repo.buscarPorNumero.mockResolvedValue(pendiente);
    const res = await request(app).delete('/guias/IPE-2026-000123');
    expect(res.status).toBe(200);
    expect(repo.eliminarGuia).toHaveBeenCalledWith(pendiente);
  });

  it('una guía entregada no se borra', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia({ estado: ESTADOS.ENTREGADO }));
    const res = await request(app).delete('/guias/IPE-2026-000123');
    expect(res.status).toBe(409);
    expect(repo.eliminarGuia).not.toHaveBeenCalled();
  });

  it('el administrador rechaza el pedido', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia({ eliminacion: 'pendiente' }));
    const res = await request(app)
      .post('/guias/IPE-2026-000123/solicitud-eliminacion/rechazo')
      .send({});
    expect(res.status).toBe(200);
    expect(res.body.eliminacion).toBe('rechazada');
  });

  it('busca el registro exacto si viene la fecha de creación', async () => {
    repo.listarGuias.mockResolvedValue([
      guia({ fecha_creacion: '2026-01-01T00:00:00.000Z', _row: 2 }),
      guia({ fecha_creacion: '2026-01-01T05:00:00.000Z', _row: 3 }),
    ]);
    const res = await request(app)
      .delete('/guias/IPE-2026-000123')
      .query({ fechaCreacion: '2026-01-01T00:00:00.000Z' });
    expect(res.status).toBe(200);
    expect(repo.eliminarGuia.mock.calls[0][0]._row).toBe(2);
  });
});

describe('DELETE /guias/:numeroGuia/foto', () => {
  it('quita la foto de una guía entregada', async () => {
    repo.buscarPorNumero.mockResolvedValue(
      guia({ estado: ESTADOS.ENTREGADO, foto_entrega_url: 'drive:abc' }),
    );
    fotos.eliminarFoto.mockResolvedValue();
    const res = await request(app).delete('/guias/IPE-2026-000123/foto');
    expect(res.status).toBe(200);
    expect(res.body.foto_entrega_url).toBe('');
    expect(fotos.eliminarFoto).toHaveBeenCalledWith('drive:abc');
  });

  it('si el archivo no se puede borrar, igual la quita y avisa', async () => {
    repo.buscarPorNumero.mockResolvedValue(
      guia({ estado: ESTADOS.ENTREGADO, foto_entrega_url: 'drive:abc' }),
    );
    fotos.eliminarFoto.mockRejectedValue(new Error('Acción desconocida.'));
    const res = await request(app).delete('/guias/IPE-2026-000123/foto');
    expect(res.status).toBe(200);
    expect(res.body.foto_entrega_url).toBe('');
    expect(res.body.aviso_foto).toMatch(/no se pudo borrar/);
  });
});

describe('Sucursal por GPS', () => {
  const sanLuis = { nombre: 'Trp San Luis', lat: -12.075, lng: -77.0, radio_m: 150 };

  it('registrada dentro del perímetro: el punto de partida es la sucursal', async () => {
    repo.buscarPorNumero.mockResolvedValue(null);
    repo.listarSucursales.mockResolvedValue([sanLuis]);
    const res = await request(app).post('/guias').send({
      numeroGuia: 'T1',
      tipoEntrega: TIPOS_ENTREGA.CLIENTE_FINAL,
      origen: 'Av. Argentina 4458',
      destino: 'Av. Siempre Viva 742',
      transportista: 'Juan Pérez',
      destinatario: 'María Torres',
      geo: { lat: -12.0752, lng: -77.0003 },
    });
    expect(res.status).toBe(201);
    expect(res.body.origen).toBe('Trp San Luis');
  });

  it('registrada fuera del perímetro: queda el punto de partida de la hoja', async () => {
    repo.buscarPorNumero.mockResolvedValue(null);
    repo.listarSucursales.mockResolvedValue([sanLuis]);
    const res = await request(app).post('/guias').send({
      numeroGuia: 'T1',
      tipoEntrega: TIPOS_ENTREGA.CLIENTE_FINAL,
      origen: 'Av. Argentina 4458',
      destino: 'Av. Siempre Viva 742',
      transportista: 'Juan Pérez',
      destinatario: 'María Torres',
      geo: { lat: -12.05, lng: -77.04 },
    });
    expect(res.body.origen).toBe('Av. Argentina 4458');
  });

  it('entregada dentro del perímetro: queda entregada en la sucursal', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    repo.listarSucursales.mockResolvedValue([sanLuis]);
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ estado: ESTADOS.ENTREGADO, geo: { lat: -12.0751, lng: -77.0001 } });
    expect(res.status).toBe(200);
    expect(res.body.destino).toBe('Trp San Luis');
  });

  it('entregada fuera: el destino no cambia', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    repo.listarSucursales.mockResolvedValue([sanLuis]);
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ estado: ESTADOS.ENTREGADO, geo: { lat: -12.05, lng: -77.04 } });
    expect(res.body.destino).toBe('Av. Siempre Viva 742');
  });
});

describe('Transbordo entre transportistas', () => {
  const usuarios = [
    { nombre: 'Juan Pérez', rol: ROLES.TRANSPORTISTA, pin: '1111', activo: true },
    { nombre: 'Ana Díaz', rol: ROLES.TRANSPORTISTA, pin: '2222', activo: true },
    { nombre: 'Luis Baja', rol: ROLES.TRANSPORTISTA, pin: '3333', activo: false },
    { nombre: 'Admin', rol: ROLES.ADMINISTRADOR, pin: '9999', activo: true },
  ];

  it('lista solo transportistas activos y sin PIN', async () => {
    repo.listarUsuarios.mockResolvedValue(usuarios);
    const res = await request(app).get('/transportistas');
    expect(res.status).toBe(200);
    expect(res.body).toEqual([{ nombre: 'Ana Díaz' }, { nombre: 'Juan Pérez' }]);
  });

  it('pasa la tarea a otro: queda pendiente y sigue siendo de quien la envía', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    repo.listarUsuarios.mockResolvedValue(usuarios);
    const res = await request(app)
      .post('/guias/IPE-2026-000123/transbordo')
      .send({ de: 'Juan Pérez', a: 'ana díaz' });
    expect(res.status).toBe(200);
    expect(res.body.transbordo_estado).toBe(TRANSBORDO.PENDIENTE);
    expect(res.body.transbordo_a).toBe('Ana Díaz');
    expect(res.body.transportista).toBe('Juan Pérez');
  });

  it('no acepta inactivos, a uno mismo ni tareas que no están en ruta', async () => {
    repo.listarUsuarios.mockResolvedValue(usuarios);
    repo.buscarPorNumero.mockResolvedValue(guia());
    const inactivo = await request(app)
      .post('/guias/IPE-2026-000123/transbordo')
      .send({ de: 'Juan Pérez', a: 'Luis Baja' });
    expect(inactivo.status).toBe(400);
    const mismo = await request(app)
      .post('/guias/IPE-2026-000123/transbordo')
      .send({ de: 'Juan Pérez', a: 'Juan Pérez' });
    expect(mismo.status).toBe(400);
    repo.buscarPorNumero.mockResolvedValue(guia({ estado: ESTADOS.ENTREGADO }));
    const cerrada = await request(app)
      .post('/guias/IPE-2026-000123/transbordo')
      .send({ de: 'Juan Pérez', a: 'Ana Díaz' });
    expect(cerrada.status).toBe(409);
    expect(repo.actualizarGuia).not.toHaveBeenCalled();
  });

  it('el que recibe la ve en su lista mientras está pendiente', async () => {
    repo.listarGuias.mockResolvedValue([
      guia({ transbordo_estado: TRANSBORDO.PENDIENTE, transbordo_a: 'Ana Díaz' }),
      guia({ numero_guia: 'OTRA', transportista: 'Pedro' }),
    ]);
    const res = await request(app).get('/guias/transportista/Ana%20D%C3%ADaz');
    expect(res.body.map((g) => g.numero_guia)).toEqual(['IPE-2026-000123']);
  });

  it('al aceptar, la tarea pasa a quien la recibe y guarda de quién vino', async () => {
    repo.buscarPorNumero.mockResolvedValue(
      guia({
        transbordo_estado: TRANSBORDO.PENDIENTE,
        transbordo_a: 'Ana Díaz',
        despacho_corte: 'DC-1',
      }),
    );
    const res = await request(app)
      .post('/guias/IPE-2026-000123/transbordo/respuesta')
      .send({ quien: 'Ana Díaz', acepta: true });
    expect(res.status).toBe(200);
    expect(res.body.transportista).toBe('Ana Díaz');
    // Sale del Despacho Corte de quien la envió.
    expect(res.body.despacho_corte).toBe('');
    expect(res.body.transbordo_de).toBe('Juan Pérez');
    expect(res.body.transbordo_estado).toBe(TRANSBORDO.ACEPTADO);
    expect(res.body.origen).toBe('Almacén Callao');
  });

  it('al rechazar, la tarea sigue con quien la envió', async () => {
    repo.buscarPorNumero.mockResolvedValue(
      guia({ transbordo_estado: TRANSBORDO.PENDIENTE, transbordo_a: 'Ana Díaz' }),
    );
    const res = await request(app)
      .post('/guias/IPE-2026-000123/transbordo/respuesta')
      .send({ quien: 'Ana Díaz', acepta: false });
    expect(res.body.transportista).toBe('Juan Pérez');
    expect(res.body.transbordo_estado).toBe(TRANSBORDO.RECHAZADO);
    expect(res.body.transbordo_a).toBe('Ana Díaz');
  });

  it('solo responde a quien va dirigido', async () => {
    repo.buscarPorNumero.mockResolvedValue(
      guia({ transbordo_estado: TRANSBORDO.PENDIENTE, transbordo_a: 'Ana Díaz' }),
    );
    const res = await request(app)
      .post('/guias/IPE-2026-000123/transbordo/respuesta')
      .send({ quien: 'Pedro', acepta: true });
    expect(res.status).toBe(403);
  });

  it('quien lo envió puede cancelarlo', async () => {
    repo.buscarPorNumero.mockResolvedValue(
      guia({ transbordo_estado: TRANSBORDO.PENDIENTE, transbordo_a: 'Ana Díaz' }),
    );
    const res = await request(app).delete('/guias/IPE-2026-000123/transbordo');
    expect(res.status).toBe(200);
    expect(res.body.transbordo_estado).toBe('');
    expect(res.body.transbordo_a).toBe('');
  });

  it('si la entrega quien la envió, el transbordo pendiente se anula', async () => {
    repo.buscarPorNumero.mockResolvedValue(
      guia({ transbordo_estado: TRANSBORDO.PENDIENTE, transbordo_a: 'Ana Díaz' }),
    );
    repo.listarSucursales.mockResolvedValue([]);
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ estado: ESTADOS.ENTREGADO, geo: { lat: -12.05, lng: -77.04 } });
    expect(res.body.transbordo_estado).toBe('');
    expect(res.body.transportista).toBe('Juan Pérez');
  });
});

