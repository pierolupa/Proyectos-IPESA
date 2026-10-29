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

// Las rutas exigen sesión (ver auth.js). Por defecto las pruebas llaman
// como administrador; `sinSesion()` y `como(sesion)` prueban lo demás.
process.env.AUTH_SECRET = 'clave-solo-para-pruebas-0123456789abcdef';
const supertest = require('supertest');
const auth = require('./auth');
const repo = require('./sheetsRepository');
const { leerGuiaConIA, leerNumeroGuia, leerComprobante } = require('./ocrAgente');
const fotos = require('./fotos');
const { ESTADOS, TIPOS_ENTREGA, ROLES, TRANSBORDO } = require('./columns');

const app = require('./app');

function conToken(token) {
  const agente = supertest(app);
  const metodos = {};
  for (const m of ['get', 'post', 'put', 'patch', 'delete']) {
    metodos[m] = (...args) => {
      const pedido = agente[m](...args);
      return token ? pedido.set('Authorization', `Bearer ${token}`) : pedido;
    };
  }
  return metodos;
}
const como = (sesion) => conToken(auth.crearToken(sesion).token);
const sinSesion = () => conToken(null);
const TOKEN_ADMIN = auth.crearToken({ nombre: 'Admin Pruebas', rol: ROLES.ADMINISTRADOR }).token;
const request = () => conToken(TOKEN_ADMIN);

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
  auth.olvidarFallos();
  repo.listarGuias.mockResolvedValue([]);
  repo.listarSucursales.mockResolvedValue([]);
  repo.infoArchivo.mockResolvedValue({ pestanas: [], ultima: null });
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

  // Hora fija: 2026-10-02 18:00 en Perú (23:00 UTC).
  const ahoraPeru = Date.parse('2026-10-02T23:00:00.000Z');
  const haceMin = (min) => new Date(ahoraPeru - min * 60000).toISOString();

  it('el mismo transportista no registra otra vez la misma guía antes de 20 min', async () => {
    jest.spyOn(Date, 'now').mockReturnValue(ahoraPeru);
    // Hoy a las 17:45 de Perú: hace 15 minutos.
    repo.listarGuias.mockResolvedValue([
      guia({ numero_guia: payload.numeroGuia, transportista: 'juan pérez ', fecha_creacion: haceMin(15) }),
    ]);
    const res = await request(app).post('/guias').send(payload);
    Date.now.mockRestore();
    expect(res.status).toBe(409);
    expect(res.body.error).toBe(
      `Ya registraste la guía ${payload.numeroGuia} a las 17:45. `
      + 'Podrás volver a registrarla desde las 18:05 (en 5 min).',
    );
    expect(repo.crearGuias).not.toHaveBeenCalled();
    // La comprobación lee la hoja sin caché.
    expect(repo.listarGuias).toHaveBeenCalledWith({ fresco: true });
  });

  it('el mismo transportista la puede registrar otra vez pasados 20 min', async () => {
    jest.spyOn(Date, 'now').mockReturnValue(ahoraPeru);
    // El mismo día, hace justo 20 minutos.
    repo.listarGuias.mockResolvedValue([
      guia({ numero_guia: payload.numeroGuia, fecha_creacion: haceMin(20) }),
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
      expect(g.geo_lat).toBe(-12.05); // donde se recogió
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
    // El punto donde se recogió no se pierde.
    expect(res.body.geo_lat).toBe(-12.05);
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
    expect(res.body).toMatchObject({ nombre: 'Juan Pérez', rol: ROLES.TRANSPORTISTA });
    expect(auth.leerToken(res.body.token)).toEqual({
      nombre: 'Juan Pérez',
      rol: ROLES.TRANSPORTISTA,
    });
    expect(Date.parse(res.body.expira)).toBeGreaterThan(Date.now());
  });

  it('acepta cuentas del equipo comercial', async () => {
    repo.listarUsuarios.mockResolvedValue([
      usuario({ nombre: 'Lucía Ramos', rol: 'comercial', pin: '5678' }),
    ]);
    const res = await request(app)
      .post('/auth/login')
      .send({ nombre: 'Lucía Ramos', pin: '5678' });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ nombre: 'Lucía Ramos', rol: 'comercial' });
  });

  it('tras 5 PIN equivocados bloquea ese nombre, aunque luego acierte', async () => {
    repo.listarUsuarios.mockResolvedValue([usuario()]);
    for (let i = 0; i < auth.MAX_FALLOS; i++) {
      const res = await sinSesion()
        .post('/auth/login')
        .send({ nombre: 'Juan Pérez', pin: '0000' });
      expect(res.status).toBe(401);
    }
    const bloqueado = await sinSesion()
      .post('/auth/login')
      .send({ nombre: 'juan pérez', pin: '1234' });
    expect(bloqueado.status).toBe(429);
  });

  it('un acierto borra los fallos anteriores', async () => {
    repo.listarUsuarios.mockResolvedValue([usuario()]);
    for (let i = 0; i < auth.MAX_FALLOS - 1; i++) {
      await sinSesion().post('/auth/login').send({ nombre: 'Juan Pérez', pin: '0000' });
    }
    await sinSesion().post('/auth/login').send({ nombre: 'Juan Pérez', pin: '1234' });
    const res = await sinSesion()
      .post('/auth/login')
      .send({ nombre: 'Juan Pérez', pin: '0000' });
    expect(res.status).toBe(401);
  });
});

