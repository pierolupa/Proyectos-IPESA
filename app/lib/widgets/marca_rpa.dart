import 'package:flutter/material.dart';

import '../theme.dart';

/// El eslogan de RPA.
const esloganRpa = 'La IA lo vio, el cliente lo firmó.';

/// La marca de la app: el logo de RPA (mitad IA, mitad ruta), el nombre y,
/// si hay espacio, lo que significa la sigla y el eslogan. [claro] es para
/// fondos oscuros (petróleo o negro).
class MarcaRpa extends StatelessWidget {
  const MarcaRpa({
    super.key,
    this.tamano = 40,
    this.claro = false,
    this.conNombre = true,
    this.conDescripcion = false,
    this.conEslogan = false,
  });

  final double tamano;
  final bool claro;
  final bool conNombre;
  final bool conDescripcion;
  final bool conEslogan;

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(
      'assets/brand/rpa_logo.png',
      width: tamano,
      height: tamano,
      semanticLabel: conNombre ? null : 'RPA',
      excludeFromSemantics: conNombre,
    );
    if (!conNombre) return logo;
    final nombre = Text(
      'RPA',
      style: TextStyle(
        fontFamily: Ipesa.fuenteTitulos,
        fontSize: tamano * .5,
        height: 1.05,
        fontWeight: FontWeight.w800,
        letterSpacing: tamano * .04,
        color: claro ? Colors.white : Colors.black,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        SizedBox(width: tamano * .28),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              nombre,
              if (conDescripcion)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'REGISTRO DE PEDIDOS ATENDIDOS',
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: (tamano * .18).clamp(9.5, 11.5),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: claro
                          ? Ipesa.suaveSobrePetroleo
                          : Ipesa.textoSuave,
                    ),
                  ),
                ),
              if (conEslogan)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: EsloganRpa(
                    tamano: (tamano * .3).clamp(12.0, 15.0),
                    claro: claro,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "La IA lo vio, el cliente lo firmó." en dos tonos, sin fondo.
class EsloganRpa extends StatelessWidget {
  const EsloganRpa({super.key, this.tamano = 16, this.claro = false});

  final double tamano;
  final bool claro;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      fontFamily: Ipesa.fuenteTitulos,
      fontSize: tamano,
      height: 1.25,
      fontWeight: FontWeight.w700,
      letterSpacing: .1,
    );
    return Text.rich(
      TextSpan(
        style: estilo,
        children: [
          TextSpan(
            text: 'La IA lo vio, ',
            style: TextStyle(color: claro ? Colors.white : Ipesa.petroleo),
          ),
          TextSpan(
            text: 'el cliente lo firmó.',
            style: TextStyle(
              color: claro ? const Color(0xFF7FD3C4) : Ipesa.turquesa,
            ),
          ),
        ],
      ),
      semanticsLabel: esloganRpa,
    );
  }
}
