import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'escena_ruta.dart';
import 'pasos_registro.dart';

const _negro = Color(0xFF000000);
const _selloVerde = Color(0xFF1E6B4A);

/// Al abrir una guía en Rastrear: la pantalla se atenúa y al
/// frente una ventana con la marca IPESA, un mensaje y los pasos reales
/// de la búsqueda (solo iconos). Solo se mueven los pasos.
class VentanaBusqueda extends StatelessWidget {
  const VentanaBusqueda({super.key, required this.pasos, required this.lista});

  final List<PasoRegistro> pasos;

  /// Ya terminó: se ve "¡Listo!" un momento antes de abrir.
  final bool lista;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Bloquea los toques mientras busca.
        const ModalBarrier(dismissible: false),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: ColoredBox(color: cieloEscena.withValues(alpha: 0.72)),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x400F4C5C),
                      blurRadius: 40,
                      offset: Offset(0, 18),
                      spreadRadius: -12,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _Sello(),
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _Mensaje(
                          key: ValueKey(lista),
                          titulo: lista
                              ? '¡Listo! Encontramos tu guía'
                              : 'Estamos buscando tu solicitud',
                          detalle: lista
                              ? 'Abriéndola…'
                              : 'Esto toma solo unos segundos',
                        ),
                      ),
                      const SizedBox(height: 14),
                      PasosRegistro(pasos: pasos),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({super.key, required this.titulo, required this.detalle});

  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: Ipesa.fuenteTitulos,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            height: 1.25,
            color: Ipesa.petroleo,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          detalle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13.5, color: Ipesa.textoSuave),
        ),
      ],
    );
  }
}

/// El cuadro negro "IPESA" de la guía, fijo: lo que se mueve son los pasos.
class _Sello extends StatelessWidget {
  const _Sello();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _negro,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 18,
            offset: Offset(0, 8),
            spreadRadius: -6,
          ),
        ],
      ),
      child: const Stack(
        children: [
          Center(
            child: Text(
              'IPESA',
              style: TextStyle(
                fontFamily: Ipesa.fuenteTitulos,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 4,
            child: ColoredBox(color: _selloVerde),
          ),
        ],
      ),
    );
  }
}