describe('Sesiones y permisos', () => {
  const transportista = { nombre: 'Juan Pérez', rol: ROLES.TRANSPORTISTA };
  const comercial = { nombre: 'Lucía Ramos', rol: ROLES.COMERCIAL };

  it('sin token no deja consultar ni cambiar nada', async () => {
    expect((await sinSesion().get('/guias')).status).toBe(401);
    expect((await sinSesion().get('/sucursales')).status).toBe(401);
    expect((await sinSesion().post('/ocr/leer-guia').send({})).status).toBe(401);
    expect((await sinSesion().delete('/guias/IPE-1')).status).toBe(401);
    expect(repo.listarGuias).not.toHaveBeenCalled();
  });

  it('/health no pide sesión', async () => {
    expect((await sinSesion().get('/health')).status).toBe(200);
  });

  it('rechaza un token alterado o vencido', async () => {
    const { token } = auth.crearToken(transportista);
    const [cuerpo] = token.split('.');
    const otroCuerpo = Buffer.from(
      JSON.stringify({ n: 'Juan Pérez', r: ROLES.ADMINISTRADOR, exp: Date.now() + 60000 }),
    ).toString('base64url');
    const alterado = `${otroCuerpo}.${token.split('.')[1]}`;
    expect(cuerpo).not.toBe(otroCuerpo);
    expect((await conToken(alterado).get('/guias')).status).toBe(401);

    const vencido = auth.crearToken(
      transportista,
      Date.now() - auth.DURACION_SESION_MS - 1000,
    ).token;
    const res = await conToken(vencido).get('/guias');
    expect(res.status).toBe(401);
    expect(res.body.error).toMatch(/sesión venció/);
  });

  it('el token del login sirve para las demás rutas', async () => {
    repo.listarUsuarios.mockResolvedValue([
      { nombre: 'Juan Pérez', rol: ROLES.TRANSPORTISTA, pin: '1234', activo: true },
    ]);
    const login = await sinSesion()
      .post('/auth/login')
      .send({ nombre: 'Juan Pérez', pin: '1234' });
    const res = await conToken(login.body.token).get('/guias');
    expect(res.status).toBe(200);
  });

  it('el comercial consulta pero no cambia nada', async () => {
    expect((await como(comercial).get('/guias')).status).toBe(200);
    const res = await como(comercial).post('/guias').send({});
    expect(res.status).toBe(403);
    expect(repo.crearGuia).not.toHaveBeenCalled();
  });

  it('sucursales, archivo y regularización son solo del administrador', async () => {
    const t = () => como(transportista);
    expect((await t().put('/sucursales/Ate').send({ lat: 1, lng: 1, radioM: 100 })).status).toBe(403);
    expect((await t().delete('/sucursales/Ate')).status).toBe(403);
    expect((await t().get('/archivo')).status).toBe(403);
    expect((await t().post('/archivo').send({})).status).toBe(403);
    expect((await t().post('/guias/regularizar').send({})).status).toBe(403);
    expect(repo.guardarSucursal).not.toHaveBeenCalled();
    expect(repo.archivarGuias).not.toHaveBeenCalled();
  });

  it('un transportista solo ve sus propias tareas', async () => {
    const ajena = await como(transportista).get('/guias/transportista/Pedro%20Soto');
    expect(ajena.status).toBe(403);
    const propia = await como(transportista).get('/guias/transportista/juan%20p%C3%A9rez');
    expect(propia.status).toBe(200);
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
      // Con comprobante, la IA la marca como entrega en agencia.
      tipo_entrega: TIPOS_ENTREGA.AGENCIA,
    });
  });

  it('sin tipo ni comprobante, la guía nueva es de cliente final', async () => {
    repo.listarGuias.mockResolvedValue([]);
    const res = await request(app).post('/guias').send({
      numeroGuia: 'T017-2',
      origen: 'Almacén Callao',
      destino: 'Lima',
      transportista: 'Juan Pérez',
      destinatario: 'Cliente',
      geo: { lat: -12, lng: -77 },
    });
    expect(res.status).toBe(201);
    expect(res.body.tipo_entrega).toBe(TIPOS_ENTREGA.CLIENTE_FINAL);
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
    // Era de cliente final: al ver el comprobante pasa a agencia, finalizada.
    expect(res.body.tipo_entrega).toBe(TIPOS_ENTREGA.AGENCIA);
    expect(res.body.estado).toBe(ESTADOS.FINALIZADO);
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
    // Sin comprobante sigue como cliente final, entregada.
    expect(res.body.estado).toBe(ESTADOS.ENTREGADO);
    expect(res.body.tipo_entrega).toBe(TIPOS_ENTREGA.CLIENTE_FINAL);
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

  it('vigentes: las abiertas siempre y las cerradas solo si cambiaron desde ese momento', async () => {
    const viejo = '2026-08-01T15:00:00.000Z';
    repo.listarGuias.mockResolvedValue([
      // Abierta de hace dos meses: se sigue hasta cerrarla.
      guia({ numero_guia: 'A', fecha_creacion: viejo, fecha_actualizacion: viejo }),
      // Cerrada hace dos meses: ya no.
      guia({
        numero_guia: 'B',
        estado: ESTADOS.ENTREGADO,
        fecha_creacion: viejo,
        fecha_actualizacion: viejo,
      }),
      // Registrada antes, entregada hoy: sí (cambió).
      guia({
        numero_guia: 'C',
        estado: ESTADOS.ENTREGADO,
        fecha_creacion: viejo,
        fecha_actualizacion: '2026-10-11T14:00:00.000Z',
      }),
      guia({
        numero_guia: 'D',
        estado: ESTADOS.RECHAZADO,
        fecha_creacion: '2026-10-11T13:00:00.000Z',
        fecha_actualizacion: '2026-10-11T13:30:00.000Z',
      }),
    ]);
    const res = await request(app)
      .get('/guias')
      .query({ vigentes: '2026-10-11T05:00:00.000Z' });
    expect(res.status).toBe(200);
    expect(res.body.map((g) => g.numero_guia)).toEqual(['A', 'C', 'D']);

    const mala = await request(app).get('/guias').query({ vigentes: 'hoy' });
    expect(mala.status).toBe(400);
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
        custodia_desde: '2026-10-19T23:00:00.000Z',
      }),
    );
    const res = await request(app)
      .post('/guias/IPE-2026-000123/transbordo/respuesta')
      .send({ quien: 'Ana Díaz', acepta: true });
    expect(res.status).toBe(200);
    expect(res.body.transportista).toBe('Ana Díaz');
    // Sale del Despacho Corte y de la custodia de quien la envió.
    expect(res.body.despacho_corte).toBe('');
    expect(res.body.custodia_desde).toBe('');
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

  const archivo = { pestanas: ['Guías 2026'], ultima: Date.parse('2026-09-30T23:00:00.000Z') };

  it('con fechas que pueden estar archivadas, suma las guías del archivo', async () => {
    repo.infoArchivo.mockResolvedValue(archivo);
    repo.listarGuias.mockResolvedValue([
      guia({ numero_guia: 'NUEVA', fecha_creacion: '2026-10-05T10:00:00.000Z' }),
    ]);
    repo.listarGuiasArchivadas.mockResolvedValue([
      { ...guia({ numero_guia: 'VIEJA', fecha_creacion: '2026-03-05T10:00:00.000Z' }), _archivo: 'Guías 2026' },
    ]);
    const res = await request(app)
      .get('/guias')
      .query({ desde: '2026-03-01T00:00:00.000Z', hasta: '2026-04-01T00:00:00.000Z' });
    expect(res.status).toBe(200);
    expect(res.body.map((g) => g.numero_guia)).toEqual(['VIEJA']);
    expect(res.body[0]._archivo).toBeUndefined();
    expect(repo.listarGuiasArchivadas).toHaveBeenCalledWith(['Guías 2026'], {
      desde: Date.parse('2026-03-01T00:00:00.000Z'),
      hasta: Date.parse('2026-04-01T00:00:00.000Z'),
    });
  });

  it('sin archivo, o si la consulta empieza después de lo archivado, no lo lee', async () => {
    repo.listarGuias.mockResolvedValue([
      guia({ numero_guia: 'NUEVA', fecha_creacion: '2026-10-05T10:00:00.000Z' }),
    ]);
    await request(app).get('/guias').query({ desde: '2026-09-01T00:00:00.000Z' });
    expect(repo.listarGuiasArchivadas).not.toHaveBeenCalled();
    repo.infoArchivo.mockResolvedValue(archivo);
    await request(app).get('/guias').query({ desde: '2026-10-01T00:00:00.000Z' });
    await request(app).get('/guias').query({ vigentes: '2026-10-12T01:00:00.000Z' });
    expect(repo.listarGuiasArchivadas).not.toHaveBeenCalled();
  });

  it('la carga del panel (vigentes) incluye lo archivado del último mes', async () => {
    repo.infoArchivo.mockResolvedValue(archivo);
    repo.listarGuias.mockResolvedValue([
      guia({ numero_guia: 'ABIERTA', estado: ESTADOS.EN_RUTA, fecha_creacion: '2026-10-11T10:00:00.000Z' }),
    ]);
    repo.listarGuiasArchivadas.mockResolvedValue([
      {
        ...guia({
          numero_guia: 'SEPTIEMBRE',
          estado: ESTADOS.ENTREGADO,
          fecha_creacion: '2026-09-29T10:00:00.000Z',
          fecha_actualizacion: '2026-09-29T15:00:00.000Z',
        }),
        _archivo: 'Guías 2026',
      },
    ]);
    const res = await request(app).get('/guias').query({ vigentes: '2026-09-07T05:00:00.000Z' });
    expect(res.body.map((g) => g.numero_guia).sort()).toEqual(['ABIERTA', 'SEPTIEMBRE']);
  });

  it('corregir una guía archivada la busca en el archivo y la escribe en su pestaña', async () => {
    repo.infoArchivo.mockResolvedValue(archivo);
    repo.listarGuias.mockResolvedValue([]);
    repo.buscarPorNumero.mockResolvedValue(null);
    repo.listarGuiasArchivadas.mockResolvedValue([
      {
        ...guia({
          numero_guia: 'IPE-2026-000123',
          estado: ESTADOS.ENTREGADO,
          fecha_creacion: '2026-03-05T10:00:00.000Z',
        }),
        _row: 7,
        _archivo: 'Guías 2026',
      },
    ]);
    const res = await request(app)
      .patch('/guias/IPE-2026-000123/numero')
      .send({ numeroNuevo: 'IPE-2026-000124', fechaCreacion: '2026-03-05T10:00:00.000Z' });
    expect(res.status).toBe(200);
    expect(repo.actualizarGuia).toHaveBeenCalledWith(
      7,
      expect.objectContaining({ _archivo: 'Guías 2026' }),
    );
  });
});

