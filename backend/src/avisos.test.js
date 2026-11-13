jest.mock('web-push', () => ({ sendNotification: jest.fn() }));
process.env.AUTH_SECRET = 'clave-solo-para-pruebas-0123456789abcdef';
const webpush = require('web-push');
const avisos = require('./avisos');

describe('avisos al celular', () => {
  it('las claves salen de la clave de firma y siempre son las mismas', () => {
    const a = avisos.clavesVapid();
    expect(Buffer.from(a.publica, 'base64url')).toHaveLength(65);
    expect(Buffer.from(a.privada, 'base64url')).toHaveLength(32);
    expect(avisos.clavesVapid()).toEqual(a);
  });

  it('manda el aviso cifrado con las claves del servidor', async () => {
    webpush.sendNotification.mockResolvedValue({});
    const r = await avisos.enviar({ endpoint: 'https://x/1', p256dh: 'p', auth: 'a' }, { titulo: 'Hola' });
    expect(r).toBe('ok');
    const [sub, cuerpo, opciones] = webpush.sendNotification.mock.calls[0];
    expect(sub).toEqual({ endpoint: 'https://x/1', keys: { p256dh: 'p', auth: 'a' } });
    expect(JSON.parse(cuerpo)).toEqual({ titulo: 'Hola' });
    expect(opciones.vapidDetails.publicKey).toBe(avisos.clavesVapid().publica);
    expect(opciones.urgency).toBe('high');
  });

  it('un celular dado de baja vuelve como vencida', async () => {
    webpush.sendNotification.mockRejectedValue(Object.assign(new Error('Gone'), { statusCode: 410 }));
    expect(await avisos.enviar({ endpoint: 'https://x/1', p256dh: 'p', auth: 'a' }, {})).toBe('vencida');
  });

  it('el mensaje lista hasta 3 guías', () => {
    const g = (n) => ({ numero_guia: n });
    expect(avisos.mensajeRecordatorio([g('A')]).titulo).toBe('Tienes 1 tarea por cerrar');
    expect(avisos.mensajeRecordatorio([g('A'), g('B'), g('C'), g('D'), g('E')]).cuerpo)
      .toBe('A, B, C y 2 más. Entrégalas, recházalas o déjalas en custodia.');
  });
});
