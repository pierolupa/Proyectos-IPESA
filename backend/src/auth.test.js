const auth = require('./auth');

const sesion = { nombre: 'Juan Pérez', rol: 'transportista' };

describe('tokens de sesión', () => {
  const original = { ...process.env };
  afterEach(() => {
    process.env = { ...original };
  });

  beforeEach(() => {
    process.env.AUTH_SECRET = 'clave-de-prueba-0123456789abcdef0123';
  });

  it('un token recién creado se lee con su nombre y rol', () => {
    const { token, expira } = auth.crearToken(sesion);
    expect(auth.leerToken(token)).toEqual(sesion);
    expect(Date.parse(expira) - Date.now()).toBeGreaterThan(auth.DURACION_SESION_MS - 5000);
  });

  it('vence a las 12 horas', () => {
    const ahora = Date.now();
    const { token } = auth.crearToken(sesion, ahora);
    expect(auth.leerToken(token, ahora + auth.DURACION_SESION_MS - 1)).toEqual(sesion);
    expect(auth.leerToken(token, ahora + auth.DURACION_SESION_MS)).toBeNull();
  });

  it('no sirve con otra clave de firma', () => {
    const { token } = auth.crearToken(sesion);
    process.env.AUTH_SECRET = 'otra-clave-distinta-0123456789abcdef';
    expect(auth.leerToken(token)).toBeNull();
  });

  it('sin AUTH_SECRET firma con una clave derivada de la cuenta de Google', () => {
    delete process.env.AUTH_SECRET;
    process.env.GOOGLE_SERVICE_ACCOUNT_KEY = '{"private_key":"uno"}';
    const { token } = auth.crearToken(sesion);
    expect(auth.leerToken(token)).toEqual(sesion);
    process.env.GOOGLE_SERVICE_ACCOUNT_KEY = '{"private_key":"dos"}';
    expect(auth.leerToken(token)).toBeNull();
  });

  it('sin ninguna clave no firma (falla en vez de usar una conocida)', () => {
    delete process.env.AUTH_SECRET;
    delete process.env.GOOGLE_SERVICE_ACCOUNT_KEY;
    expect(() => auth.crearToken(sesion)).toThrow(/AUTH_SECRET/);
  });

  it('rechaza basura sin romperse', () => {
    for (const malo of [undefined, null, '', 'abc', 'a.b.c', '.', 'x.', '.y', 123]) {
      expect(auth.leerToken(malo)).toBeNull();
    }
  });
});

describe('freno de intentos de login', () => {
  beforeEach(() => auth.olvidarFallos());

  it('bloquea tras MAX_FALLOS y se libera pasado el tiempo', () => {
    const t0 = 1_000_000;
    for (let i = 0; i < auth.MAX_FALLOS; i++) auth.registrarFallo(' Juan ', t0);
    expect(auth.loginBloqueado('juan', t0 + 1000)).toBe(true);
    expect(auth.loginBloqueado('otro', t0 + 1000)).toBe(false);
    expect(auth.loginBloqueado('juan', t0 + auth.BLOQUEO_MS + 1)).toBe(false);
  });

  it('limpiarFallos lo desbloquea', () => {
    for (let i = 0; i < auth.MAX_FALLOS; i++) auth.registrarFallo('juan');
    auth.limpiarFallos('JUAN');
    expect(auth.loginBloqueado('juan')).toBe(false);
  });
});