describe('archivo desde la app', () => {
  const plan = { ejecutar: false, total: 80, porPestana: { 'Guías 2026': 80 } };
  const admin = { nombre: 'Piero', rol: ROLES.ADMINISTRADOR, pin: '1234', activo: true };

  it('simula sin mover nada; por defecto hasta el 1 del mes en curso', async () => {
    repo.archivarGuias.mockResolvedValue(plan);
    const res = await request(app).get('/archivo');
    expect(res.status).toBe(200);
    expect(res.body.total).toBe(80);
    expect(res.body.hasta).toMatch(/^\d{4}-\d{2}-01$/);
    expect(repo.archivarGuias).toHaveBeenCalledWith(res.body.hasta, { ejecutar: false });
  });

  it('no deja archivar el mes en curso ni fechas que no son día 1', async () => {
    expect((await request(app).get('/archivo').query({ hasta: '2999-01-01' })).status).toBe(400);
    expect((await request(app).get('/archivo').query({ hasta: '2026-09-15' })).status).toBe(400);
    expect(repo.archivarGuias).not.toHaveBeenCalled();
  });

  it('archivar de verdad pide el PIN de un administrador', async () => {
    repo.listarUsuarios.mockResolvedValue([
      admin,
      { nombre: 'Oscar Aspur', rol: ROLES.TRANSPORTISTA, pin: '9999', activo: true },
    ]);
    const sinPin = await request(app).post('/archivo').send({ nombre: 'Piero' });
    expect(sinPin.status).toBe(400);
    const malo = await request(app).post('/archivo').send({ nombre: 'Piero', pin: '0000', hasta: '2026-10-01' });
    expect(malo.status).toBe(403);
    const transportista = await request(app)
      .post('/archivo')
      .send({ nombre: 'Oscar Aspur', pin: '9999', hasta: '2026-10-01' });
    expect(transportista.status).toBe(403);
    expect(repo.archivarGuias).not.toHaveBeenCalled();

    repo.archivarGuias.mockResolvedValue({ ...plan, ejecutar: true });
    const ok = await request(app).post('/archivo').send({ nombre: 'piero', pin: '1234', hasta: '2026-10-01' });
    expect(ok.status).toBe(200);
    expect(ok.body.total).toBe(80);
    expect(repo.archivarGuias).toHaveBeenCalledWith('2026-10-01', { ejecutar: true });
  });
});

