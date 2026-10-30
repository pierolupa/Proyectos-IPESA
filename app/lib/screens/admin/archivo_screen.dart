import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/guias_api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';

const _meses = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// "2026-10-01" → (2026, 10).
(int, int) _anioMes(String corte) {
  final partes = corte.split('-');
  return (int.parse(partes[0]), int.parse(partes[1]));
}

String _corte(int anio, int mes) =>
    '$anio-${mes.toString().padLeft(2, '0')}-01';

/// Los cortes que se ofrecen: el más reciente permitido y los 11 anteriores.
List<String> cortesDisponibles(String maximo) {
  var (anio, mes) = _anioMes(maximo);
  final cortes = <String>[];
  for (var i = 0; i < 12; i++) {
    cortes.add(_corte(anio, mes));
    mes--;
    if (mes == 0) {
      mes = 12;
      anio--;
    }
  }
  return cortes;
}

/// "2026-10-01" → "hasta septiembre de 2026 (todo lo anterior al 1 de octubre)".
String etiquetaCorte(String corte) {
  final (anio, mes) = _anioMes(corte);
  final anterior = mes == 1 ? (anio - 1, 12) : (anio, mes - 1);
  return 'Hasta ${_meses[anterior.$2 - 1]} de ${anterior.$1}';
}

/// Archivo por año: pasa las guías cerradas de meses anteriores a una
/// pestaña por año ("Guías 2026") para que la hoja activa siga liviana. Se
/// simula primero; archivar pide el PIN del administrador.
class ArchivoScreen extends StatefulWidget {
  const ArchivoScreen({super.key});

  @override
  State<ArchivoScreen> createState() => _ArchivoScreenState();
}

class _ArchivoScreenState extends State<ArchivoScreen> {
  PlanArchivo? _plan;
  List<String> _cortes = const [];
  String? _corte;
  bool _cargando = true;
  bool _archivando = false;
  String? _error;
  String? _listo;

  @override
  void initState() {
    super.initState();
    _simular();
  }

  Future<void> _simular([String? corte]) async {
    setState(() {
      _cargando = true;
      _error = null;
      if (corte != null) _corte = corte;
    });
    try {
      final plan = await context.read<AppState>().simularArchivo(hasta: corte);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _corte = plan.hasta;
        if (_cortes.isEmpty) {
          _cortes = cortesDisponibles(plan.maximo ?? plan.hasta);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _archivar() async {
    final plan = _plan;
    if (plan == null || plan.total == 0) return;
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoPin(total: plan.total),
    );
    if (pin == null || !mounted) return;
    setState(() {
      _archivando = true;
      _error = null;
      _listo = null;
    });
    try {
      final res = await context.read<AppState>().archivar(
        pin: pin,
        hasta: plan.hasta,
      );
      if (!mounted) return;
      final destino = res.porPestana.keys.join(', ');
      setState(
        () => _listo =
            'Listo: ${res.total} guías pasaron a "$destino". Se siguen '
            'viendo en Rastrear, Guías y Dashboard.',
      );
      await _simular(plan.hasta);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _archivando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final ocupado = _cargando || _archivando;
    return Scaffold(
      backgroundColor: Ipesa.fondo,
      appBar: AppBar(title: const Text('Archivo de guías')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Pasa las guías cerradas de meses anteriores a una pestaña '
                  'por año ("Guías 2026") dentro de la misma hoja. Así la '
                  'hoja activa sigue liviana y la app rápida. Las guías '
                  'archivadas se siguen viendo en Rastrear, Guías y Dashboard '
                  'al elegir esas fechas.',
                  style: TextStyle(fontSize: 15, color: Ipesa.textoSuave),
                ),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _corte,
                          key: ValueKey(_cortes.length),
                          decoration: const InputDecoration(
                            labelText: 'Archivar las guías registradas',
                          ),
                          items: [
                            for (final c in _cortes)
                              DropdownMenuItem(
                                value: c,
                                child: Text(etiquetaCorte(c)),
                              ),
                          ],
                          onChanged: ocupado
                              ? null
                              : (c) {
                                  if (c != null && c != _corte) _simular(c);
                                },
                        ),
                        const SizedBox(height: 16),
                        if (_cargando)
                          const LinearProgressIndicator(minHeight: 3)
                        else if (plan != null)
                          _Resumen(plan: plan),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: ocupado || plan == null || plan.total == 0
                              ? null
                              : _archivar,
                          icon: _archivando
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.inventory_2_outlined),
                          label: Text(
                            _archivando
                                ? 'Archivando…'
                                : plan == null || plan.total == 0
                                ? 'Nada para archivar'
                                : 'Archivar ${plan.total} guías',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Hazlo de noche o cuando nadie esté registrando guías. Si '
                  'alguien cambia la hoja mientras se archiva, no se borra '
                  'nada y puedes volver a intentarlo sin duplicar.',
                  style: TextStyle(fontSize: 13.5, color: Ipesa.textoSuave),
                ),
                if (_listo != null) ...[
                  const SizedBox(height: 16),
                  _Aviso(texto: _listo!, error: false),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _Aviso(texto: _error!, error: true),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.plan});

  final PlanArchivo plan;

  @override
  Widget build(BuildContext context) {
    if (plan.total == 0) {
      return const Text(
        'No hay guías cerradas para archivar en ese periodo.',
        style: TextStyle(fontSize: 15, color: Ipesa.textoSuave),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Se moverían ${plan.total} guías cerradas',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Ipesa.texto,
          ),
        ),
        const SizedBox(height: 4),
        for (final e in plan.porPestana.entries)
          Text(
            '${e.value} a la pestaña "${e.key}"',
            style: const TextStyle(fontSize: 14.5, color: Ipesa.textoSuave),
          ),
        const SizedBox(height: 4),
        const Text(
          'Las que siguen abiertas o con algo pendiente se quedan.',
          style: TextStyle(fontSize: 13.5, color: Ipesa.textoSuave),
        ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, required this.error});

  final String texto;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? const Color(0xFFB3261E) : Ipesa.turquesa;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Ipesa.radioCampo),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(texto, style: TextStyle(fontSize: 14.5, color: color)),
    );
  }
}

class _DialogoPin extends StatefulWidget {
  const _DialogoPin({required this.total});

  final int total;

  @override
  State<_DialogoPin> createState() => _DialogoPinState();
}

class _DialogoPinState extends State<_DialogoPin> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _confirmar() {
    final pin = _pin.text.trim();
    if (pin.isNotEmpty) Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Archivar ${widget.total} guías'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Confirma con tu PIN de administrador.'),
          const SizedBox(height: 12),
          TextField(
            controller: _pin,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'PIN'),
            onSubmitted: (_) => _confirmar(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _confirmar, child: const Text('Archivar')),
      ],
    );
  }
}
