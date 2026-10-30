import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// En la PC, la tecla Esc vuelve a la pantalla anterior (como la flecha de
/// "atrás"). Solo para pantallas de consulta: en un formulario se perdería
/// lo escrito.
class VolverConEsc extends StatelessWidget {
  const VolverConEsc({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