describe('archivo automático (cron)', () => {
  const plan = { ejecutar: false, total: 80, porPestana: { 'Guías 2026': 80 } };

  afterEach(() => {
    jest.useRealTimers();
    delete process.env.CRON_SECRET;
  });

  it('de madrugada archiva lo anterior al mes en curso', async () => {
    jest.useFakeTimers({ now: new Date('2026-10-13T08:10:00Z'), doNotFake: ['nextTick', 'setImmediate'] });
    repo.archivarGuias
      .mockResolvedValueOnce(plan)
      .mockResolvedValueOnce({ ...plan, ejecutar: true });
    const res = await request(app).get('/cron/archivo');
    expect(res.status).toBe(200);
    expect(repo.archivarGuias).toHaveBeenNthCalledWith(1, '2026-10-01', { ejecutar: false });
    expect(repo.archivarGuias).toHaveBeenNthCalledWith(2, '2026-10-01', { ejecutar: true });
  });

  it('si no hay nada que archivar, no escribe', async () => {
    jest.useFakeTimers({ now: new Date('2026-10-14T08:10:00Z'), doNotFake: ['nextTick', 'setImmediate'] });
    repo.archivarGuias.mockResolvedValue({ ejecutar: false, total: 0, porPestana: {} });
    const res = await request(app).get('/cron/archivo');
    expect(res.status).toBe(200);
    expect(repo.archivarGuias).toHaveBeenCalledTimes(1);
  });

  it('de día no corre, y con CRON_SECRET exige el token', async () => {
    jest.useFakeTimers({ now: new Date('2026-10-13T15:00:00Z'), doNotFake: ['nextTick', 'setImmediate'] });
    expect((await request(app).get('/cron/archivo')).status).toBe(403);
    process.env.CRON_SECRET = 'secreto-de-prueba';
    expect((await request(app).get('/cron/archivo')).status).toBe(401);
    repo.archivarGuias.mockResolvedValue({ ejecutar: false, total: 0, porPestana: {} });
    const ok = await request(app)
      .get('/cron/archivo')
      .set('Authorization', 'Bearer secreto-de-prueba');
    expect(ok.status).toBe(200);
  });
});

