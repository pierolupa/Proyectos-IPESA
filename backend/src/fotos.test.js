jest.mock('@vercel/blob', () => ({ put: jest.fn(), get: jest.fn() }));

const { put } = require('@vercel/blob');
const fotos = require('./fotos');

const foto = { base64: Buffer.from('jpg').toString('base64'), mediaType: 'image/jpeg' };

function respuestaJson(cuerpo) {
  return { json: async () => cuerpo };
}

describe('fotos en Google Drive', () => {
  const entornoOriginal = { ...process.env };

  beforeEach(() => {
    jest.resetAllMocks();
    delete process.env.BLOB_READ_WRITE_TOKEN;
    delete process.env.BLOB_STORE_ID;
    process.env.DRIVE_FOTOS_URL = 'https://script.google.com/macros/s/X/exec';
    process.env.DRIVE_FOTOS_CLAVE = 'clave-de-prueba';
    global.fetch = jest.fn();
  });

  afterAll(() => {
    process.env = entornoOriginal;
  });

  it('cuenta como almacenamiento configurado', () => {
    expect(fotos.almacenamientoConfigurado()).toBe(true);
    delete process.env.DRIVE_FOTOS_CLAVE;
    expect(fotos.almacenamientoConfigurado()).toBe(false);
  });

  it('guarda la foto con la clave y devuelve drive:<id>', async () => {
    global.fetch.mockResolvedValue(respuestaJson({ id: 'abc123' }));

    const donde = await fotos.guardarFoto('T033-3455', foto);

    expect(donde).toBe('drive:abc123');
    expect(put).not.toHaveBeenCalled();
    const [url, opciones] = global.fetch.mock.calls[0];
    expect(url).toBe('https://script.google.com/macros/s/X/exec');
    const enviado = JSON.parse(opciones.body);
    expect(enviado).toMatchObject({
      accion: 'guardar',
      clave: 'clave-de-prueba',
      tipo: 'image/jpeg',
      base64: foto.base64,
    });
    expect(enviado.nombre).toMatch(/^T033-3455_\d{4}-\d{2}-\d{2}\.jpg$/);
  });

  it('explica el error si el script lo rechaza', async () => {
    global.fetch.mockResolvedValue(respuestaJson({ error: 'Clave incorrecta.' }));
    await expect(fotos.guardarFoto('T1', foto)).rejects.toThrow(
      'Google Drive: Clave incorrecta.',
    );
  });

  it('avisa si el script no está publicado para cualquier persona', async () => {
    global.fetch.mockResolvedValue({
      json: async () => {
        throw new SyntaxError('Unexpected token <');
      },
    });
    await expect(fotos.guardarFoto('T1', foto)).rejects.toThrow(/Cualquier persona/);
  });

  it('sirve una foto de Drive como imagen', async () => {
    global.fetch.mockResolvedValue(
      respuestaJson({ tipo: 'image/png', base64: Buffer.from('png').toString('base64') }),
    );
    const res = { set: jest.fn(), send: jest.fn() };

    await fotos.enviarFoto('drive:abc123', res);

    expect(JSON.parse(global.fetch.mock.calls[0][1].body)).toMatchObject({
      accion: 'leer',
      id: 'abc123',
    });
    expect(res.set).toHaveBeenCalledWith('Content-Type', 'image/png');
    expect(res.send.mock.calls[0][0].toString()).toBe('png');
  });
});
