jest.mock('./sheetsRepository');
jest.mock('./ocrAgente');

const request = require('supertest');
const repo = require('./sheetsRepository');
const { leerGuiaConIA } = require('./ocrAgente');
const { ESTADOS, TIPOS_ENTREGA, ROLES } = require('./columns');

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
    expect(repo.crearGuia).not.toHaveBeenCalled();
  });

  it('rechaza un número de guía duplicado y activo', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia({ numero_guia: payload.numeroGuia }));
    const res = await request(app).post('/guias').send(payload);
    expect(res.status).toBe(409);
    expect(repo.crearGuia).not.toHaveBeenCalled();
  });

  it('permite reasignar un número de guía ya finalizado', async () => {
    repo.buscarPorNumero.mockResolvedValue(
      guia({ numero_guia: payload.numeroGuia, estado: ESTADOS.FINALIZADO }),
    );
    const res = await request(app).post('/guias').send(payload);
    expect(res.status).toBe(201);
    expect(repo.crearGuia).toHaveBeenCalledTimes(1);
  });

  it('crea la guía en estado en_ruta cuando no hay duplicado', async () => {
    repo.buscarPorNumero.mockResolvedValue(null);
    const res = await request(app).post('/guias').send(payload);
    expect(res.status).toBe(201);
    expect(res.body.estado).toBe(ESTADOS.EN_RUTA);
    expect(repo.crearGuia).toHaveBeenCalledWith(
      expect.objectContaining({ numero_guia: payload.numeroGuia, estado: ESTADOS.EN_RUTA }),
    );
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

describe('GET /guias/rastreo/:ultimosCuatro', () => {
  it('valida que sean exactamente 4 dígitos', async () => {
    const res = await request(app).get('/guias/rastreo/12a4');
    expect(res.status).toBe(400);
  });

  it('no expone destinatario ni transportista', async () => {
    repo.listarGuias.mockResolvedValue([guia({ numero_guia: 'IPE-2026-000123' })]);
    const res = await request(app).get('/guias/rastreo/0123');
    expect(res.status).toBe(200);
    expect(res.body).toEqual([
      { ultimos_cuatro: '0123', estado: ESTADOS.EN_RUTA, destino: 'Av. Siempre Viva 742' },
    ]);
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
});