describe('GET /despachos (hoja Despachos Ate)', () => {
  const despacho = (numero, fecha) => ({
    numero_guia: numero,
    cliente: 'IPESA S.A.C.',
    fecha,
    numero_pedido: '4900109327',
    numero_entrega: '81115782',
  });

  it('devuelve solo las que no están en la base de la app', async () => {
    repo.listarDespachos.mockResolvedValue([
      despacho('T001-1', '2026-10-10T15:00:00.000Z'),
      despacho('T001-2', '2026-10-10T16:00:00.000Z'),
    ]);
    repo.listarGuias.mockResolvedValue([guia({ numero_guia: 'T001-1' })]);
    const res = await request(app)
      .get('/despachos')
      .query({ desde: '2026-10-10T05:00:00.000Z', hasta: '2026-10-11T05:00:00.000Z' });
    expect(res.status).toBe(200);
    expect(res.body).toEqual([despacho('T001-2', '2026-10-10T16:00:00.000Z')]);
    expect(repo.listarDespachos).toHaveBeenCalledWith({
      desde: Date.parse('2026-10-10T05:00:00.000Z'),
      hasta: Date.parse('2026-10-11T05:00:00.000Z'),
    });
  });

  it('tampoco repite las que están archivadas', async () => {
    repo.infoArchivo.mockResolvedValue({ pestanas: ['Guías 2026'], ultima: Date.parse('2026-09-30T23:00:00Z') });
    repo.listarDespachos.mockResolvedValue([despacho('T001-9', '2026-09-29T15:00:00.000Z')]);
    repo.listarGuiasArchivadas.mockResolvedValue([guia({ numero_guia: 'T001-9' })]);
    const res = await request(app).get('/despachos').query({ desde: '2026-09-28T05:00:00.000Z' });
    expect(res.body).toEqual([]);
  });

  it('sin fecha de inicio responde 400; si la hoja no se puede leer, 503', async () => {
    expect((await request(app).get('/despachos')).status).toBe(400);
    repo.listarDespachos.mockRejectedValue(new Error('The caller does not have permission'));
    const res = await request(app).get('/despachos').query({ desde: '2026-10-10T05:00:00.000Z' });
    expect(res.status).toBe(503);
    expect(res.body.error).toMatch(/Despachos Ate/);
  });
});

describe('POST /guias/regularizar (administrador)', () => {
  const datos = {
    transportista: 'Juan Pérez',
    numeroGuia: 'T001-99001',
    origen: 'Almacén Callao',
    destino: 'Av. Principal 123',
    destinatario: 'Cliente X',
    numeroPedido: '0188170001',
    numeroEntrega: '0080210000',
    foto: { base64: 'AAAA', mediaType: 'image/jpeg' },
    comprobante: null,
  };

  it('pide la foto de la entrega', async () => {
    const res = await request(app)
      .post('/guias/regularizar')
      .send({ ...datos, foto: undefined });
    expect(res.status).toBe(400);
    expect(repo.crearGuias).not.toHaveBeenCalled();
  });

  it('crea la guía ya entregada, a nombre del transportista, sin GPS', async () => {
    const res = await request(app).post('/guias/regularizar').send(datos);
    expect(res.status).toBe(201);
    expect(res.body.numeroGuia).toBe('T001-99001');
    expect(repo.crearGuias).toHaveBeenCalledWith([
      expect.objectContaining({
        numero_guia: 'T001-99001',
        estado: ESTADOS.ENTREGADO,
        transportista: 'Juan Pérez',
        corregido_por_admin: true,
        numero_pedido: '0188170001',
      }),
    ]);
    const [guia] = repo.crearGuias.mock.calls[0][0];
    expect(guia.geo_lat).toBeUndefined();
    expect(guia.fecha_cierre).toBeTruthy();
  });

  it('no aplica la regla de un registro por día ni se bloquea por la guía ya registrada', async () => {
    repo.listarGuias.mockResolvedValue([
      guia({ numero_guia: 'T001-99001', transportista: 'Juan Pérez', fecha_creacion: new Date().toISOString() }),
    ]);
    const res = await request(app).post('/guias/regularizar').send(datos);
    expect(res.status).toBe(201);
  });

  it('con un comprobante de agencia queda finalizada en agencia', async () => {
    const res = await request(app)
      .post('/guias/regularizar')
      .send({ ...datos, comprobante: { razonSocial: 'Olva', ruc: '20123456789', monto: 45 } });
    expect(res.status).toBe(201);
    const [guia] = repo.crearGuias.mock.calls[0][0];
    expect(guia.estado).toBe(ESTADOS.FINALIZADO);
    expect(guia.tipo_entrega).toBe(TIPOS_ENTREGA.AGENCIA);
  });
});

describe('errores de Google', () => {
  it('un 401 de Google no se confunde con una sesión vencida', async () => {
    repo.listarGuias.mockRejectedValue(
      Object.assign(new Error('Request had invalid authentication credentials.'), {
        status: 401,
        response: { status: 401 },
      }),
    );
    const res = await request(app).get('/guias');
    expect(res.status).toBe(502);
    expect(res.body.error).toMatch(/Google respondió con un error: Request had invalid/);
  });

  it('los errores propios conservan su código', async () => {
    repo.listarGuias.mockRejectedValue(
      Object.assign(new Error('La hoja cambió; inténtalo de nuevo.'), { status: 409 }),
    );
    const res = await request(app).get('/guias');
    expect(res.status).toBe(409);
  });
});

