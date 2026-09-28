jest.mock('./sheetsRepository');
jest.mock('./ocrAgente');
jest.mock('./fotos', () => ({
  ...jest.requireActual('./fotos'),
  guardarFoto: jest.fn(),
  enviarFoto: jest.fn(),
  eliminarFoto: jest.fn(),
}));

const request = require('supertest');
const repo = require('./sheetsRepository');
const { leerGuiaConIA } = require('./ocrAgente');
const fotos = require('./fotos');
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

  it('no deja registrar la misma guía dentro de las 2 horas', async () => {
    const haceMedia = new Date(Date.now() - 30 * 60000).toISOString();
    repo.buscarPorNumero.mockResolvedValue(
      guia({ numero_guia: payload.numeroGuia, fecha_creacion: haceMedia }),
    );
    const res = await request(app).post('/guias').send(payload);
    expect(res.status).toBe(409);
    expect(res.body.error).toMatch(/hace 30 min/);
    expect(res.body.error).toMatch(/desde las \d{2}:\d{2}/);
    expect(repo.crearGuia).not.toHaveBeenCalled();
    // La comprobación lee la hoja sin caché.
    expect(repo.buscarPorNumero).toHaveBeenCalledWith(payload.numeroGuia, { fresco: true });
  });

  it('la misma guía se puede registrar otra vez pasadas 2 horas, aunque siga activa', async () => {
    const haceTres = new Date(Date.now() - 3 * 3600000).toISOString();
    repo.buscarPorNumero.mockResolvedValue(
      guia({ numero_guia: payload.numeroGuia, fecha_creacion: haceTres }),
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
    // Devuelve la guía completa para que la app no recargue todo.
    expect(res.body).toMatchObject({
      numero_guia: payload.numeroGuia,
      destinatario: payload.destinatario,
      transportista: payload.transportista,
    });
    expect(res.body.fecha_creacion).toBeTruthy();
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

  it('no crea un traslado hacia una sucursal que no existe', async () => {
    repo.listarSucursales.mockResolvedValue([sucursal]);
    const res = await request(app).post('/guias').send({
      numeroGuia: 'T001-1',
      tipoEntrega: TIPOS_ENTREGA.ENTRE_SUCURSALES,
      origen: 'Almacén Callao',
      destino: 'Sucursal Cusco',
      transportista: 'Juan Pérez',
      destinatario: 'Sucursal',
      geo: { lat: -12.05, lng: -77.04 },
    });
    expect(res.status).toBe(400);
    expect(repo.crearGuia).not.toHaveBeenCalled();
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
    repo.buscarPorNumero.mockResolvedValue(
      guia({ estado: ESTADOS.RECHAZADO, fecha_creacion: new Date().toISOString() }),
    );
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

  it('entre sucursales exige una sucursal registrada', async () => {
    repo.buscarPorNumero.mockResolvedValue(guia());
    repo.listarSucursales.mockResolvedValue([
      { nombre: 'Sucursal Arequipa', lat: -16.4, lng: -71.5, radio_m: 200 },
    ]);
    const mal = await request(app)
      .patch('/guias/IPE-2026-000123/tipo')
      .send({ tipoEntrega: TIPOS_ENTREGA.ENTRE_SUCURSALES, destino: 'Cusco' });
    expect(mal.status).toBe(400);
    const bien = await request(app)
      .patch('/guias/IPE-2026-000123/tipo')
      .send({ tipoEntrega: TIPOS_ENTREGA.ENTRE_SUCURSALES, destino: 'sucursal arequipa' });
    expect(bien.status).toBe(200);
    expect(bien.body.destino).toBe('Sucursal Arequipa');
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
