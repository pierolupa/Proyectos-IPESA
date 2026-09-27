import 'package:flutter/material.dart';

import '../theme.dart';

/// Marcas que representa IPESA (logos en assets/marcas/, recortados de
/// ipesa.com.pe). El orden es el de la web.
const marcasIpesa = <(String, String)>[
  ('John Deere', 'john_deere'),
  ('Wirtgen', 'wirtgen'),
  ('Vögele', 'vogele'),
  ('Hamm', 'hamm'),
  ('Kleemann', 'kleemann'),
  ('Benninghoven', 'benninghoven'),
  ('Ciber', 'ciber'),
  ('Aksa', 'aksa'),
  ('Fiori', 'fiori'),
  ('Terramac', 'terramac'),
  ('Romanelli', 'romanelli'),
  ('Bergkamp', 'bergkamp'),
  ('Simem', 'simem'),
  ('NPK', 'npk'),
  ('Socomec', 'socomec'),
  ('Bia Baldan', 'bia_baldan'),
  ('Bison', 'bison'),
  ('GF Gordini', 'gf_gordini'),
  ('Gama', 'gama'),
  ('Fieldking', 'fieldking'),
  ('JF', 'jf'),
  ('Lavrale', 'lavrale'),
  ('DAF', 'daf'),
  ('Kenworth', 'kenworth'),
];

/// Cinta de logos que avanza sola, en bucle y sin saltos. Si el sistema
/// pide reducir animaciones, queda quieta y se puede deslizar a mano.
class CarruselMarcas extends StatefulWidget {
  const CarruselMarcas({
    super.key,
    this.alto = 64,
    this.ancho = 148,
    this.separacion = 12,
    this.pixelesPorSegundo = 36,
    this.bordeTarjeta = Ipesa.borde,
    this.difuminar = true,
  });

  final double alto;
  final double ancho;
  final double separacion;
  final double pixelesPorSegundo;
  final Color bordeTarjeta;

  /// Desvanece los extremos de la cinta. Se apaga cuando la cinta ya
  /// sale de la pantalla por los lados (la cinta verde del login).
  final bool difuminar;

  /// Los tests lo apagan (test/flutter_test_config.dart): una animación
  /// sin fin haría que `pumpAndSettle` no termine nunca.
  @visibleForTesting
  static bool animar = true;

  @override
  State<CarruselMarcas> createState() => _CarruselMarcasState();
}

class _CarruselMarcasState extends State<CarruselMarcas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _avance = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: (_anchoVuelta / widget.pixelesPorSegundo * 1000).round(),
    ),
  );

  double get _paso => widget.ancho + widget.separacion;
  double get _anchoVuelta => _paso * marcasIpesa.length;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_quieto(context)) {
      _avance.stop();
    } else if (!_avance.isAnimating) {
      _avance.repeat();
    }
  }

  static bool _quieto(BuildContext context) =>
      !CarruselMarcas.animar || MediaQuery.of(context).disableAnimations;

  @override
  void dispose() {
    _avance.dispose();
    super.dispose();
  }

  Widget _tarjeta(String nombre, String archivo) => Container(
    width: widget.ancho,
    height: widget.alto,
    margin: EdgeInsets.only(right: widget.separacion),
    padding: EdgeInsets.symmetric(
      horizontal: widget.alto * 0.18,
      vertical: widget.alto * 0.15,
    ),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: widget.bordeTarjeta),
    ),
    child: Tooltip(
      message: nombre,
      child: Image.asset(
        'assets/marcas/$archivo.png',
        fit: BoxFit.contain,
        semanticLabel: nombre,
        filterQuality: FilterQuality.medium,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tarjetas = [
      for (final (nombre, archivo) in marcasIpesa) _tarjeta(nombre, archivo),
    ];

    final Widget cinta;
    if (_quieto(context)) {
      cinta = ListView(scrollDirection: Axis.horizontal, children: tarjetas);
    } else {
      cinta = LayoutBuilder(
        builder: (context, constraints) {
          // Suficientes vueltas para cubrir el ancho visible y una más,
          // así al reiniciar la animación no se nota el salto.
          final vueltas = (constraints.maxWidth / _anchoVuelta).ceil() + 1;
          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              child: AnimatedBuilder(
                animation: _avance,
                builder: (context, hijo) => Transform.translate(
                  offset: Offset(-_avance.value * _anchoVuelta, 0),
                  child: hijo,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (var i = 0; i < vueltas; i++) ...tarjetas],
                ),
              ),
            ),
          );
        },
      );
    }

    if (!widget.difuminar) return SizedBox(height: widget.alto, child: cinta);

    // Los extremos se desvanecen (máscara de opacidad) sobre cualquier fondo.
    return SizedBox(
      height: widget.alto,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0, 0.08, 0.92, 1],
        ).createShader(rect),
        child: cinta,
      ),
    );
  }
}

/// Franja fija de marcas al pie de las pantallas principales de la app
/// (va en `Scaffold.bottomNavigationBar`, así el botón flotante queda
/// encima de ella).
class BandaMarcas extends StatelessWidget {
  const BandaMarcas({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Ipesa.borde)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Semantics(
              label: 'Marcas que representa IPESA',
              child: const CarruselMarcas(
                alto: 42,
                ancho: 112,
                separacion: 10,
                pixelesPorSegundo: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