describe('Custodia', () => {
  const transportista = { nombre: 'Juan Pérez', rol: ROLES.TRANSPORTISTA };

  beforeEach(() => {
    repo.actualizarGuia.mockResolvedValue();
  });

  it('el transportista deja su guía en custodia (sigue en ruta)', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    const res = await como(transportista).post('/guias/IPE-2026-000123/custodia').send({});
    expect(res.status).toBe(200);
    expect(res.body.estado).toBe(ESTADOS.EN_RUTA);
    expect(Date.parse(res.body.custodia_desde)).not.toBeNaN();
    const [fila, guardada] = repo.actualizarGuia.mock.calls[0];
    expect(fila).toBe(2);
    expect(guardada.custodia_desde).toBe(res.body.custodia_desde);
  });

  it('se puede quitar si se marcó por error', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia({ custodia_desde: '2026-10-19T23:00:00.000Z' }));
    const res = await como(transportista).delete('/guias/IPE-2026-000123/custodia');
    expect(res.status).toBe(200);
    expect(res.body.custodia_desde).toBe('');
  });

  it('otro transportista no puede tocar la guía', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    const res = await como({ nombre: 'Pedro Soto', rol: ROLES.TRANSPORTISTA })
      .post('/guias/IPE-2026-000123/custodia')
      .send({});
    expect(res.status).toBe(403);
    expect(repo.actualizarGuia).not.toHaveBeenCalled();
  });

  it('el administrador sí puede', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    const res = await request(app).post('/guias/IPE-2026-000123/custodia').send({});
    expect(res.status).toBe(200);
  });

  it('solo una guía en ruta', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia({ estado: ESTADOS.ENTREGADO }));
    const res = await como(transportista).post('/guias/IPE-2026-000123/custodia').send({});
    expect(res.status).toBe(409);
    expect(repo.actualizarGuia).not.toHaveBeenCalled();
  });

  it('el comercial solo consulta', async () => {
    const res = await como({ nombre: 'Lucía Ramos', rol: ROLES.COMERCIAL })
      .post('/guias/IPE-2026-000123/custodia')
      .send({});
    expect(res.status).toBe(403);
  });

  it('guía que no existe: 404', async () => {
    repo.buscarPorNumero.mockResolvedValue(null);
    const res = await como(transportista).post('/guias/NO-EXISTE/custodia').send({});
    expect(res.status).toBe(404);
  });
});

describe('documento del cliente (MIGO, H.E.S)', () => {
  const foto = { base64: Buffer.from('guia').toString('base64'), mediaType: 'image/jpeg' };
  const migo = { base64: Buffer.from('migo').toString('base64'), mediaType: 'image/jpeg' };
  const transportista = { nombre: 'Juan Pérez', rol: ROLES.TRANSPORTISTA };
  const entregar = (cuerpo) => como(transportista)
    .patch('/guias/IPE-2026-000123/estado')
    .send({ estado: ESTADOS.ENTREGADO, geo: { lat: -12.1, lng: -77.02 }, foto, ...cuerpo });

  beforeEach(() => {
    repo.actualizarGuia.mockResolvedValue();
    repo.listarSucursales.mockResolvedValue([]);
    fotos.guardarFoto.mockImplementation(async (nombre) => `drive:${nombre}`);
  });

  it('Mota-Engil a cliente final no se cierra sin la foto del MIGO', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia({ destinatario: 'MOTA-ENGIL PERU S.A.' }));
    const res = await entregar();
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/Falta la foto del MIGO/);
    expect(repo.actualizarGuia).not.toHaveBeenCalled();
  });

  it('guarda la foto del MIGO aparte de la guía', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia({ destinatario: 'Mota Engil Perú S.A.' }));
    const res = await entregar({ docCliente: migo });
    expect(res.status).toBe(200);
    expect(fotos.guardarFoto).toHaveBeenCalledWith('IPE-2026-000123_MIGO', migo);
    expect(res.body.foto_entrega_url).toBe('drive:IPE-2026-000123');
    expect(res.body.doc_cliente).toBe('drive:IPE-2026-000123_MIGO');
  });

  it('sin el documento en físico se cierra marcando que va por correo', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia({ destinatario: 'SK RENTAL S.A.C.' }));
    const sinNada = await entregar();
    expect(sinNada.status).toBe(400);
    expect(sinNada.body.error).toMatch(/Falta la foto del H\.E\.S/);
    const res = await entregar({ docPorCorreo: true });
    expect(res.status).toBe(200);
    expect(res.body.doc_cliente).toBe('correo');
    expect(fotos.guardarFoto).toHaveBeenCalledTimes(1);
  });

  it('otros clientes, agencias y el administrador no lo piden', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    expect((await entregar()).status).toBe(200);
    repo.buscarPorNumero.mockResolvedValue(
      guia({ destinatario: 'MOTA-ENGIL PERU S.A.', tipo_entrega: TIPOS_ENTREGA.AGENCIA }),
    );
    expect((await entregar({ estado: ESTADOS.FINALIZADO })).status).toBe(200);
    repo.buscarPorNumero.mockResolvedValue(guia({ destinatario: 'MOTA-ENGIL PERU S.A.' }));
    const admin = await request(app)
      .patch('/guias/IPE-2026-000123/estado')
      .send({ estado: ESTADOS.ENTREGADO, porAdmin: true });
    expect(admin.status).toBe(200);
  });

  it('el comercial ve la foto del documento; si fue por correo, no hay foto', async () => {
    const comercial = { nombre: 'Ana', rol: ROLES.COMERCIAL };
    repo.buscarPorNumero.mockResolvedValue(guia({ doc_cliente: 'drive:abc' }));
    fotos.enviarFoto.mockImplementation(async (_url, res) => res.send('imagen'));
    const res = await como(comercial).get('/guias/IPE-2026-000123/doc-cliente');
    expect(res.status).toBe(200);
    expect(fotos.enviarFoto).toHaveBeenCalledWith('drive:abc', expect.anything());

    repo.buscarPorNumero.mockResolvedValue(guia({ doc_cliente: 'correo' }));
    const correo = await como(comercial).get('/guias/IPE-2026-000123/doc-cliente');
    expect(correo.status).toBe(404);
  });
});

