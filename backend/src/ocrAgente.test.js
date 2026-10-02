const mockGenerateContent = jest.fn();
jest.mock('@google/genai', () => ({
  GoogleGenAI: jest.fn().mockImplementation(() => ({ models: { generateContent: mockGenerateContent } })),
}));

process.env.GEMINI_API_KEY = 'prueba';
const { leerNumeroGuia, leerComprobante, claveGuia, comprobanteDe } = require('./ocrAgente');

const responde = (json) => mockGenerateContent.mockResolvedValueOnce({ text: JSON.stringify(json) });

describe('claveGuia', () => {
  it('ignora ceros a la izquierda, espacios, N° y confusiones O/0 e I/1 de la serie', () => {
    const clave = claveGuia('T001-93506');
    for (const leido of ['T001-0093506', 't001 - 93506', 'T001 N° 0093506', 'TOO1-93506', 'TO01-93506']) {
      expect(claveGuia(leido)).toBe(clave);
    }
    expect(claveGuia('T001-93507')).not.toBe(clave);
    expect(claveGuia('T002-93506')).not.toBe(clave);
  });
});

describe('leerNumeroGuia', () => {
  beforeEach(() => mockGenerateContent.mockReset());

  it('manda los candidatos a la IA y devuelve el de la lista', async () => {
    responde({ numero_guia: 'T001-93506' });
    const r = await leerNumeroGuia('ZmFrZQ==', 'image/jpeg', ['T001-93506', 'T001-93507']);
    expect(r).toEqual({ numero_guia: 'T001-93506', agencia_razon_social: null, agencia_ruc: null, agencia_monto: null });
    const prompt = mockGenerateContent.mock.calls[0][0].contents[1].text;
    expect(prompt).toContain('- T001-93507');
  });

  it('si la IA lo lee con ceros u otra forma, lo cambia por el de la lista', async () => {
    responde({ numero_guia: 'TOO1 - 0093507' });
    const r = await leerNumeroGuia('ZmFrZQ==', 'image/jpeg', ['T001-93506', 'T001-93507']);
    expect(r).toEqual({ numero_guia: 'T001-93507', agencia_razon_social: null, agencia_ruc: null, agencia_monto: null });
  });

  it('si no es de la lista devuelve lo leído, y null si no se ve', async () => {
    responde({ numero_guia: 'X999-1' });
    expect(await leerNumeroGuia('ZmFrZQ==', 'image/jpeg', ['T001-1'])).toEqual({ numero_guia: 'X999-1', agencia_razon_social: null, agencia_ruc: null, agencia_monto: null });
    responde({ numero_guia: null });
    expect(await leerNumeroGuia('ZmFrZQ==', 'image/jpeg', [])).toEqual({ numero_guia: null, agencia_razon_social: null, agencia_ruc: null, agencia_monto: null });
  });
});

describe('comprobante de agencia', () => {
  beforeEach(() => mockGenerateContent.mockReset());

  it('limpia lo que lee la IA: RUC de 11 dígitos, sin el de IPESA, y el total como número', () => {
    expect(
      comprobanteDe({
        agencia_razon_social: ' TURISMO INTERNACIONAL PALOMINO S.A.C. ',
        agencia_ruc: '20515659324',
        agencia_monto: 'S/ 70.00',
      }),
    ).toEqual({
      agencia_razon_social: 'TURISMO INTERNACIONAL PALOMINO S.A.C.',
      agencia_ruc: '20515659324',
      agencia_monto: 70,
    });
    expect(comprobanteDe({ agencia_ruc: '20101639275', agencia_razon_social: 'IPESA S.A.C.' })).toEqual({
      agencia_razon_social: null,
      agencia_ruc: null,
      agencia_monto: null,
    });
    expect(comprobanteDe({ agencia_monto: '1.234,50' }).agencia_monto).toBe(1234.5);
    expect(comprobanteDe({ agencia_monto: '13,00' }).agencia_monto).toBe(13);
    expect(comprobanteDe({ agencia_ruc: '2060185745' }).agencia_ruc).toBeNull();
  });

  it('lee el comprobante de la foto de entrega', async () => {
    responde({
      agencia_razon_social: 'SEÑOR DE LUREN EXPRESS E.I.R.L.',
      agencia_ruc: '20601857457',
      agencia_monto: 13,
    });
    expect(await leerComprobante('ZmFrZQ==', 'image/jpeg')).toEqual({
      agencia_razon_social: 'SEÑOR DE LUREN EXPRESS E.I.R.L.',
      agencia_ruc: '20601857457',
      agencia_monto: 13,
    });
  });

  it('el número de guía también trae el comprobante si lo hay', async () => {
    responde({ numero_guia: 'T028-132601', agencia_razon_social: 'ITTSA', agencia_ruc: '20132272418', agencia_monto: 24 });
    const r = await leerNumeroGuia('ZmFrZQ==', 'image/jpeg', ['T028-132601']);
    expect(r).toEqual({
      numero_guia: 'T028-132601',
      agencia_razon_social: 'ITTSA',
      agencia_ruc: '20132272418',
      agencia_monto: 24,
    });
  });
});
