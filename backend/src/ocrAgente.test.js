const mockGenerateContent = jest.fn();
jest.mock('@google/genai', () => ({
  GoogleGenAI: jest.fn().mockImplementation(() => ({ models: { generateContent: mockGenerateContent } })),
}));

process.env.GEMINI_API_KEY = 'prueba';
const { leerNumeroGuia, claveGuia } = require('./ocrAgente');

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
    expect(r).toEqual({ numero_guia: 'T001-93506' });
    const prompt = mockGenerateContent.mock.calls[0][0].contents[1].text;
    expect(prompt).toContain('- T001-93507');
  });

  it('si la IA lo lee con ceros u otra forma, lo cambia por el de la lista', async () => {
    responde({ numero_guia: 'TOO1 - 0093507' });
    const r = await leerNumeroGuia('ZmFrZQ==', 'image/jpeg', ['T001-93506', 'T001-93507']);
    expect(r).toEqual({ numero_guia: 'T001-93507' });
  });

  it('si no es de la lista devuelve lo leído, y null si no se ve', async () => {
    responde({ numero_guia: 'X999-1' });
    expect(await leerNumeroGuia('ZmFrZQ==', 'image/jpeg', ['T001-1'])).toEqual({ numero_guia: 'X999-1' });
    responde({ numero_guia: null });
    expect(await leerNumeroGuia('ZmFrZQ==', 'image/jpeg', [])).toEqual({ numero_guia: null });
  });
});