it('un transportista no se salta el MIGO haciéndose pasar por administrador', async () => {
  repo.actualizarGuia.mockResolvedValue();
  repo.buscarPorNumero.mockResolvedValue(guia({ destinatario: 'MOTA-ENGIL PERU S.A.' }));
  const res = await como({ nombre: 'Juan Pérez', rol: ROLES.TRANSPORTISTA })
    .patch('/guias/IPE-2026-000123/estado')
    .send({ estado: ESTADOS.ENTREGADO, porAdmin: true, geo: { lat: -12.1, lng: -77.02 } });
  expect(res.status).toBe(400);
  expect(repo.actualizarGuia).not.toHaveBeenCalled();
});

describe('POST /fotos/migrar (fotos de Blob a Drive)', () => {
  const BLOB = 'https://abc.private.blob.vercel-storage.com/entregas/T1-x.jpg';
  const BLOB_DOC = 'https://abc.private.blob.vercel-storage.com/entregas/T2_MIGO-y.jpg';

  beforeEach(() => {
    jest.spyOn(fotos, 'driveConfigurado').mockReturnValue(true);
    jest.spyOn(fotos, 'copiarADrive').mockImplementation(async (_url, nombre) => `drive:${nombre}`);
    fotos.eliminarFoto.mockResolvedValue();
    repo.actualizarGuia.mockResolvedValue();
    repo.actualizarGuias.mockResolvedValue();
    repo.infoArchivo.mockResolvedValue({ pestanas: [] });
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('pasa a Drive la foto y el documento, anota drive: y borra de Blob', async () => {
    repo.listarGuias.mockResolvedValue([
      guia({ numero_guia: 'T1', foto_entrega_url: BLOB, fecha_cierre: '2026-10-20T15:00:00.000Z', _row: 2 }),
      guia({
        numero_guia: 'T2',
        destinatario: 'MOTA-ENGIL PERU S.A.',
        foto_entrega_url: 'drive:ya',
        doc_cliente: BLOB_DOC,
        _row: 3,
      }),
      guia({ numero_guia: 'T3', foto_entrega_url: '', doc_cliente: 'correo', _row: 4 }),
    ]);
    const res = await request(app).post('/fotos/migrar');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ movidas: 2, pendientes: 0, errores: [] });
    expect(fotos.copiarADrive).toHaveBeenCalledWith(BLOB, 'T1', '2026-10-20');
    expect(fotos.copiarADrive).toHaveBeenCalledWith(BLOB_DOC, 'T2_MIGO', '2026-01-01');
    // Las activas, en una sola escritura.
    expect(repo.actualizarGuias).toHaveBeenCalledTimes(1);
    expect(repo.actualizarGuias.mock.calls[0][0]).toEqual([
      expect.objectContaining({ _row: 2, foto_entrega_url: 'drive:T1' }),
      expect.objectContaining({ _row: 3, doc_cliente: 'drive:T2_MIGO' }),
    ]);
    expect(fotos.eliminarFoto).toHaveBeenCalledWith(BLOB);
    expect(fotos.eliminarFoto).toHaveBeenCalledWith(BLOB_DOC);
  });

  it('si no se puede leer de Blob, no toca la guía ni la borra', async () => {
    repo.listarGuias.mockResolvedValue([guia({ numero_guia: 'T1', foto_entrega_url: BLOB })]);
    fotos.copiarADrive.mockRejectedValue(new Error('Your store is blocked'));
    const res = await request(app).post('/fotos/migrar');
    expect(res.body.movidas).toBe(0);
    expect(res.body.pendientes).toBe(1);
    expect(res.body.errores).toEqual([{ numero_guia: 'T1', error: 'Your store is blocked' }]);
    expect(repo.actualizarGuias).not.toHaveBeenCalled();
    expect(fotos.eliminarFoto).not.toHaveBeenCalled();
  });

  it('si no se puede anotar en la hoja, no borra de Blob', async () => {
    repo.listarGuias.mockResolvedValue([guia({ numero_guia: 'T1', foto_entrega_url: BLOB })]);
    repo.actualizarGuias.mockRejectedValue(new Error('cuota de Google'));
    const res = await request(app).post('/fotos/migrar');
    expect(res.status).toBeGreaterThanOrEqual(500);
    expect(fotos.eliminarFoto).not.toHaveBeenCalled();
  });

  it('también las del archivo, en su pestaña', async () => {
    repo.listarGuias.mockResolvedValue([]);
    repo.infoArchivo.mockResolvedValue({ pestanas: ['Guías 2026'] });
    repo.listarGuiasArchivadas.mockResolvedValue([
      guia({ numero_guia: 'A1', foto_entrega_url: BLOB, _row: 7, _archivo: 'Guías 2026' }),
    ]);
    const res = await request(app).post('/fotos/migrar');
    expect(res.body.movidas).toBe(1);
    expect(repo.actualizarGuia).toHaveBeenCalledWith(
      7,
      expect.objectContaining({ _archivo: 'Guías 2026', foto_entrega_url: 'drive:A1' }),
    );
  });

  it('de a pocas por llamada; sin Drive o sin ser administrador, no', async () => {
    repo.listarGuias.mockResolvedValue(
      Array.from({ length: 25 }, (_, i) => guia({ numero_guia: `T${i}`, foto_entrega_url: BLOB, _row: i + 2 })),
    );
    const res = await request(app).post('/fotos/migrar');
    expect(res.body).toMatchObject({ movidas: 20, pendientes: 5 });

    const transportista = await como({ nombre: 'Juan Pérez', rol: ROLES.TRANSPORTISTA }).post('/fotos/migrar');
    expect(transportista.status).toBe(403);

    fotos.driveConfigurado.mockReturnValue(false);
    const sinDrive = await request(app).post('/fotos/migrar');
    expect(sinDrive.status).toBe(409);
  });
});

it('GET /foto: si la foto apunta a Blob, relee la hoja por si ya pasó a Drive', async () => {
  const BLOB = 'https://abc.private.blob.vercel-storage.com/entregas/T1-x.jpg';
  repo.buscarPorNumero
    .mockResolvedValueOnce(guia({ foto_entrega_url: BLOB }))
    .mockResolvedValueOnce(guia({ foto_entrega_url: 'drive:nuevo' }));
  fotos.enviarFoto.mockImplementation(async (_url, res) => res.send('imagen'));
  const res = await request(app).get('/guias/IPE-2026-000123/foto');
  expect(res.status).toBe(200);
  expect(repo.buscarPorNumero).toHaveBeenLastCalledWith('IPE-2026-000123', { fresco: true });
  expect(fotos.enviarFoto).toHaveBeenCalledWith('drive:nuevo', expect.anything());
});

it('GET /foto con fechaCreacion: la foto de esa tarea, no la de la más reciente', async () => {
  repo.listarGuias.mockResolvedValue([
    guia({ numero_guia: 'T033-3531', fecha_creacion: '2026-10-01T13:45:00.000Z', foto_entrega_url: 'drive:tramo1' }),
    guia({ numero_guia: 'T033-3531', fecha_creacion: '2026-10-01T15:28:00.000Z', foto_entrega_url: 'drive:tramo2' }),
  ]);
  fotos.enviarFoto.mockImplementation(async (_url, res) => res.send('imagen'));
  const res = await request(app)
    .get('/guias/T033-3531/foto')
    .query({ fechaCreacion: '2026-10-01T13:45:00.000Z' });
  expect(res.status).toBe(200);
  expect(fotos.enviarFoto).toHaveBeenCalledWith('drive:tramo1', expect.anything());
  expect(repo.buscarPorNumero).not.toHaveBeenCalled();
});

describe('Sub administrador', () => {
  const usuarios = [
    { nombre: 'Jairo Fabian', rol: ROLES.SUB_ADMINISTRADOR, pin: 'jairo123', activo: true },
    { nombre: 'Almacen Viru', rol: ROLES.TRANSPORTISTA, activo: true, encargado: 'Jairo Fabian' },
    { nombre: 'Trp Huancayo', rol: ROLES.TRANSPORTISTA, activo: false, encargado: 'jairo fabian' },
    { nombre: 'Oscar Aspur', rol: ROLES.TRANSPORTISTA, activo: true, encargado: 'Encargado Lima' },
  ];
  const jairo = () => como({ nombre: 'Jairo Fabian', rol: ROLES.SUB_ADMINISTRADOR });
  beforeEach(() => repo.listarUsuarios.mockResolvedValue(usuarios));

  it('ingresa con su rol', async () => {
    const res = await sinSesion()
      .post('/auth/login')
      .send({ nombre: 'Jairo Fabian', pin: 'jairo123' });
    expect(res.status).toBe(200);
    expect(res.body.rol).toBe(ROLES.SUB_ADMINISTRADOR);
  });

  it('su equipo: los transportistas que lo tienen de encargado (activos o no)', async () => {
    const res = await jairo().get('/transportistas/equipo');
    expect(res.status).toBe(200);
    expect(res.body).toEqual([{ nombre: 'Almacen Viru' }, { nombre: 'Trp Huancayo' }]);
  });

  it('corrige una guía de su transportista, también sin GPS', async () => {
    const suya = guia({ numero_guia: 'T1', transportista: 'Almacen Viru' });
    repo.listarGuias.mockResolvedValue([suya]);
    repo.buscarPorNumero.mockResolvedValue(suya);
    const res = await jairo()
      .patch('/guias/T1/estado')
      .send({ estado: ESTADOS.ENTREGADO, porAdmin: true });
    expect(res.status).toBe(200);
    expect(res.body.corregido_por_admin).toBe(true);
  });

  it('no toca guías de transportistas que no están a su cargo', async () => {
    const ajena = guia({ numero_guia: 'T2', transportista: 'Oscar Aspur' });
    repo.listarGuias.mockResolvedValue([ajena]);
    repo.buscarPorNumero.mockResolvedValue(ajena);
    const res = await jairo()
      .patch('/guias/T2/estado')
      .send({ estado: ESTADOS.ENTREGADO, porAdmin: true });
    expect(res.status).toBe(403);
    expect(repo.actualizarGuia).not.toHaveBeenCalled();
    expect((await jairo().delete('/guias/T2')).status).toBe(403);
  });

  it('no registra guías ni cambia sucursales, archivo o regularización', async () => {
    expect((await jairo().post('/guias').send({})).status).toBe(403);
    expect((await jairo().post('/guias/lote').send({})).status).toBe(403);
    expect((await jairo().put('/sucursales/Ate').send({})).status).toBe(403);
    expect((await jairo().post('/guias/regularizar').send({})).status).toBe(403);
    expect((await jairo().post('/fotos/migrar')).status).toBe(403);
    expect(repo.guardarSucursal).not.toHaveBeenCalled();
  });

  it('puede consultar cualquier guía (Rastrear)', async () => {
    repo.listarGuias.mockResolvedValue([
      guia({ numero_guia: 'T2', transportista: 'Oscar Aspur' }),
    ]);
    const res = await jairo().get('/guias');
    expect(res.status).toBe(200);
    expect(res.body).toHaveLength(1);
  });
});
